"""Per-view visibility ownership; no mutation of actor gameplay state."""
import unittest
from pathlib import Path
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts'
FIXTURE=r'''
function obj(id)local o={id=id};function o:IsValid()return true end;function o:GetAddress()return self.id end;function o:GetWorld()return world end;return o end
world=obj(1);pc=obj(2);a=obj(3);b=obj(4);external=obj(5)
array={items={}}
function array:type()return 'TArray'end
function array:GetArrayNum()return #self.items end
function array:ForEach(fn)for i,o in ipairs(self.items)do fn(i,{get=function()return o end})end end
function array:Empty()self.items={}end
setmetatable(array,{__newindex=function(t,k,v)if type(k)=='number'then if fail and v==b then fail=false;error('write failure')end;t.items[k]=v else rawset(t,k,v)end end})
pc.HiddenActors=array
'''
class VisibilityTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE)
  self.lua.globals().module=self.lua.execute((SOURCE/'scene_visibility.lua').read_text())
 def run_lua(self,s):self.lua.execute(s)
 def test_add_and_remove_own_entries_only(self):
  self.run_lua("array.items={external};s=module.new(pc,world);s.set({a,b});assert(#array.items==3 and not a.bHidden);s.stop();assert(#array.items==1 and array.items[1]==external)")
 def test_external_addition_survives_cleanup(self):
  self.run_lua("s=module.new(pc,world);s.set({a});array.items[2]=external;s.stop();assert(#array.items==1 and array.items[1]==external)")
 def test_preexisting_desired_entry_is_not_owned(self):
  self.run_lua("array.items={a};s=module.new(pc,world);s.set({a,b});s.stop();assert(#array.items==1 and array.items[1]==a)")
 def test_despawn_updates_without_leaking_old_entry(self):
  self.run_lua("s=module.new(pc,world);s.set({a,b});s.set({b});assert(#array.items==1 and array.items[1]==b);s.stop();assert(#array.items==0)")
 def test_failed_write_restores_previous_array(self):
  self.run_lua("array.items={external};s=module.new(pc,world);fail=true;assert(not pcall(s.set,{a,b}));assert(#array.items==1 and array.items[1]==external);s.stop();assert(#array.items==1)")
 def test_world_travel_does_not_touch_new_world_array(self):
  self.run_lua("s=module.new(pc,world);s.set({a});world=obj(10);array.items={external};s.stop();assert(#array.items==1 and array.items[1]==external)")
 def test_foreign_world_refused_before_mutation(self):
  self.run_lua("s=module.new(pc,world);function b:GetWorld()return obj(20)end;assert(not pcall(s.set,{b}));assert(#array.items==0)")
if __name__=='__main__':unittest.main()
