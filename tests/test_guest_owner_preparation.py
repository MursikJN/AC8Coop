"""R31 request/initial-pose boundary with mock reflection, never game/native calls."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts'

class OwnerPreparationTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.globals().SOURCE=SOURCE.as_posix()
  self.lua.execute('''
   M=assert(loadfile(SOURCE..'/guest_owner_preparation.lua'))()
   local next=1
   function obj()next=next+1;local o={id=next};function o:IsValid()return true end;function o:GetAddress()return self.id end;return o end
   WORLD=obj();PC=obj();PAWN=obj();CAM=obj();MANAGER=obj();CDO=obj();CLASS=obj();BASE=obj()
   function PC:GetViewTarget()return CAM end
   function MANAGER:GetWorld()return WORLD end
   function CLASS:IsChildOf(b)return b==BASE end
   function CLASS:GetCDO()return CDO end
   function CLASS:ForEachProperty(fn)
    fn({GetFName=function()return{ToString=function()return 'bHidden'end}end,
     GetClass=function()return{GetFName=function()return{ToString=function()return 'BoolProperty'end}end}end,
     GetOffset_Internal=function()return 0x58 end,GetAddress=function()return 12345 end})
   end
   API={static=function(p)return p:find('PP0023',1,true)and CLASS or BASE end,load=function()error('unexpected load')end,find=function()return {MANAGER}end}
   C={snapshot={guest_weapon1='0',guest_weapon2='0'}}
   CLIENT={context={world=WORLD,pc=PC,pawn=PAWN,isolated_world_verified=true},camera={active=true,camera=CAM}}
  ''')
 def test_no_source_pawn_or_cross_process_model_in_request(self):
  self.lua.execute("ROWS={};M.request(C,CLIENT,ROWS,API);TEXT=table.concat(ROWS,'\\n');assert(TEXT:find('owner_class',1,true)and TEXT:find('hidden_property',1,true)and TEXT:find('mod_count\\t0',1,true)and not TEXT:find('host',1,true))")
 def test_missing_manager_and_wrong_camera_fail_before_native(self):
  self.lua.execute("API.find=function()return {}end;assert(not pcall(M.request,C,CLIENT,{},API));API.find=function()return {MANAGER}end;CAM=obj();assert(not pcall(M.request,C,CLIENT,{},API))")
 def test_preview_cannot_be_owner_world(self):
  self.lua.execute('CLIENT.context.preview=true;assert(not pcall(M.request,C,CLIENT,{},API))')
 def test_expected_dependency_classes_are_required_and_in_request(self):
  self.lua.execute("ROWS={};M.request(C,CLIENT,ROWS,API);local t=table.concat(ROWS,'\\n');for _,k in ipairs({'actor_manager_class','combat_zone_class','actor_mapper_class'})do assert(t:find(k..'\\t',1,true))end")
  for name in ('LiveActorManager','LiveCombatZone','LiveObjectMapper'):
   self.setUp();self.lua.globals().MISSING=name
   self.lua.execute("local old=API.static;API.static=function(p)if p=='/Script/Live.'..MISSING then return nil end;return old(p)end;local ok,why=pcall(M.request,C,CLIENT,{},API);assert(not ok and tostring(why):find('owner_world_object_class_missing',1,true))")
 def test_initial_seed_uses_only_pose_and_native_euler_conversion(self):
  self.lua.execute('''
   local q=math.sqrt(.5);F={sequence=42,generation=7,revision=2,poses={{},{role=1,aircraft=23,position={10,20,30},rotation={0,0,q,q}}}}
   V=assert(loadfile(SOURCE..'/guest_pilot_view.lua'))()
   local api={static=function()return{Quat_Rotator=function(_,q)assert(q.Z>0);return {Pitch=0,Yaw=90,Roll=0}end}end}
   local text=M.seed(F,V,api);assert(text:find('host_sequence\\t42',1,true)and text:find('angle1\\t90',1,true)and text:find('position0\\t10',1,true))
   assert(not text:find('parts',1,true)and not text:find('cache',1,true))
  ''')

if __name__=='__main__':unittest.main()
