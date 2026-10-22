"""Actual file receipts gate QuitGame; no game or Steam is started."""
import unittest
import test_steam_lobby as base

class ShutdownServicesTests(unittest.TestCase):
 def setUp(self):
  base.SteamLobbyTests.setUp(self)
  self.lua.execute("BEGINS=0;POLLS=0;N.shutdown_begin=function()BEGINS=BEGINS+1 end;N.shutdown_poll=function()POLLS=POLLS+1 end;C=M.new(OUTPUT,N,function()return T end,{owner_native=true});C.join('76561198000000002')")
 def receipt(self,**fields):
  d=dict(format='ac8-native-shutdown-v1',config_token=self.lua.eval('C.token'),requested=1,worker_running=0,callbacks_registered=0,complete=1,failed=0)
  d.update(fields);(self.root/'native-shutdown.tsv').write_text(''.join(f'{k}\t{v}\n'for k,v in d.items()))
 def test_old_receipt_removed_and_same_session_required(self):
  self.receipt();self.lua.execute('assert(not C.shutdown())');self.receipt(config_token='old');self.lua.execute('assert(not C.shutdown())');self.receipt();self.lua.execute('assert(C.shutdown() and BEGINS==1)')
 def test_all_stop_conditions_are_required(self):
  self.lua.execute('assert(not C.shutdown())')
  for field in ['worker_running','callbacks_registered','failed']:
   self.receipt(**{field:1});self.lua.execute('assert(not C.shutdown())')
  self.receipt(requested=0);self.lua.execute('assert(not C.shutdown())');self.receipt();self.lua.execute('assert(C.shutdown())')
 def test_polling_cannot_restart_steam_during_shutdown(self):
  self.lua.execute("C.shutdown();local n=calls.tick;N.invites_tick=function()error('must not run')end;C.poll();assert(calls.tick==n);T=T+11;assert(not C.shutdown() and C.error)")

if __name__=='__main__':unittest.main()
