"""One-PC lifecycle lab using the mod's native TCP bridge and current session core.
No UE state is synthesized here. Workers use no Steam and no game-memory access.
"""
import argparse, ctypes, json, os, secrets, subprocess, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DLL=ROOT/'build/lifecycle-lab/ac8_lifecycle_lab.dll'

def read(folder):
    try:return dict(line.split('\t',1) for line in (Path(folder)/'shared-session-status.tsv').read_text().splitlines())
    except (OSError,ValueError):return {}

def wait(fn,label,timeout=10):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        value=fn()
        if value:return value
        time.sleep(.025)
    raise AssertionError(label)

def command(folder,op,a=0,b=0,expected=None,reject=0):
    folder=Path(folder);s=read(folder)
    assert s.get('have_snapshot')=='1', 'No authoritative snapshot'
    request=int(s.get('request_ack',0))+1
    epoch,revision=expected or (s['epoch'],s['revision'])
    data=dict(request=request,epoch=epoch,revision=revision,op=op,arg0=a,arg1=b)
    payload=''.join(f'{k}\t{v}\n' for k,v in data.items())
    temp=folder/'shared-session-command.pending'
    temp.write_text(payload,encoding='ascii')
    temp.replace(folder/'shared-session-command.tsv')
    wait(lambda:int(read(folder).get('request_confirmed',0))>=request,'command confirmation')
    s=read(folder)
    with (folder/'lab-commands.jsonl').open('a',encoding='utf-8') as f:
        f.write(json.dumps(dict(at=time.time(),command=data,result=s.get('reject'),phase=s.get('phase')))+'\n')
    assert int(s['reject'])==reject,(op,reject,s)
    return s

def worker(role,folder,token,port,dll):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    os.environ.update(AC8_LOCAL_SESSION='25201480',AC8_MISSION_SYNC='25201480',
        AC8_LOCAL_HANGAR='25201480',AC8_LOCAL_ROLE=role,AC8_LOCAL_PORT=str(port),
        AC8_LOCAL_TOKEN=str(token),AC8_COOP_RECON_OUTPUT=str(folder))
    lib=ctypes.CDLL(str(Path(dll).resolve()))
    lib.luaopen_ac8_local_start.argtypes=[ctypes.c_void_p]
    lib.luaopen_ac8_local_stop.argtypes=[ctypes.c_void_p]
    lib.ac8_local_wait_stopped.argtypes=[ctypes.c_ulong]
    lib.ac8_local_wait_stopped.restype=ctypes.c_int
    lib.luaopen_ac8_local_start(None)
    try:
        while not(folder/'stop').exists():
            s=read(folder)
            if s.get('transport') in ('error','disconnected','stopped'):break
            time.sleep(.05)
    finally:
        lib.luaopen_ac8_local_stop(None)
        assert lib.ac8_local_wait_stopped(5000)==1

class Pair:
    def __init__(self,root):
        self.root=Path(root);self.root.mkdir(parents=True)
        self.children=[];self.host=self.root/'host';self.guest=self.root/'guest'
        token=secrets.randbelow(2**53-1)+1
        self.start('host',token,0)
        port=wait(lambda:read(self.host).get('port'),'host port')
        self.start('guest',token,port)
        wait(lambda:read(self.guest).get('have_snapshot')=='1','guest connection')
    def start(self,role,token,port):
        folder=self.root/role;folder.mkdir()
        f=(folder/'worker.log').open('w')
        self.children.append(subprocess.Popen([sys.executable,__file__,'worker',role,str(folder),str(token),str(port),str(DLL)],stdout=f,stderr=subprocess.STDOUT))
        f.close()
    def cmd(self,role,op,a=0,b=0,**kw):
        if role=='guest':
            wait(lambda:all(read(self.guest).get(k)==read(self.host).get(k)for k in ('epoch','revision','changes')),'fresh guest')
        result=command(self.root/role,op,a,b,**kw)
        if role=='guest':
            # The acknowledgement snapshot can reach the guest before the host
            # publishes its next status file. Do not assert against that old file.
            wait(lambda:int(read(self.host).get('changes',0))>=int(result['changes']),'host status publication')
        return result
    def phase(self,n):return wait(lambda:read(self.host)if read(self.host).get('phase')==str(n) else None,'phase '+str(n))
    def barrier(self,cinema=False):
        field='cinema_at' if cinema else 'release_at';op=21 if cinema else 13
        d=int(wait(lambda:read(self.host).get(field)if int(read(self.host).get(field,0))else None,'deadline'))
        self.cmd('host',op,d&0xffffffff,d>>32)
        self.cmd('guest',op,d&0xffffffff,d>>32)
        wait(lambda:read(self.host).get(field)=='0','barrier release',5)
    def close(self):
        for role in ('host','guest'):(self.root/role/'stop').touch()
        for p in self.children:
            try:p.wait(timeout=7)
            except subprocess.TimeoutExpired:
                p.terminate();p.wait(timeout=5)
                raise AssertionError('Native lab worker did not stop normally')
            assert p.returncode==0
    def lobby(self):
        self.cmd('host',2,6,1);self.cmd('guest',3,23)
        self.cmd('host',1,1);self.cmd('guest',1,1)
    def intro(self):
        self.lobby();self.cmd('host',9,1)
        self.cmd('host',19,1);self.cmd('guest',19,1)
        self.cmd('host',7);self.cmd('guest',7)
        self.barrier();self.phase(2);self.barrier(True)

def trial(output):
    output=Path(output);checks=[]
    def passed(name):checks.append(name)
    p=Pair(output/'full')
    try:
        p.lobby()
        old=(read(p.host)['epoch'],read(p.host)['revision'])
        p.cmd('host',2,6,2);assert read(p.host)['ready_mask']=='0'
        p.cmd('guest',1,1,expected=old,reject=3);passed('mission_change_resets_ready_and_rejects_stale')
        p.cmd('host',2,6,1);p.cmd('host',1,1);p.cmd('guest',1,1)
        p.cmd('host',9,1);p.cmd('host',7,reject=5)
        p.cmd('host',19,1);p.cmd('host',7)
        time.sleep(2);assert read(p.host)['phase']=='1'and read(p.host)['loaded_mask']=='1'
        p.cmd('guest',19,1);p.cmd('guest',7)
        d=int(wait(lambda:read(p.host).get('release_at')if int(read(p.host).get('release_at',0))else None,'deadline'))
        p.cmd('host',13,d&0xffffffff,d>>32)
        wait(lambda:int(read(p.host).get('release_at',0))>d,'rearm')
        p.cmd('guest',13,d&0xffffffff,d>>32,reject=3);p.barrier();p.phase(2);p.barrier(True)
        passed('delayed_intro_and_expired_commit')
        p.cmd('host',20,1);p.cmd('host',8,1,reject=5)
        time.sleep(2);assert read(p.host)['phase']=='2'and read(p.host)['cinema_finished']=='1'
        p.cmd('guest',20,1);p.barrier(True)
        old=(read(p.host)['epoch'],read(p.host)['revision'])
        p.cmd('host',14,2);p.cmd('guest',5,1,expected=old,reject=3)
        for role in ('host','guest'):p.cmd(role,19,2)
        p.barrier(True)
        p.cmd('host',5,2);n=read(p.host)['changes'];p.cmd('host',5,2)
        assert read(p.host)['vote_mask']=='1'and read(p.host)['changes']==n
        time.sleep(2);assert read(p.host)['cinema_state']=='2'
        p.cmd('guest',5,2);p.barrier(True)
        p.cmd('host',8,2,reject=5)
        for role in ('host','guest'):p.cmd(role,20,2)
        p.cmd('host',8,2);p.phase(3)
        passed('natural_finish_waits_peer_two_votes_and_old_scene')
        p.cmd('host',11,1,23);time.sleep(2);assert read(p.host)['phase']=='3'
        p.cmd('guest',7);p.barrier();p.phase(4)
        assert read(p.host)['ready_mask']=='0'
        p.cmd('host',6,reject=5)
        p.cmd('host',1,1);p.cmd('guest',1,1);p.cmd('guest',3,22)
        assert read(p.host)['ready_mask']=='1'
        p.cmd('host',6,reject=5);p.cmd('guest',3,23);p.cmd('guest',1,1)
        old=(read(p.host)['epoch'],read(p.host)['revision'])
        p.cmd('host',6);generation=read(p.host)['generation']
        p.cmd('host',6,expected=old,reject=3)
        p.cmd('host',12);time.sleep(2);assert read(p.host)['phase']=='5'
        p.cmd('guest',7);p.barrier();p.phase(6)
        assert read(p.host)['generation']==generation=='1'
        passed('hangar_new_ready_loadout_reset_single_sortie_delayed_load')
        (p.guest/'stop').touch();wait(lambda:read(p.host).get('phase')=='8','peer loss')
        assert read(p.host)['stop_reason']=='3';passed('flight_disconnect_stops')
    finally:p.close()
    for label in ('lobby','loading','cancel'):
        p=Pair(output/label)
        try:
            p.lobby()
            if label!='lobby':p.cmd('host',9,1)
            if label=='cancel':
                p.cmd('guest',23,int(read(p.host)['generation']))
                assert read(p.host)['phase']=='8'and read(p.host)['stop_reason']=='1'
            else:
                (p.guest/'stop').touch()
                wait(lambda:read(p.host).get('connected')=='0','disconnect')
                assert read(p.host)['phase']==('0'if label=='lobby'else'8')
                if label=='lobby':assert read(p.host)['ready_mask']=='0'
                else:assert read(p.host)['stop_reason']=='3'
            passed(label+'_safe_disconnect_or_cancel')
        finally:p.close()
    result=dict(result='PASS',protocol=8,transport='native TCP loopback',checks=checks,gameplay_tested=False)
    (output/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':
    a=sys.argv[1:]
    if a[0]=='worker':worker(*a[1:])
    elif a[0]=='test':trial(a[1])
    elif a[0]=='status':
        s=read(a[1]);s.pop('config_token',None);print(json.dumps(s,indent=2))
    elif a[0]=='cmd':
        s=command(a[1],*map(int,a[2:]));s.pop('config_token',None);print(json.dumps(s,indent=2))
