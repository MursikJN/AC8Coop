"""Quiescence and durable restart decisions using fake native boundaries."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/session_lifecycle.lua'
FIXTURE=r'''
FILES={};EVENTS={};ACKS=0;FINAL_ACKS=0;QUITS=0
function event(s)EVENTS[#EVENTS+1]=s end
io.open=function(path,mode)return {write=function(_,...)local a={...};for i,v in ipairs(a)do a[i]=tostring(v)end;FILES[path]=(FILES[path]or'')..table.concat(a);return true end,close=function()return true end}end
os.remove=function(path)FILES[path]=nil;return true end
os.rename=function(a,b)FILES[b]=FILES[a];FILES[a]=nil;return true end
C={token='123',role='host',now=1000,snapshot={phase='6',generation='1',loaded_mask='0',restart_id='1',restart_ack='0',mission='6',difficulty='1',self='76561198000000001',peer='76561198000000002',epoch='5',revision='3'}}
C.view=function()return {connected=CONNECTED~=false}end
C.status=function()return 'session status'end
C.loaded=function()ACKS=ACKS+1 end
C.restart_ack=function()FINAL_ACKS=FINAL_ACKS+1 end
C.fault=function(why)C.local_failure=why;event('fault')end
P={pilot={stop=function()event('pilot_stop')end},role={runtime={stop=function()event('role_unbind')end}},client={stop=function()event('scene_stop')end}}
C.cinema={stop=function()event('cinema_stop')end}
E={hold=function()event('hold');if FAIL_HOLD then error('hold refused')end end,quit=function()event('quit');if FAIL_QUIT then error('quit refused')end;QUITS=QUITS+1 end}
'''
class SessionLifecycleTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(FIXTURE)
  self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'));self.l.execute("R=M.new(C,'out','source',function()end,E)")
 def test_active_flight_keeps_running(self):self.l.execute('assert(not R.update(P));assert(#EVENTS==0 and ACKS==0)')
 def test_disconnect_holds_before_unbinding_controls(self):
  self.l.execute("CONNECTED=false;assert(R.update(P));assert(EVENTS[1]=='hold'and EVENTS[2]=='pilot_stop'and EVENTS[3]=='role_unbind');assert(ACKS==0)")
 def test_stop_is_idempotent_but_reasserts_pause(self):
  self.l.execute("C.snapshot.phase='8';R.update(P);R.update(P);assert(#EVENTS==6 and EVENTS[6]=='hold'and QUITS==0)")
 def test_restart_prepare_requires_real_quiescence(self):
  self.l.execute("C.snapshot.phase='9';FAIL_HOLD=true;R.update(P);assert(R.error and ACKS==0 and QUITS==0)")
 def test_restart_acks_only_after_all_local_teardown(self):
  self.l.execute("C.snapshot.phase='9';R.update(P);assert(ACKS==1 and EVENTS[5]=='cinema_stop');C.snapshot.loaded_mask='1';R.update(P);assert(ACKS==1)")
 def test_guest_waits_for_seal_then_writes_ticket_before_exit(self):
  self.l.execute("C.role='guest';C.snapshot.phase='10';R.update(P);assert(FINAL_ACKS==1 and QUITS==0);C.snapshot.restart_ack='2';C.pending={};R.update(P);assert(QUITS==0);C.pending=nil;R.update(P);assert(QUITS==1 and FILES['out/session-restart.tsv']:find('sealed\t1',1,true))")
 def test_host_waits_for_guest_confirmation_to_drain(self):
  self.l.execute("C.snapshot.phase='10';C.snapshot.restart_ack='2';R.update(P);assert(QUITS==0);C.now=2999;R.update(P);assert(QUITS==0);C.now=3000;R.update(P);assert(QUITS==1)")
 def test_no_restart_on_unsealed_disconnect(self):
  self.l.execute("CONNECTED=false;C.snapshot.phase='8';R.update(P);assert(QUITS==0 and not FILES['out/session-restart.tsv'])")
 def test_failed_adapter_cannot_keep_flying(self):
  self.l.execute("P.role.error='role failed';assert(R.update(P));assert(C.local_failure and EVENTS[1]=='fault'and EVENTS[2]=='hold')")
 def test_old_error_does_not_cancel_a_fresh_process_restart(self):
  self.l.execute("P.role.error='old error';C.cinema.error='old error';C.snapshot.phase='9';R.update(P);assert(ACKS==1 and not C.local_failure)")
 def test_manual_quit_never_writes_an_auto_restart_ticket(self):
  self.l.execute("R.quit();assert(QUITS==1 and not FILES['out/session-restart.tsv'])")
 def test_failed_quit_is_reported_and_can_be_retried(self):
  self.l.execute('FAIL_QUIT=true;assert(not pcall(R.quit));assert(not R.quitting);FAIL_QUIT=false;R.quit();assert(QUITS==1)')
if __name__=='__main__':unittest.main()
