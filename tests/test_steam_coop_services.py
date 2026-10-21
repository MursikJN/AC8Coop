"""File-boundary tests for Steam mission phases; never launch a game or Steam."""
import unittest
import test_steam_lobby as base

class SteamCoopTests(unittest.TestCase):
 host=base.SteamLobbyTests.host
 def setUp(self):
  base.SteamLobbyTests.setUp(self);self.lua.execute('C=M.new(OUTPUT,N,function()return T end,{mission_sync=true})')
 def state(self,**fields):
  defaults=dict(protocol=5,mission_sync=1,phase=0,local_tick=10000,host_tick=10000,clock_ready=1,release_at=0,commit_mask=0,scene=1,scene_return=3,generation=0)
  defaults.update(fields);base.SteamLobbyTests.state(self,**defaults)
 def test_host_creation_sends_selected_difficulty_after_own_snapshot(self):
  self.lua.execute('assert(not pcall(C.create,6,4));assert(calls.start==0)')
 def test_steam_lobby_has_real_mission_phase(self):
  self.host();self.state(ready_mask=3,phase=0)
  self.lua.execute('assert(C.view().can_open_hangar and not C.view().lobby_only);C.open_hangar()')
  self.assertIn('op\t9\narg0\t1\n',(self.root/'shared-session-command.tsv').read_text())
 def test_guest_does_not_auto_report_loaded_from_connection(self):
  self.lua.execute("C.join('76561198000000002')");self.state(phase=5,generation=1)
  self.assertFalse((self.root/'shared-session-command.tsv').exists())
 def test_guest_cannot_launch_or_advance_host_scene(self):
  self.lua.execute("C.join('76561198000000002')");self.state(phase=4,ready_mask=3,host_aircraft=7)
  self.lua.execute('assert(not C.view().can_start_flight);assert(not pcall(C.start_flight));assert(not pcall(C.scene_ended))')
 def test_guest_commit_requires_calibrated_clock(self):
  self.lua.execute("C.join('76561198000000002')");self.state(phase=5,generation=1,release_at=12000,clock_ready=0)
  self.assertFalse((self.root/'shared-session-command.tsv').exists())
  self.state(phase=5,generation=1,release_at=12000,clock_ready=1)
  self.assertIn('op\t13\narg0\t12000\n',(self.root/'shared-session-command.tsv').read_text())
 def test_new_hangar_readiness_and_repeat_confirmation(self):
  self.host();self.state(phase=4,ready_mask=2,host_aircraft=7)
  self.lua.execute('C.ready()');self.state(phase=4,ready_mask=3,host_aircraft=7,request_ack=2,request_confirmed=2)
  self.lua.execute('assert(C.view().can_start_flight);C.ready()')
  self.state(phase=4,ready_mask=2,host_aircraft=7,request_ack=3,request_confirmed=3)
  self.lua.execute('assert(not C.view().can_start_flight);C.ready()')
 def test_wrong_protocol_never_arms_mission(self):
  self.lua.execute("C.join('76561198000000002')");self.state(protocol=3,ready_mask=3)
  self.lua.execute('assert(not C.view().connected and not C.view().can_open_hangar)')

if __name__=='__main__':unittest.main()
