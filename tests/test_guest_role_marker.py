import unittest
from pathlib import Path
from lupa import LuaRuntime

SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/guest_role_marker.lua'
FIXTURE=r'''
H={spawned=0,cancelled=0,destroyed=0}
local next_id=100
function obj()
 next_id=next_id+1;local o={id=next_id,valid=true}
 function o:IsValid()return self.valid end
 function o:GetAddress()return self.id end
 return o
end
local invalid={IsValid=function()return false end}
H.world=obj();H.host=obj();H.player=obj();H.pc=obj();H.class=obj()
function H.class:GetFullName()return 'BlueprintGeneratedClass /Game/UI/Material/HUD/TargetContainer3DUI/ChronicleTargetContainerActorBP.ChronicleTargetContainerActorBP_C'end
H.host.Controller=H.pc;H.pc.Pawn=H.host;H.player.Controller=invalid;H.player.bIsActivated=true
H.host.world=H.world;H.player.world=H.world;H.player.nickname='Steam Pilot'
function H.player:GetWorld()return self.world end
function H.host:GetWorld()return self.world end
function H.player:K2_GetActorLocation()return {X=100,Y=200,Z=300}end
function H.player:GetObjName()return self.nickname end
H.pc.PlayerCameraManager=obj()
function H.pc.PlayerCameraManager:GetCameraLocation()return {X=500,Y=600,Z=700}end
function H.world:SpawnActor(class,p,rot)
 assert(class==H.class);H.spawned=H.spawned+1
 local a=obj();H.last=a;a.label=obj();a.ObjectCallsignText=a.label
 function a:SetOwner(p)self.owner=p end
 function a:GetOwner()return self.owner end
 function a:GetClass()return class end
 function a:SetActorTickEnabled(v)assert(v==false)end
 function a:SetActorEnableCollision(v)assert(v==false)end
 function a:SetActorHiddenInGame(v)self.hidden=v end
 function a:K2_SetActorLocationAndRotation(p,r)self.position=p;self.rotation=r end
 function a:K2_DestroyActor()self.valid=false;H.destroyed=H.destroyed+1 end
 function a.label:SetVisibility(v)self.visible=v end
 function a.label:SetHiddenInGame(v)self.hidden=v end
 function a.label:SetTextRenderColor(v)self.color=v end
 function a.label:SetText(v)self.text=v end
 function a.label:SetWorldSize(v)assert(v>0 and v<100000);self.size=v end
 return a
end
H.api={static=function()return H.class end,ftext=function(s)return s end,
 loop=function(_,cb)H.callback=cb;return 7 end,
 cancel=function(id)assert(id==7);H.cancelled=H.cancelled+1 end}
'''

class MarkerTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute(FIXTURE)
  self.lua.globals().module=self.lua.execute(SOURCE.read_text(encoding='utf-8'))
  self.lua.execute('S=module.new(H.api);S.attach(H.player,H.pc)')

 def check(self,script):self.lua.execute(script)

 def test_owns_only_hud_actor_and_uses_steam_name(self):
  self.check("assert(H.spawned==1 and H.last.owner==H.player and H.last.label.text=='Steam Pilot');assert(H.pc.Pawn==H.host and H.host.Controller==H.pc);assert(H.last.position.Z==1500)")

 def test_updates_nickname_without_new_actor(self):
  self.check("H.player.nickname='Renamed';H.callback();assert(H.last.label.text=='Renamed' and H.spawned==1 and S.updates==2)")

 def test_map_change_removes_owned_marker(self):
  self.check("H.player.world=obj();H.callback();assert(not S.active and H.destroyed==1 and H.cancelled==1)")

 def test_host_ownership_change_stops_marker(self):
  self.check("H.pc.Pawn=obj();H.callback();assert(not S.active and H.destroyed==1)")

 def test_detached_role_is_not_displayed(self):
  self.check("H.player.bIsActivated=false;H.callback();assert(not S.active and H.destroyed==1)")

 def test_repeat_attach_retires_previous_marker(self):
  self.check("local old=H.last;S.attach(H.player,H.pc);assert(not old.valid and old.hidden and not old.label.visible and old.label.hidden and H.spawned==2 and H.destroyed==1 and H.cancelled==1)")

 def test_guard_failure_removes_marker(self):
  self.check("S.verify=function()return false end;H.callback();assert(not S.active and H.destroyed==1)")

if __name__=='__main__':unittest.main()
