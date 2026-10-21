"""r29 service boundaries; no game or Steam process."""
import unittest
import test_steam_lobby as base
class SessionPolicyServicesTests(unittest.TestCase):
 def setUp(self):base.SteamLobbyTests.setUp(self)
 def start(self,role='host'):
  self.lua.execute(f"C=M.new(OUTPUT,N,function()return T end,{{mission_sync=true,cinema_sync=true,session_policy=true,launch_role='{role}'}})")
  if role=='host':self.lua.execute('C.create(6,1)');self.state();self.state(request_ack=1,request_confirmed=1)
  else:self.lua.execute("C.join('76561198000000002')");self.state()
 def state(self,**fields):
  d=dict(protocol=7,mission_sync=1,cinema_sync=1,session_policy=1,host_progress_only=1,phase=0,generation=1,scene=1,scene_return=3,clock_ready=1,host_tick=10000,release_at=0,cinema_at=0,cinema_state=0,cinema_prepared=0,cinema_finished=0,cinema_commit_mask=0,commit_mask=0,loaded_mask=0,restart_id=0,restart_ack=0,stop_reason=0)
  d.update(fields);base.SteamLobbyTests.state(self,**d)
 def test_role_is_fixed_to_save_policy(self):
  self.start();self.lua.execute("C.leave();C.active=false;C.closing=false;assert(not pcall(C.join,'76561198000000002'))")
 def test_guest_cannot_restart(self):
  self.start('guest');self.state(phase=6);self.lua.execute('assert(not C.view().can_restart and not pcall(C.restart))')
 def test_host_restart_uses_current_attempt(self):
  self.start();self.state(phase=6,generation=3);self.lua.execute('assert(C.view().can_restart);C.restart()')
  self.assertIn('op\t22\narg0\t3\n',(self.root/'shared-session-command.tsv').read_text())
 def test_cancel_supersedes_a_pending_ordinary_request(self):
  self.start('guest');self.state(phase=5,release_at=12000);self.lua.execute('assert(C.pending);C.cancel();assert(C.pending.request==2)')
  text=(self.root/'session-emergency.tsv').read_text();self.assertIn('op\t23\ngeneration\t1\n',text)
  self.lua.execute('assert(not C.view().can_cancel and not pcall(C.cancel))')
 def test_stop_does_not_allow_invites_or_readiness(self):
  self.start();self.state(phase=8,stop_reason=3,connected=0)
  self.lua.execute('assert(not C.view().can_invite and not C.view().can_ready and C.status():find("потеряна",1,true))')
 def test_stale_local_worker_requests_one_fault_and_disables_actions(self):
  self.start();self.state(phase=6);self.lua.execute('T=T+6;C.poll();assert(C.local_failure and not C.view().can_ready);C.poll()')
  text=(self.root/'session-emergency.tsv').read_text();self.assertIn('op\t24\n',text);self.assertEqual(self.lua.eval('C.sequence'),2)
 def test_old_protocol_never_arms_policy_actions(self):
  self.start('guest');self.state(protocol=6);self.lua.execute('assert(C.error and not C.view().connected)')
 def test_hangar_loadout_update_is_host_only(self):
  self.start();self.state(phase=4,ready_mask=3,host_aircraft=7);self.lua.execute('C.host_loadout(9)')
  self.assertIn('op\t3\narg0\t9\n',(self.root/'shared-session-command.tsv').read_text())
 def test_new_room_after_using_a_world_requires_a_new_process(self):
  self.start();self.state(phase=5);self.lua.execute('C.active=false;assert(not pcall(C.create,6,1))')
 def test_local_failure_blocks_stale_green_launch_button(self):
  self.start();self.state(phase=4,ready_mask=3,host_aircraft=7);self.lua.execute("C.local_failure='paused safety';assert(not C.view().can_ready and not C.view().can_start_flight and not pcall(C.start_flight))")
if __name__=='__main__':unittest.main()
