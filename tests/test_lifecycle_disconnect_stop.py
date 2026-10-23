from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
class StopTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute('''
   calls={};events={};flags=0;held=false;override=0;bad=false
   pause={bootstrap=function()table.insert(calls,'bootstrap')end,
    command=function(op)
     table.insert(calls,op);if bad then error('identity_changed')end
     if op=='acquire'then held=true;flags=flags|32 end
     return {held=held and '1'or'0',paused=flags~=0 and '1'or'0',flags=tostring(flags),applied=tostring(flags),override=tostring(override)}
    end}
   rows={flight=1,active=1}
  ''')
  self.lua.globals().M=self.lua.execute((ROOT/'probe/LifecycleLab/Scripts/disconnect_stop.lua').read_text())
  self.lua.execute("p=M.new(pause,'123',function(s,r)table.insert(events,s..':'..r)end)")
 def status(self,phase=6,reason=0,epoch=3,tick=1,token='123',connected=1):
  return f'format\tac8-session-status-v2\nconfig_token\t{token}\nrole\thost\nhave_snapshot\t1\nphase\t{phase}\nstop_reason\t{reason}\nepoch\t{epoch}\nlocal_tick\t{tick}\nconnected\t{connected}\n'
 def step(self,now=1,**kwargs):
  g=self.lua.globals();return g.p.step(self.status(**kwargs),g.rows,now)
 def test_loss_holds_once_and_never_resumes_on_repeated_or_connected_snapshot(self):
  self.assertEqual('armed',self.step())
  self.assertEqual('held',self.step(2,phase=8,reason=3,epoch=4,connected=0))
  self.step(3,phase=8,reason=3,epoch=4,connected=0);self.step(4,epoch=5)
  calls=list(self.lua.globals().calls.values())
  self.assertEqual(calls.count('acquire'),1);self.assertNotIn('release',calls)
  self.assertEqual(1,sum(s.startswith('loss_detected:') for s in self.lua.globals().events.values()))
 def test_lobby_loss_does_not_pause(self):
  self.assertEqual('idle',self.step(phase=0,connected=0))
  self.assertEqual('idle',self.step(phase=8,reason=3))
 def test_no_flight_no_arm(self):
  self.lua.globals().rows.flight=0;self.step();self.step(phase=8,reason=3)
  self.assertFalse(self.lua.globals().p.armed)
 def test_existing_stock_bit_waits_then_acquires_without_stealing(self):
  self.step();self.lua.globals().flags=48
  self.assertEqual('waiting_for_stock_pause',self.step(2,phase=8,reason=3,epoch=4))
  self.assertFalse(self.lua.globals().held)
  self.lua.globals().flags=16
  self.assertEqual('held',self.step(3,phase=8,reason=3,epoch=4))
  self.assertEqual(48,self.lua.globals().flags)
 def test_override_and_other_pause_bits_preserved(self):
  self.step();self.lua.globals().override=2;self.lua.globals().flags=8
  self.assertEqual('held',self.step(2,phase=8,reason=3,epoch=4))
  self.assertEqual(2,self.lua.globals().override);self.assertEqual(40,self.lua.globals().flags)
 def test_native_failure_latches_without_repeated_calls(self):
  self.step();self.lua.globals().bad=True
  self.assertEqual('failed',self.step(2,phase=8,reason=3))
  n=len(self.lua.globals().calls);self.step(3,phase=8,reason=3)
  self.assertEqual(n,len(self.lua.globals().calls))
 def test_wrong_token_duplicate_malformed_and_regressed_epoch(self):
  self.assertIsNone(self.lua.globals().M.parse(self.status()+'phase\t8\n','123'))
  self.assertIsNone(self.lua.globals().M.parse('broken','123'))
  self.step();self.assertEqual('armed',self.step(2,phase=8,reason=3,token='456'))
  self.assertEqual('armed',self.step(3,phase=8,reason=3,epoch=2))
 def test_stalled_bridge_holds_after_five_seconds(self):
  self.step();self.assertEqual('armed',self.step(5))
  self.assertEqual('held',self.step(6))
 def test_missing_status_after_armed_stops_but_not_in_menu(self):
  g=self.lua.globals();self.assertEqual('idle',g.p.step(None,g.rows,10))
  self.step(11);self.assertEqual('held',g.p.step(None,g.rows,16))
if __name__=='__main__':unittest.main()
