"""Evidence-gated manual-UI lab. Does not press keys or claim automatic UE transitions.

Each stage captures fresh real-engine observations before sending host receipts.
Guest engine readiness is deliberately simulated, not evidence of a second scene.
"""
import hashlib,json,sys,time
from pathlib import Path
from lifecycle_lab import Pair,read,wait

class Live(Pair):
    def __init__(self,root):
        self.root=Path(root);self.host=self.root/'host';self.guest=self.root/'guest'
    def observe(self,field):
        p=self.host/'game-observation.tsv'
        raw=p.read_bytes();s=dict(line.split('\t',1)for line in raw.decode().splitlines())
        assert 0<=time.time()-int(s['utc'])<6, 'stale engine observation'
        if field=='briefing_world':assert '/Briefing/PL_Briefing' in s.get('world',''),s
        else:assert s.get(field)=='1',(field,s)
        self.note('engine_observation',dict(field=field,sha256=hashlib.sha256(raw).hexdigest(),state=s))
        return s
    def note(self,event,data):
        with(self.root/'live-checks.jsonl').open('a',encoding='utf-8')as f:
            f.write(json.dumps(dict(at=time.time(),event=event,data=data))+'\n')
    def run(self,step):
        self.note('step_started',step)
        if step=='lobby':
            self.observe('main_menu');self.lobby()
            old=(read(self.host)['epoch'],read(self.host)['revision'])
            self.cmd('host',2,6,2);assert read(self.host)['ready_mask']=='0'
            self.cmd('guest',1,1,expected=old,reject=3)
            self.cmd('host',2,6,1);self.cmd('host',1,1);self.cmd('guest',1,1)
            n=read(self.host)['changes'];self.cmd('guest',1,1)
            assert read(self.host)['changes']==n
        elif step=='begin':
            self.observe('narrative');self.cmd('host',9,1)
        elif step=='intro':
            self.observe('briefing_world')
            self.cmd('host',19,1);self.cmd('host',7)
            time.sleep(5);assert read(self.host)['phase']=='1'and read(self.host)['loaded_mask']=='1'
            self.cmd('guest',19,1);self.cmd('guest',7);self.barrier();self.phase(2);self.barrier(True)
            self.cmd('host',5,1);n=read(self.host)['changes'];self.cmd('host',5,1)
            assert read(self.host)['vote_mask']=='1'and read(self.host)['changes']==n
            time.sleep(5);self.observe('briefing_world');assert read(self.host)['cinema_state']=='2'
            self.cmd('guest',5,1);self.barrier(True)
            assert read(self.host)['cinema_state']=='4'
            self.note('ui_skip_authorized','Both votes; operator may now use stock skip. No native skip hook.')
        elif step=='briefing':
            self.observe('briefing');self.cmd('host',20,1)
            self.cmd('host',8,1,reject=5)
            time.sleep(8);self.observe('briefing')
            assert read(self.host)['phase']=='2'and read(self.host)['cinema_finished']=='1'
            self.cmd('guest',20,1);self.cmd('host',8,1);self.phase(3)
            self.note('ui_hangar_authorized','Both finished; operator may open stock hangar.')
        elif step=='hangar':
            self.observe('hangar_standby')
            # Plane IDs require visual confirmation in the stock hangar before this step.
            confirm=json.loads((self.root/'hangar-visual-confirmation.json').read_text())
            assert confirm['host_aircraft']==1 and confirm['guest_aircraft']==23
            assert 0<=time.time()-confirm['at']<120
            self.cmd('host',11,1,23);time.sleep(8);self.observe('hangar_standby')
            assert read(self.host)['phase']=='3';self.cmd('guest',7);self.barrier();self.phase(4)
            self.cmd('host',6,reject=5)
            self.cmd('host',1,1);self.cmd('guest',1,1);self.cmd('guest',3,22)
            assert read(self.host)['ready_mask']=='1';self.cmd('host',6,reject=5)
            self.cmd('guest',3,23);self.cmd('guest',1,1)
            old=(read(self.host)['epoch'],read(self.host)['revision'])
            self.cmd('host',6);self.cmd('host',6,expected=old,reject=3)
            assert read(self.host)['generation']=='1'
            self.note('ui_sortie_authorized','One generation; operator may press stock sortie once.')
        elif step=='flight':
            s=self.observe('flight');assert s['paused']=='1','Pause through stock UI first'
            self.cmd('host',12);time.sleep(8);s2=self.observe('flight')
            assert s2['paused']=='1'and abs(float(s['world_time'])-float(s2['world_time']))<.01
            assert read(self.host)['phase']=='5';self.cmd('guest',7);self.barrier();self.phase(6)
            self.note('ui_resume_authorized','Both loaded; operator may resume stock game.')
        elif step=='hangar_ready_retry':
            self.observe('hangar_standby');assert read(self.host)['phase']=='4'
            self.cmd('guest',3,23);self.cmd('host',1,1);self.cmd('guest',1,1)
            self.cmd('guest',3,22);assert read(self.host)['ready_mask']=='1'
            self.cmd('host',6,reject=5);self.cmd('guest',3,23);self.cmd('guest',1,1)
            old=(read(self.host)['epoch'],read(self.host)['revision'])
            self.cmd('host',6);self.cmd('host',6,expected=old,reject=3)
            assert read(self.host)['generation']=='1'
            self.note('ui_sortie_authorized','Readiness retry after harness publication race; stock sortie once.')
        elif step=='disconnect':
            before=self.observe('flight');assert read(self.host)['phase']=='6'
            assert before.get('disconnect_stop')=='armed'and before['paused']=='0'
            started=time.monotonic()
            (self.guest/'stop').touch();wait(lambda:read(self.host).get('phase')=='8','disconnect stops session')
            assert read(self.host)['stop_reason']=='3'
            def held():
                try:
                    s=dict(line.split('\t',1)for line in (self.host/'game-observation.tsv').read_text().splitlines())
                    return s.get('disconnect_stop')=='held'and s.get('paused')=='1'
                except (OSError,ValueError):return False
            wait(held,'actual engine pause',timeout=8)
            detected=time.monotonic()-started
            baseline=self.observe('flight');time.sleep(8);after=self.observe('flight')
            advanced=float(after['world_time'])-float(baseline['world_time'])
            displacement=sum((float(after[k])-float(baseline[k]))**2 for k in ('x','y','z'))**.5
            result=dict(before=before,baseline=baseline,after=after,confirmation_seconds=detected,
                elapsed_game_time=advanced,displacement=displacement,
                engine_automatically_held=after['paused']=='1'and abs(advanced)<.01 and displacement<.01,
                limit='One real host world; guest is headless native TCP client. No second renderer.')
            self.note('engine_after_disconnect',result)
            assert result['engine_automatically_held'],result
        else:raise ValueError(step)
        if step=='disconnect':
            self.note('protocol_step_passed',step)
            print('disconnect: protocol AND real host world pause PASS (8-second observation)')
        else:
            self.note('step_passed',step);print(step+' PASS (manual UI / simulated guest)')

if __name__=='__main__':
    run=Live(sys.argv[1])
    try:run.run(sys.argv[2])
    except Exception as e:
        run.note('step_failed',dict(step=sys.argv[2],exception=type(e).__name__,
            phase=read(run.host).get('phase'),changes=read(run.host).get('changes')))
        raise
