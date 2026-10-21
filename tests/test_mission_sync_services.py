from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/mission_sync_services.lua'
class ServicesTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True)
  self.l.execute(r'''
   FILES={};NOW=100;WRITES=0
   io.open=function(path,mode)
    if mode=='wb'then WRITES=WRITES+1;FILES[path]='';local f={close=function()end};f.write=function(_,text)FILES[path]=FILES[path]..text;return f end;return f end
    if not FILES[path]then return nil end;return {read=function()return FILES[path]end,close=function()end}
   end
   N={clock=function()FILES['out/sync-clock.tsv']='tick\t'..NOW..'\n'end,start=function()end}
   S={config_token='123',mission_sync='1',local_tick='100',have_snapshot='1',connected='1',phase='0',epoch='1',revision='2',request_ack='0',request_confirmed='0',reject='0',mission='6',difficulty='1',guest_aircraft='23',ready_mask='3',commit_mask='0',release_at='0',scene='1'}
   function snapshot()local a={};for k,v in pairs(S)do a[#a+1]=k..'\t'..v..'\n'end;FILES['out/shared-session-status.tsv']=table.concat(a)end
  ''')
  self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'));self.l.execute("C=M.new('out','123',N,function()end);C.selection=true;snapshot();C.poll()")
 def runlua(self,s):self.l.execute(s)
 def val(self,s):return self.l.eval(s)
 def test_missing_confirmation_keeps_request_and_blocks_repeats(self):
  self.runlua('C.ready();NOW=12000;S.local_tick=tostring(NOW);snapshot();C.poll()')
  self.assertIsNotNone(self.val('C.pending'));self.assertEqual(self.val('WRITES'),1);self.assertRaises(Exception,self.runlua,'C.ready()')
 def test_only_own_confirmed_request_releases_pending(self):
  self.runlua("C.ready();S.request_ack='1';snapshot();C.poll()")
  self.assertIsNotNone(self.val('C.pending'))
  self.runlua("S.request_confirmed='1';snapshot();C.poll()")
  self.assertIsNone(self.val('C.pending'))
 def test_rearmed_start_commits_latest_exact_deadline(self):
  self.runlua("S.phase='5';S.release_at='1000';snapshot();C.poll()")
  self.assertIn('arg0\t1000',self.val("FILES['out/shared-session-command.tsv']"))
  self.runlua("S.request_confirmed='1';S.request_ack='1';S.release_at='3000';snapshot();C.poll()")
  self.assertIn('arg0\t3000',self.val("FILES['out/shared-session-command.tsv']"))
 def test_stale_state_cannot_start_sortie(self):
  self.runlua("S.phase='4';S.host_aircraft='7';snapshot();C.poll();NOW=9000;C.poll()")
  self.assertFalse(self.val('C.view().connected'));self.assertFalse(self.val('C.view().can_start_flight'));self.assertRaises(Exception,self.runlua,'C.start_flight()')
 def test_old_run_token_cannot_replace_current_state(self):
  self.runlua("S.config_token='other';S.phase='6';snapshot();C.poll()")
  self.assertEqual(self.val('C.view().phase'),0)
 def test_start_permission_requires_both_hangar_readiness_flags(self):
  self.runlua("S.phase='4';S.host_aircraft='7';S.ready_mask='1';snapshot();C.poll()")
  self.assertFalse(self.val('C.view().can_start_flight'))
  self.runlua("S.ready_mask='3';snapshot();C.poll()")
  self.assertTrue(self.val('C.view().can_start_flight'))
if __name__=='__main__':unittest.main()
