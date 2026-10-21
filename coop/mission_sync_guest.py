"""A virtual guest's loading/render lifecycle, using the same Windows clock as the host."""
import ctypes
import time

def windows_tick():
    fn=ctypes.windll.kernel32.GetTickCount64
    fn.restype=ctypes.c_ulonglong
    return fn()

class SyncGuest:
    def __init__(self,client,clock=windows_tick):
        self.client=client;self.clock=clock
        self.delays={1:8000,3:2000,5:10000,'commit':0}
        self.loads={};self.commits={};self.released=set();self.last=None;self.hold_started=None;self.hold_latched=False
    def set_delay(self,key,milliseconds):
        if key not in self.delays or not 0<=milliseconds<=60000:raise ValueError('Задержка должна быть от 0 до 60000 мс.')
        self.delays[key]=milliseconds
    def send(self,op,arg=0,arg1=0,description='подтверждение этапа',expected=None):
        s=self.client.snapshot
        expected=expected or(s['epoch'],s['revision'])
        self.client.command(op,arg,description,arg1,expected)
        self.last=(op,arg,arg1,expected)
    def vote(self):
        s=self.client.snapshot
        if s.get('phase')!='2':raise ValueError('Нет текущей общей катсцены.')
        self.send(5,int(s['scene']),description='голос гостя за пропуск')
    def repeat_last(self):
        if not self.last:raise ValueError('Нет команды для повтора.')
        op,arg,arg1,expected=self.last
        self.send(op,arg,arg1,'повтор прежней команды',expected)
    def hold(self,down,threshold_ms):
        now=self.clock()
        if threshold_ms<=0:raise ValueError('Порог удержания должен быть положительным.')
        if not down:self.hold_started=None;self.hold_latched=False;return
        if self.hold_latched:return
        if self.client.snapshot.get('phase')!='2':self.hold_started=None;return
        if self.hold_started is None:self.hold_started=now
        if now-self.hold_started>=threshold_ms and not self.client.pending:
            if not(int(self.client.snapshot.get('vote_mask',0))&2):self.vote()
            self.hold_latched=True
    def update(self):
        c=self.client
        if not c.connected:return
        s=c.snapshot;phase=int(s.get('phase',0));epoch=int(s.get('epoch',0));now=self.clock()
        key=(phase,epoch)
        if phase in(1,3,5):
            due=self.loads.setdefault(key,now+self.delays[phase])
            if not(int(s.get('loaded_mask',0))&2)and now>=due and not c.pending:
                self.send(7,description='виртуальный мир загружен');c.log('simulator_loaded',f'phase={phase} epoch={epoch} tick={now}')
        deadline=int(s.get('release_at',0))
        if deadline:
            due=self.commits.setdefault((epoch,deadline),now+self.delays['commit'])
            if int(s.get('commit_mask',0))&2==0 and now>=due and not c.pending:
                self.send(13,deadline&0xffffffff,deadline>>32,'подтверждение общего времени старта')
            if s.get('commit_mask')=='3'and now>=deadline and(epoch,deadline)not in self.released:
                self.released.add((epoch,deadline))
                c.log('simulator_release',f'phase={phase} epoch={epoch} planned={deadline} actual={now} lateness_ms={now-deadline}')
