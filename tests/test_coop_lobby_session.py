"""Two independent lobby controllers connected through an in-memory wire."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/coop_lobby_session.lua'
FIXTURE=r'''
T=0;D={};S={};A={};F={};CAP=true;DROPPED=false
function copy(t)local n={};for k,v in pairs(t)do n[k]=v end;return n end
for i=1,2 do
 local n=i;D[n]={tx=0,launches=0,arms=0,stops=0,reports=0}
 F[n]={detail='fixture',ready=function()D[n].arms=D[n].arms+1 end,stop=function()D[n].stops=D[n].stops+1 end,update=function()end}
 A[n]={now=function()return T end,log=function()end,report=function()D[n].reports=D[n].reports+1 end,
 configure=function()end,connect=function()end,disconnect=function()end,pump=function()end,
 route_supported=function()return CAP end,route_update=function()end,flight_supported=function()return false end,
 launch=function(m,p,l)assert(m==7 and p==23 and l==1);D[n].launches=D[n].launches+1 end,
 publish=function(t)D[n].tx=D[n].tx+1;D[n].frame=copy(t);D[n].frame.sequence=D[n].tx end,
 receive=function()
  if DROPPED then return {connected=false}end
  local peer=D[3-n].frame;if not peer then return nil end
  local p=copy(peer);p.connected=true;p.age_ms=0;p.session=100+n;p.peer_session=103-n;return p
 end}
 S[n]=M.new(A[n],F[n])
end
S[1].configure('host','76561198000000002');S[2].configure('guest','76561198000000001')
function tick()S[1].update();S[2].update();T=T+0.1 end
function both_ready()tick();S[1].ready();tick();S[2].ready();tick()end
'''
class LobbyTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'));self.l.execute(FIXTURE)
 def runlua(self,s):self.l.execute(s)
 def val(self,s):return self.l.eval(s)
 def test_host_cannot_start_before_both_ready(self):
  self.runlua('tick();S[1].ready();tick()');self.assertFalse(self.val('S[1].can_start()'));self.assertRaises(Exception,self.runlua,'S[1].start()')
 def test_guest_cannot_start(self):
  self.runlua('both_ready()');self.assertRaises(Exception,self.runlua,'S[2].start()')
 def test_prepare_ack_commit_launches_both_once(self):
  self.runlua('both_ready();S[1].start()');self.assertEqual(self.val('D[1].launches+D[2].launches'),0)
  self.runlua('for i=1,12 do tick()end');self.assertEqual(self.val('D[1].launches'),1);self.assertEqual(self.val('D[2].launches'),1);self.assertEqual(self.val('D[1].arms+D[2].arms'),2)
 def test_duplicate_prepare_does_not_launch(self):
  self.runlua('both_ready();S[1].start();S[2].update();S[2].update()');self.assertEqual(self.val('D[2].launches'),0)
 def test_disconnect_invalidates_ready_and_blocks_launch(self):
  self.runlua('both_ready();DROPPED=true;tick()');self.assertEqual(self.val('S[1].phase'),'stopped');self.assertFalse(self.val('S[1].ready_local'));self.assertEqual(self.val('D[1].launches+D[2].launches'),0)
 def test_missing_verified_route_blocks_start(self):
  self.runlua('CAP=false;both_ready()');self.assertFalse(self.val('S[1].can_start()'));self.assertRaises(Exception,self.runlua,'S[1].start()')
 def test_guest_ready_revision_is_bound_to_host_choice(self):
  self.runlua('both_ready();D[1].frame.revision=2;D[1].frame.ready_revision=0;D[1].frame.flags=2;D[1].frame.sequence=100;S[2].update()');self.assertEqual(self.val('S[2].revision'),2);self.assertFalse(self.val('S[2].ready_local'))
 def test_guest_cannot_change_choice(self):self.assertRaises(Exception,self.runlua,'S[2].select(7,23)')
 def test_wrong_mission_cannot_launch(self):
  self.runlua('both_ready();D[1].frame.mission=6;S[2].update()');self.assertEqual(self.val('S[2].phase'),'stopped');self.assertEqual(self.val('D[2].launches'),0)
 def test_timeout_before_ack(self):
  self.runlua('both_ready();S[1].start();T=16;S[1].update()');self.assertEqual(self.val('S[1].phase'),'stopped')
 def test_cancel_during_prepare(self):
  self.runlua('both_ready();S[1].start();S[2].stop();S[1].update()');self.assertEqual(self.val('S[1].phase'),'stopped');self.assertEqual(self.val('D[1].launches+D[2].launches'),0)
 def test_session_change_never_reuses_old_ready(self):
  self.runlua('both_ready();local old=A[1].receive;A[1].receive=function()local p=old();p.peer_session=999;return p end;S[1].update()');self.assertEqual(self.val('S[1].phase'),'stopped')
 def test_replayed_commit_without_prepare_never_launches(self):
  self.runlua('both_ready();D[1].frame.phase=3;D[1].frame.launch=1;D[1].frame.sequence=100;S[2].update()');self.assertEqual(self.val('D[2].launches'),0)
 def test_reset_before_travel_clears_ready_and_allows_role_change(self):
  self.runlua("both_ready();S[1].reset();S[1].configure('guest','76561198000000003')")
  self.assertEqual(self.val('S[1].phase'),'room');self.assertEqual(self.val('S[1].role'),'guest');self.assertFalse(self.val('S[1].ready_local'))
 def test_reset_after_travel_cannot_reuse_allocation(self):
  self.runlua('both_ready();S[1].start();for i=1,12 do tick()end')
  self.assertRaises(Exception,self.runlua,'S[1].reset()')
if __name__=='__main__':unittest.main()
