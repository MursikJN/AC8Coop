from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
class GuestSlotResolverTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute('''
   function obj(id,label)
    return {id=id,label=label,live=true,IsValid=function(s)return s.live end,GetAddress=function(s)return s.id end,GetFullName=function(s)return s.label end,
     GetWorld=function(s)return s.world end,GetClass=function(s)return s.class end,IsA=function(s,p)return s.kind==p end}
   end
   function weak_array(o,n)return setmetatable({GetArrayNum=function()return n or 1 end}, {__index=function(t,k)if type(k)=='number'then return {Get=function()return o end}end end})end
   W=obj(1,'World /Game/Maps/Ingame/Mission007/PL_Mission007.PL_Mission007')
   P=obj(2,'host');P.world=W;P.kind='/Script/Live.LivePlayerPlane';P.bIsIGCActor=false
   PC=obj(3,'pc');PC.world=W;PC.Pawn=P
   C=obj(4,'BlueprintGeneratedClass /Game/Blueprints/Vehicle/AI/Wingman/BP_WOP1023_f14d.BP_WOP1023_f14d_C')
   B=obj(5,'baxter_current');B.world=W;B.class=C;B.ObjNameID='ContainerAllyCallsign_Name_Joker2';B.CallsignId='ContainerAllyCallsign_Name_Professor';B.bIsActivated=true;B.bIsIGCActor=false;B.bIsAnimationPlane=false
   S=obj(6,'state');S.world=W;S.Owner=B;B.AIStateComponent=S;B.AIWingmanStateComponent=S
   function wing(id,role)local o=obj(id,role);o.world=W;o.ObjNameID='ContainerAllyCallsign_Name_'..role;o.bIsActivated=true;return o end
   T=wing(7,'Joker3');K=wing(8,'Joker4')
   U=obj(9,'unit_current');U.world=W
   for _,k in ipairs({'RootAIGameObjects','ChildAIGameObjects','GroupLeadPlanes','AliveChildAIGameObjects'})do U[k]=weak_array(B)end
   ALL={LivePlayerController={PC},LiveAIWingmanPlane={B,T,K},LiveWingmanUnit={U}}
   CLASS=nil;API={find=function(q)return ALL[q]end,static=function()return CLASS end}
  ''')
  self.lua.globals().M=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/guest_slot_resolver.lua').read_text(encoding='utf-8-sig'))
 def runlua(self,s):return self.lua.execute(s)
 def test_resolves_current_baxter_without_requiring_loaded_player_asset(self):
  self.runlua('R=M.resolve(API);assert(R.slot==1 and R.aircraft==23 and R.target==B and R.host_player==P and not R.player_class_loaded)')
 def test_loaded_class_is_reported(self):self.runlua("CLASS=obj(20,'player_class');assert(M.resolve(API).player_class_loaded)")
 def test_refuses_pre_spawn_snapshot(self):
  self.runlua('ALL.LiveAIWingmanPlane={}')
  self.assertRaises(Exception,self.runlua,'M.resolve(API)')
 def test_refuses_duplicate_role(self):
  self.runlua("ALL.LiveAIWingmanPlane[4]=wing(12,'Joker2')")
  self.assertRaises(Exception,self.runlua,'M.resolve(API)')
 def test_refuses_wrong_model(self):
  self.runlua("C.label='some_other_aircraft'")
  self.assertRaises(Exception,self.runlua,'M.resolve(API)')
 def test_refuses_incomplete_unit(self):
  self.runlua('U.GroupLeadPlanes=weak_array(T)')
  self.assertRaises(Exception,self.runlua,'M.resolve(API)')
 def test_refuses_duplicate_unit(self):
  self.runlua('ALL.LiveWingmanUnit[2]=U')
  self.assertRaises(Exception,self.runlua,'M.resolve(API)')
 def test_refuses_component_owner_mismatch(self):
  self.runlua('S.Owner=T')
  self.assertRaises(Exception,self.runlua,'M.resolve(API)')
 def test_rechecks_host_pawn(self):
  self.runlua("R=M.resolve(API);P2=obj(21,'new_host');P2.world=W;P2.kind=P.kind;PC.Pawn=P2")
  self.assertRaises(Exception,self.runlua,'M.verify(R,API)')
 def test_rechecks_actor_name_even_if_address_reused(self):
  self.runlua("R=M.resolve(API);B.label='recycled_actor'")
  self.assertRaises(Exception,self.runlua,'M.verify(R,API)')
 def test_rechecks_weak_references(self):
  self.runlua('R=M.resolve(API);B.live=false')
  self.assertRaises(Exception,self.runlua,'M.verify(R,API)')
if __name__=='__main__':unittest.main()
