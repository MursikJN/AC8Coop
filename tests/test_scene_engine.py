"""Replica renderer ownership, asset barriers and pause rollback."""
from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'probe/AC8CoopRecon/Scripts'
FIXTURE=r'''
H={spawned=0,destroyed=0,paused=true,next=100,actors={}}
function object(kind)
 H.next=H.next+1;local o={id=H.next,valid=true,kind=kind}
 function o:IsValid()return self.valid end;function o:GetAddress()return self.id end
 function o:IsA(k)return self.kind==k end;return o
end
H.world=object('World');function H.world:GetFullName()return '/Game/Maps/Mission007'end
H.pc=object('PC');function H.pc:GetWorld()return H.world end
H.gameplay=object('Library');function H.gameplay:IsGamePaused()return H.paused end
H.math=object('Library');function H.math:Quat_Rotator(q)return q end
H.assets={['/Game/Test.Mesh']=object('/Script/Engine.SkeletalMesh'),['/Game/Test.Material']=object('/Script/Engine.MaterialInterface'),
 ['/Script/Engine.SkeletalMeshActor']=object('/Script/CoreUObject.Class'),['/Script/Engine.StaticMeshActor']=object('/Script/CoreUObject.Class')}
H.api={static=function(p)if p:find('GameplayStatics',1,true)then return H.gameplay elseif p:find('KismetMathLibrary',1,true)then return H.math else return H.assets[p]end end}
H.originals={}
for i=1,2 do local o=object('Original');o.bHidden=i==2;function o:GetWorld()return H.world end;function o:SetActorHiddenInGame(v)self.bHidden=v end;H.originals[i]=o end
H.context={preview=true,world=H.world,pc=H.pc,original_for_id=function(id)return H.originals[id]end}
function H.world:SpawnActor(class,p,q)
 assert(class==H.assets['/Script/Engine.SkeletalMeshActor']or class==H.assets['/Script/Engine.StaticMeshActor'])
 H.spawned=H.spawned+1;local a=object('VisualActor');H.actors[#H.actors+1]=a;local c=object('VisualComponent');a.SkeletalMeshComponent=c;a.StaticMeshComponent=c
 function a:SetActorHiddenInGame(v)self.hidden=v end;function a:SetActorEnableCollision(v)assert(v==false)end;function a:SetActorTickEnabled(v)assert(v==false)end
 function a:SetOwner(v)assert(v==H.pc)end;function a:K2_SetActorLocationAndRotation(p,q)self.p=p;self.q=q end;function a:SetActorScale3D(v)self.scale=v end
 function a:K2_DestroyActor()self.valid=false;H.destroyed=H.destroyed+1 end
 function c:SetMobility(v)assert(v==2)end;function c:SetSimulatePhysics(v)assert(v==false)end;function c:SetCollisionEnabled(v)assert(v==0)end
 function c:SetComponentTickEnabled(v)assert(v==false)end;function c:SetSkeletalMeshAsset(v)assert(v==H.assets['/Game/Test.Mesh'])end
 function c:SetMaterial(_,v)assert(v==H.assets['/Game/Test.Material'])end;function c:SetVisibility(v)assert(v)end;function c:SetHiddenInGame(v)assert(not v)end
 return a
end
'''


class EngineTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE)
  self.codec=self.lua.execute((SOURCE/'scene_codec.lua').read_text())
  module=self.lua.execute((SOURCE/'scene_engine.lua').read_text())
  self.engine=module.new(self.lua.globals().H.context,str(SOURCE).replace('\\','/'),self.lua.globals().H.api)
 def frame(self,sequence=1,ids=(1,2),mesh='/Game/Test.Mesh'):
  return dict(sequence=sequence,generation=1,revision=1,source_ms=sequence*200,world='/Game/Maps/Mission007',complete=True,paused=True,
   session=dict(epoch=1,stage=6,mission=6,difficulty=1,ready=0,loaded=0,votes=0,scene=0,host_aircraft=7,guest_aircraft=23,observed='flight'),
   entities=[dict(id=i,kind='plane',role=i-1,alive=True,health=200,asset='/Game/Class',label=str(i),position=[100*i,0,0],rotation=[0,0,0,1])for i in ids],events=[],event_cursor=0,
   visual_complete=True,visuals=[dict(entity=i,slot=1,kind='skeletal',asset=mesh,position=[0,0,0],rotation=[0,0,0,1],scale=[1,1,1],materials=['/Game/Test.Material'])for i in ids])
 def wire(self,frame):return self.codec.encode(self.lua.table_from(frame,recursive=True))
 def value(self,expression):return self.lua.eval(expression)
 def test_assets_and_spawns_finish_before_originals_are_hidden(self):
  self.engine.accept(self.wire(self.frame()),100,True);self.engine.pump(1)
  self.assertFalse(self.engine.ready);self.assertFalse(self.value('H.originals[1].bHidden'))
  self.engine.pump(1);self.engine.render(100);self.engine.activate(100)
  self.assertTrue(self.engine.ready);self.assertTrue(self.value('H.originals[1].bHidden'))
  self.assertEqual(self.value('H.spawned'),2);self.assertFalse(self.value('H.actors[1].hidden'))
  self.engine.stop('test');self.assertEqual(self.value('H.destroyed'),2)
  self.assertFalse(self.value('H.originals[1].bHidden'));self.assertTrue(self.value('H.originals[2].bHidden'))
 def test_missing_asset_never_creates_or_hides_anything(self):
  with self.assertRaises(Exception):self.engine.accept(self.wire(self.frame(mesh='/Game/Missing')),100,True)
  self.assertEqual(self.value('H.spawned'),0);self.assertFalse(self.value('H.originals[1].bHidden'))
 def test_authoritative_despawn_removes_only_owned_mesh(self):
  self.engine.accept(self.wire(self.frame()),100,True);self.engine.pump(10);self.engine.activate(100)
  self.engine.accept(self.wire(self.frame(2,ids=(2,))),300,False)
  self.assertEqual(self.value('H.destroyed'),1);self.assertFalse(self.value('H.originals[1].bHidden'))
  self.assertTrue(self.value('H.originals[1].valid'))
 def test_unpause_refuses_further_render_and_cleanup_restores_originals(self):
  self.engine.accept(self.wire(self.frame()),100,True);self.engine.pump(10);self.engine.activate(100)
  self.lua.execute('H.paused=false')
  with self.assertRaises(Exception):self.engine.render(200)
  self.engine.stop('unpaused');self.assertFalse(self.value('H.originals[1].bHidden'))
 def test_independent_guest_requires_verified_world_isolation(self):
  self.lua.execute('H.context.preview=false')
  with self.assertRaises(Exception):self.engine.accept(self.wire(self.frame()),100,True)
  self.assertEqual(self.value('H.spawned'),0)
 def test_incomplete_visual_baseline_never_hides_host(self):
  f=self.frame();f['visual_complete']=False
  with self.assertRaises(Exception):self.engine.accept(self.wire(f),100,True)
  self.assertFalse(self.value('H.originals[1].bHidden'));self.assertEqual(self.value('H.spawned'),0)
 def test_loading_needs_a_fresh_baseline_before_switching_views(self):
  self.engine.accept(self.wire(self.frame()),100,True);self.engine.pump(10)
  with self.assertRaises(Exception):self.engine.activate(1000)
  self.assertFalse(self.value('H.originals[1].bHidden'));self.assertFalse(self.engine.ready)
  self.engine.accept(self.wire(self.frame(2)),1000,False);self.engine.pump(10);self.engine.activate(1000)
  self.assertTrue(self.engine.ready)
 def test_network_silence_freezes_visuals_without_reviving_originals(self):
  self.engine.accept(self.wire(self.frame()),100,True);self.engine.pump(10);self.engine.activate(100)
  result=self.engine.render(1000);self.assertEqual(result,(False,'stale_host'))
  self.assertEqual(self.value('H.destroyed'),0);self.assertTrue(self.value('H.originals[1].bHidden'))
  self.engine.accept(self.wire(self.frame(2)),1100,False);self.assertTrue(self.engine.render(1100))
  self.assertEqual(self.value('H.spawned'),2)
 def test_nested_visibility_overrides_restore_in_reverse_order(self):
  self.lua.globals().engine=self.engine
  self.lua.execute("widget=object('Widget');widget.Visibility=1;function widget:SetVisibility(v)self.Visibility=v end;engine.panels={{object=widget,visibility=3},{object=widget,visibility=1}}")
  self.engine.stop('test');self.assertEqual(self.value('widget.Visibility'),3)
  self.assertIsNone(self.engine.core.current)
 def test_live_preview_uses_per_view_scope_without_hiding_game_actors(self):
  self.lua.execute("H.paused=false;H.context.preview=false;H.context.live_preview=true;H.context.visibility={verify=function(pc,world)assert(pc==H.pc and world==H.world)end,set=function(objects)H.hidden_views=objects end,stop=function()H.hidden_views={}end}")
  self.engine.accept(self.wire(self.frame()),100,True);self.engine.pump(10);self.engine.render(100);self.engine.activate(100)
  self.assertFalse(self.value('H.originals[1].bHidden'));self.assertTrue(self.value('H.hidden_views[1]==H.originals[1]'))
  self.engine.stop('test');self.assertTrue(self.value('next(H.hidden_views)==nil'));self.assertEqual(self.value('H.destroyed'),2)
 def test_live_preview_refuses_missing_per_view_scope(self):
  self.lua.execute('H.paused=false;H.context.preview=false;H.context.live_preview=true')
  with self.assertRaises(Exception):self.engine.accept(self.wire(self.frame()),100,True)
  self.assertEqual(self.value('H.spawned'),0)

if __name__=='__main__':unittest.main()
