-- Mesh-only client renderer. No LivePlayerPlane/AI/Unit is spawned here.
-- One-PC preview borrows the loaded terrain while its authoritative world is
-- paused. A separate client must supply a verified isolated replica world.
local M={}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
local function vector(p)return{X=p[1],Y=p[2],Z=p[3]}end
local function quat(q)return{X=q[1],Y=q[2],Z=q[3],W=q[4]}end
local function signature(v)return v.kind..'|'..v.asset..'|'..table.concat(v.materials,'\n')end
function M.new(context,source,api)
 local codec=assert(loadfile(source..'/scene_codec.lua'))()
 local transform=assert(loadfile(source..'/scene_transform.lua'))()
 local client=assert(loadfile(source..'/scene_client.lua'))()
 local pilot_view=assert(loadfile(source..'/guest_pilot_view.lua'))()
 api=api or{static=StaticFindObject}
 local gameplay=api.static('/Script/Engine.Default__GameplayStatics');local mathlib=api.static('/Script/Engine.Default__KismetMathLibrary')
 local s={nodes={},pending={},originals={},entities={},resources={},created=0,destroy_requested=0,ready=false,assets_ready=false,active=true,panels={}}
 local function guard()
  assert(s.active and valid(context.world)and valid(context.pc)and same(context.pc:GetWorld(),context.world),'Replica world expired')
  if context.live_preview then
   assert(not context.preview and context.visibility,'Live preview requires per-view visibility')
   context.visibility.verify(context.pc,context.world)
   assert(not gameplay:IsGamePaused(context.world),'Live replica preview was paused')
  elseif context.preview then assert(gameplay:IsGamePaused(context.world),'Replica preview requires paused host')
  else assert(context.isolated_world_verified==true,'Guest simulation isolation not verified')end
 end
 local function resolve(path,kind)
  local key=kind..'|'..path;local o=s.resources[key];if valid(o)then return o end
  o=api.static(path)
  if not valid(o)and context.load_assets and type(LoadAsset)=='function'then LoadAsset(path);o=api.static(path)end
  assert(valid(o)and o:IsA(kind),'Missing or wrong replica asset: '..path);s.resources[key]=o;return o
 end
 local function destroy(key)
  local n=s.nodes[key];s.pending[key]=nil;if not n then return end
  if valid(n.actor)then n.actor:SetActorHiddenInGame(true);n.actor:K2_DestroyActor();s.destroy_requested=s.destroy_requested+1 end;s.nodes[key]=nil
 end
 local function restore_original(id)
  local original=s.originals[id];if context.preview and original and valid(original.object)and same(original.object:GetWorld(),context.world)then original.object:SetActorHiddenInGame(original.hidden)end;s.originals[id]=nil
 end
 local adapter={}
 function adapter.prepare(frame)
  guard();assert(frame.world==context.world:GetFullName(),'Replica map mismatch')
  assert(frame.visuals and frame.visual_complete,'Complete visual baseline required')
  assert(#frame.visuals<=1024,'Local renderer mesh budget exceeded')
  local plan={};local prepared_originals={}
  for _,v in ipairs(frame.visuals)do
   local materials={};for i,path in ipairs(v.materials)do if path~=''then materials[i]=resolve(path,'/Script/Engine.MaterialInterface')end end
   local class=resolve(v.kind=='skeletal'and'/Script/Engine.SkeletalMeshActor'or'/Script/Engine.StaticMeshActor','/Script/CoreUObject.Class')
   plan[v.entity..':'..v.slot]={descriptor=v,mesh=resolve(v.asset,v.kind=='skeletal'and'/Script/Engine.SkeletalMesh'or'/Script/Engine.StaticMesh'),class=class,materials=materials,signature=signature(v)}
  end
  if context.preview or context.live_preview then
   assert(type(context.original_for_id)=='function','Preview identity mapping unavailable')
   for _,e in ipairs(frame.entities)do
    local old=s.originals[e.id];local o=context.original_for_id(e.id)
    assert(valid(o)and same(o:GetWorld(),context.world)and type(o.bHidden)=='boolean','Stale preview actor identity')
    assert(not old or same(old.object,o),'Preview entity identity changed')
    prepared_originals[e.id]=old or{object=o,hidden=o.bHidden}
   end
  end
  s.plan=plan;s.prepared_originals=prepared_originals
 end
 function adapter.create(e)s.entities[e.id]=e end
 function adapter.remove(id)
  if s.entities[id]and s.entities[id].role==1 then s.owner_pose=nil;s.guest_pose=nil end
  local keys={};for k,n in pairs(s.nodes)do if n.descriptor.entity==id then keys[#keys+1]=k end end;for _,k in ipairs(keys)do destroy(k)end
  for k,n in pairs(s.pending)do if n.descriptor.entity==id then s.pending[k]=nil end end
  restore_original(id);s.entities[id]=nil
 end
 function adapter.event(e)s.last_event=e end
 function adapter.menu(menu)s.menu=menu end
 function adapter.commit()
  local keys={};for key in pairs(s.nodes)do local next=s.plan[key];if not next or next.signature~=s.nodes[key].signature then keys[#keys+1]=key end end
  for _,key in ipairs(keys)do destroy(key)end
  s.pending={};for key,n in pairs(s.plan)do
   local old=s.nodes[key];if old then
    for _,field in ipairs({'position','rotation','scale'})do for i,v in ipairs(n.descriptor[field])do if old.descriptor[field][i]~=v then old.dirty=true end end end
    old.descriptor=n.descriptor
   else s.pending[key]=n;s.ready=false;s.assets_ready=false end
  end
  for id,entry in pairs(s.prepared_originals)do s.originals[id]=entry end
  if context.live_preview and s.ready then local objects={};for id,entry in pairs(s.originals)do objects[id]=entry.object end;context.visibility.set(objects)end
 end
 function adapter.update(e)
  if e.role==1 and not e.alive then s.owner_pose=nil end
  -- Only the verified local owner can override its own movement. Mission
  -- state/health/alive and every other entity still come from the host.
  if e.role==1 and e.alive and s.owner_pose then
   local local_entity={};for k,v in pairs(e)do local_entity[k]=v end
   local_entity.position=s.owner_pose.position;local_entity.rotation=s.owner_pose.rotation;local_entity.speed=s.owner_pose.speed;e=local_entity
  end
  s.entities[e.id]=e;if e.role==1 and e.alive then s.guest_pose=e end
  for _,n in pairs(s.nodes)do if n.descriptor.entity==e.id then
   local p,q=transform.world(e,n.descriptor);local key=table.concat(p,':')..':'..table.concat(q,':')..':'..table.concat(n.descriptor.scale,':')
   if n.dirty or n.pose_key~=key then
    n.actor:K2_SetActorLocationAndRotation(vector(p),mathlib:Quat_Rotator(quat(q)),false,{},true)
    n.actor:SetActorScale3D(vector(n.descriptor.scale));n.pose_key=key;n.dirty=false
   end
  end end
 end
 s.core=client.new(codec,adapter)
 function s.set_owner_pose(frame)
  guard()
  if context.local_owner_verified~=true or context.preview or context.live_preview or not context.isolated_world_verified or not s.ready or frame.generation~=context.generation or frame.revision~=context.revision or frame.sequence<=(s.owner_sequence or 0)then return false end
  local p=frame.pose;if not pilot_view.pose(p)or p.role~=1 or p.aircraft~=23 then return false end
  local own;for _,e in pairs(s.entities)do if e.role==1 and e.alive then assert(not own,'Duplicate guest role');own=e end end
  if not own then return false end
  local copied={role=1,aircraft=23,position={table.unpack(p.position)},rotation={table.unpack(p.rotation)},speed=p.speed}
  s.owner_pose=copied;s.owner_sequence=frame.sequence;adapter.update(own);return true
 end
 function s.accept(data,now,baseline)return s.core.accept(data,now,baseline)end
 function s.pump(budget)
  guard();local count=0
  for key,n in pairs(s.pending)do
   if count>=(budget or 12)then break end
   local e=assert(s.entities[n.descriptor.entity]);local p,q=transform.world(e,n.descriptor)
   n.actor=context.world:SpawnActor(n.class,vector(p),mathlib:Quat_Rotator(quat(q)));assert(valid(n.actor),'Replica mesh spawn failed')
   s.nodes[key]=n;s.created=s.created+1;s.pending[key]=nil
   n.actor:SetActorHiddenInGame(true);n.actor:SetActorEnableCollision(false);n.actor:SetActorTickEnabled(false);n.actor:SetOwner(context.pc)
   n.component=n.descriptor.kind=='skeletal'and n.actor.SkeletalMeshComponent or n.actor.StaticMeshComponent;assert(valid(n.component),'Replica mesh component missing')
   n.component:SetMobility(2);n.component:SetSimulatePhysics(false);n.component:SetCollisionEnabled(0);n.component:SetComponentTickEnabled(false)
   assert(valid(n.mesh),'Replica mesh asset expired before registration')
   if n.descriptor.kind=='skeletal'then n.component:SetSkeletalMeshAsset(n.mesh)else assert(n.component:SetStaticMesh(n.mesh),'Static replica mesh refused')end
   for i,material in pairs(n.materials)do n.component:SetMaterial(i-1,material)end
   n.component:SetVisibility(true,false);n.component:SetHiddenInGame(false,false);n.dirty=true;count=count+1
  end
  s.assets_ready=next(s.pending)==nil
 end
 function s.activate(now)
  guard();assert(s.assets_ready and next(s.nodes),'No complete visual baseline')
  assert(s.core.active and now>=s.core.received and now-s.core.received<=500,'Fresh post-load baseline required')
  if context.preview then for _,entry in pairs(s.originals)do assert(valid(entry.object),'Original retired during preview');entry.object:SetActorHiddenInGame(true)end end
  if context.live_preview then local objects={};for id,entry in pairs(s.originals)do objects[id]=entry.object end;context.visibility.set(objects)end
  for _,n in pairs(s.nodes)do n.actor:SetActorHiddenInGame(false)end;s.ready=true
 end
 function s.render(now)guard();return s.core.render(now)end
 function s.stop(reason)
  s.active=false;s.ready=false;s.reason=reason
  if context.visibility then context.visibility.stop()end
  local keys={};for key in pairs(s.nodes)do keys[#keys+1]=key end;for _,key in ipairs(keys)do destroy(key)end
  local ids={};for id in pairs(s.originals)do ids[#ids+1]=id end;for _,id in ipairs(ids)do restore_original(id)end
  for i=#s.panels,1,-1 do local entry=s.panels[i];if valid(entry.object)then
   if entry.attribute then entry.object[entry.attribute]=entry.value else entry.object:SetVisibility(entry.visibility)end
  end end;s.panels={};s.pending={};s.plan={};s.resources={};s.prepared_originals={};s.entities={};s.guest_pose=nil;s.owner_pose=nil;s.owner_sequence=nil;s.core.reset(reason)
 end
 return s
end
return M
