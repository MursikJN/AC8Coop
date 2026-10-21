import math,struct,unittest
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts'
def snapshot(seq=1,generation=1,x=0,q=(0,0,0,1)):
 b=bytearray(368)
 struct.pack_into('<4sHHII6Q6I',b,0,b'AC8P',1,368,25201480,1,1,10,20,seq,generation,seq*1000,1,7,1,23,4,4)
 for i in range(4):struct.pack_into('<II3d4f3fI',b,104+64*i,i,23 if i==1 else 7,x,0,0,*q,200,200,200,0)
 return bytes(b)
class ViewTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True,encoding=None)
  self.v=self.lua.execute((ROOT/'guest_pilot_view.lua').read_bytes())
 def test_parse_native_wire_layout(self):
  f=self.v[b'parse'](snapshot(x=123));self.assertEqual(f[b'poses'][2][b'position'][1],123);self.assertEqual(f[b'poses'][2][b'aircraft'],23)
 def test_nonfinite_rotation_rejected(self):
  with self.assertRaises(Exception):self.v[b'parse'](snapshot(q=(math.nan,0,0,1)))
 def test_replay_and_old_generation_rejected(self):
  s=self.v[b'stream']();f=self.v[b'parse'](snapshot(generation=2))
  self.assertTrue(s[b'accept'](f,100));self.assertFalse(s[b'accept'](f,101));self.assertFalse(s[b'accept'](self.v[b'parse'](snapshot(2,1)),102))
 def test_interpolation_and_stale_state(self):
  s=self.v[b'stream']();s[b'accept'](self.v[b'parse'](snapshot(1,x=0)),100);s[b'accept'](self.v[b'parse'](snapshot(2,x=100)),200)
  self.assertAlmostEqual(s[b'sample'](225)[b'poses'][2][b'position'][1],50)
  self.assertIsNone(s[b'sample'](501)[0])
 def test_quaternion_hemisphere_does_not_spin(self):
  s=self.v[b'stream']();s[b'accept'](self.v[b'parse'](snapshot(1)),100);s[b'accept'](self.v[b'parse'](snapshot(2,q=(0,0,0,-1))),200)
  self.assertAlmostEqual(abs(s[b'sample'](225)[b'poses'][2][b'rotation'][4]),1)
 def test_camera_follows_yaw_and_pitch(self):
  p=self.v[b'parse'](snapshot(q=(0,0,math.sqrt(.5),math.sqrt(.5))))[b'poses'][2];at,_,fwd=self.v[b'follow'](p)
  self.assertAlmostEqual(fwd[2],1,places=6);self.assertAlmostEqual(at[b'Y'],-4200,places=3)

FIXTURE=r'''
H={cancelled=0,destroyed=0,paused=true}
local n=100
function obj()n=n+1;local o={id=n,valid=true};function o:IsValid()return self.valid end;function o:GetAddress()return self.id end;return o end
H.world=obj();function H.world:GetFullName()return 'World /Game/Maps/Ingame/Mission007/PL_Mission007'end
H.pawn=obj();function H.pawn:GetWorld()return H.world end
H.pc=obj();H.pc.Pawn=H.pawn;H.pc.target=H.pawn;H.pc.bAutoManageActiveCameraTarget=true;H.pc.bShouldPerformFullTickWhenPaused=false
function H.pc:GetWorld()return H.world end
function H.pc:GetViewTarget()return self.target end
function H.pc:SetViewTargetWithBlend(o)self.target=o end
H.class=obj();H.math=obj();function H.math:FindLookAtRotation()return {Pitch=0,Yaw=0,Roll=0}end
H.gameplay=obj();function H.gameplay:IsGamePaused()return H.paused end
H.now=0;function H.gameplay:GetRealTimeSeconds()return H.now end
H.pose={position={0,0,0},rotation={0,0,0,1}}
function H.world:SpawnActor()
 local c=obj();c.CameraComponent=obj();H.last=c
 function c:SetOwner()end;function c:SetActorEnableCollision()end;function c:SetActorHiddenInGame()end
 function c:K2_SetActorLocationAndRotation(p)self.position=p end
 function c:K2_DestroyActor()self.valid=false;H.destroyed=H.destroyed+1 end
 return c
end
H.api={static=function(path)if path:find('KismetMathLibrary',1,true)then return H.math elseif path:find('GameplayStatics',1,true)then return H.gameplay else return H.class end end,
loop=function(_,fn)H.callback=fn;return 10 end,cancel=function(id)assert(id==10);H.cancelled=H.cancelled+1 end}
'''
class CameraTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE)
  self.lua.globals().view=self.lua.execute((ROOT/'guest_pilot_view.lua').read_text())
  self.lua.globals().module=self.lua.execute((ROOT/'guest_pilot_camera.lua').read_text())
 def run_lua(self,s):self.lua.execute(s)
 def test_preview_preserves_pawn_and_restores_camera_flags(self):
  self.run_lua("S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{preview=true});assert(H.pc.Pawn==H.pawn and H.pc.target==H.last);S.stop('test');assert(H.pc.target==H.pawn and H.pc.bAutoManageActiveCameraTarget and not H.pc.bShouldPerformFullTickWhenPaused and H.destroyed==1)")
 def test_preview_rolls_back_if_host_unpauses(self):
  self.run_lua("S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{preview=true});H.paused=false;H.callback();assert(not S.active and H.pc.target==H.pawn and H.cancelled==1)")
 def test_missing_source_rolls_back(self):
  self.run_lua("S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{preview=true});H.pose=nil;H.callback();assert(not S.active and H.pc.target==H.pawn and H.destroyed==1)")
 def test_replaced_pawn_stops_preview(self):
  self.run_lua("S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{preview=true});H.pc.Pawn=obj();H.callback();assert(not S.active and H.destroyed==1)")
 def test_camera_cleanup_preserves_a_new_external_view_target(self):
  self.run_lua("S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{preview=true});local external=obj();H.pc.target=external;S.stop('changed');assert(H.pc.target==external and H.pc.bAutoManageActiveCameraTarget and not H.pc.bShouldPerformFullTickWhenPaused)")
 def test_camera_cleanup_restores_flags_after_world_travel(self):
  self.run_lua("S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{preview=true});H.world=obj();S.stop('travel');assert(H.pc.bAutoManageActiveCameraTarget and not H.pc.bShouldPerformFullTickWhenPaused and H.destroyed==1)")
 def test_live_observer_tracks_received_pose_and_returns_without_pausing(self):
  self.run_lua("H.paused=false;S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{observer=true,duration=5});H.pose.position[1]=1000;H.now=4;H.callback();assert(S.active and H.last.position.X==-3200 and H.pc.Pawn==H.pawn);H.now=5;H.callback();assert(not S.active and S.reason=='observer_complete'and H.pc.target==H.pawn and not H.paused and H.destroyed==1)")
 def test_live_observer_requires_a_bounded_explicit_duration(self):
  self.run_lua("for _,duration in ipairs({0,16,math.huge})do S=module.new(view,H.api);assert(not pcall(S.attach,H.pc,function()return H.pose end,{observer=true,duration=duration}))end;assert(H.destroyed==0 and H.pc.target==H.pawn)")
 def test_live_observer_missing_transport_restores_host(self):
  self.run_lua("H.paused=false;S=module.new(view,H.api);S.attach(H.pc,function()return H.pose end,{observer=true,duration=5});H.pose=nil;H.callback();assert(not S.active and H.pc.target==H.pawn and not H.paused)")
if __name__=='__main__':unittest.main()
