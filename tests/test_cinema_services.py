"""r28 service compatibility and commit deadlines, with file transport fakes."""
import unittest
import test_steam_coop_services as base
class CinemaServicesTests(base.SteamCoopTests):
 def setUp(self):
  super().setUp();self.lua.execute('C=M.new(OUTPUT,N,function()return T end,{mission_sync=true,cinema_sync=true})')
 def state(self,**fields):
  defaults=dict(protocol=6,cinema_sync=1,cinema_state=0,cinema_prepared=0,cinema_finished=0,cinema_at=0,cinema_commit_mask=0)
  defaults.update(fields);super().state(**defaults)
 def test_cinematic_commit_is_separate_from_flight_loading(self):
  self.lua.execute("C.join('76561198000000002')");self.state(phase=2,cinema_prepared=3,cinema_state=1,cinema_at=15000)
  self.assertIn('op\t21\narg0\t15000\n',(self.root/'shared-session-command.tsv').read_text())
 def test_old_r27_status_cannot_ack_local_cinema(self):
  self.lua.execute("C.join('76561198000000002')");self.state(protocol=5,phase=1)
  self.lua.execute('assert(C.error and not C.view().connected)')
 def test_done_wait_message_is_derived_from_host_receipts(self):
  self.lua.execute("C.join('76561198000000002')");self.state(phase=2,cinema_state=2,cinema_finished=1)
  self.assertIn('Ожидание второго игрока',self.lua.eval('C.status()'))
if __name__=='__main__':unittest.main()
