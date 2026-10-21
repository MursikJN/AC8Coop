-- Guest camera, paused mesh preview, or a bounded live observer on one PC.
-- The observer only changes ViewTarget: it never possesses or moves a plane.
local M={}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
function M.new(view,api)
 api=api or{static=StaticFindObject,loop=LoopInGameThreadAfterFrames,cancel=CancelDelayedAction}
 local s={active=false,updates=0}
 function s.stop(reason)
  s.active=false;s.reason=reason
  if s.loop then api.cancel(s.loop);s.loop=nil end
  if valid(s.pc)then
   if same(s.pc:GetViewTarget(),s.camera)and valid(s.world)and same(s.pc:GetWorld(),s.world)then
    local target=same(s.pc.Pawn,s.pawn)and s.original_target or s.pc.Pawn
    if valid(target)then s.pc:SetViewTargetWithBlend(target,0,0,0,false)end
   end
   -- Controller flags also need restoration if the controller survives travel.
   if s.original_auto~=nil and s.pc.bAutoManageActiveCameraTarget==false then s.pc.bAutoManageActiveCameraTarget=s.original_auto end
   if s.original_full_tick~=nil and s.pc.bShouldPerformFullTickWhenPaused==true then s.pc.bShouldPerformFullTickWhenPaused=s.original_full_tick end
  end
  if valid(s.camera)then s.camera:SetActorHiddenInGame(true);s.camera:K2_DestroyActor()end
  s.camera=nil
 end
 function s.update()
  assert(s.active and valid(s.pc)and valid(s.pawn)and same(s.pc.Pawn,s.pawn)and same(s.pawn:GetWorld(),s.world),'Guest camera world changed')
  assert(valid(s.camera),'Guest camera retired')
  if s.replica_context then assert(s.verify_replica()and same(s.replica_context.world,s.world),'Client world isolation expired')end
  if s.preview then assert(s.gameplay:IsGamePaused(s.pawn),'Preview requires paused host world')end
  if s.observer and s.gameplay:GetRealTimeSeconds(s.world)-s.started>=s.duration then s.stop('observer_complete');return end
  local p=assert(s.source(),'Authoritative guest pose unavailable');local at,target=view.follow(p)
  local rotation=s.math:FindLookAtRotation(at,target)
  s.camera:K2_SetActorLocationAndRotation(at,rotation,false,{},true)
  assert(same(s.pc:GetViewTarget(),s.camera),'Guest camera target changed')
  s.updates=s.updates+1
 end
 function s.attach(controller,source,options)
  if s.active then s.stop('replace_guest_camera')end
  options=options or{};assert(valid(controller)and valid(controller.Pawn),'Guest controller unavailable')
  s.replica_context=options.replica_context;s.verify_replica=options.verify_replica
  if s.replica_context then assert(s.replica_context.isolated_world_verified==true and type(s.verify_replica)=='function'and s.verify_replica(),'Verified isolated scene required')end
  s.pc=controller;s.pawn=controller.Pawn;s.world=s.pawn:GetWorld();s.source=source;s.preview=options.preview==true;s.observer=options.observer==true
  assert(not(s.preview and s.observer),'Choose one camera preview mode')
  if s.observer then assert(type(options.duration)=='number'and options.duration>=1 and options.duration<=15,'Live observer duration must be 1..15 seconds');s.duration=options.duration end
  assert(valid(s.world)and s.world:GetFullName():find('Mission007',1,true),'Guest mission 6 required')
  if not s.preview and not s.observer and not s.replica_context then assert(s.pawn:GetClass():GetFullName():find('/PP0023_f14d/',1,true),'Guest F-14D required')end
  s.math=api.static('/Script/Engine.Default__KismetMathLibrary');s.gameplay=api.static('/Script/Engine.Default__GameplayStatics')
  assert(valid(s.math)and valid(s.gameplay),'Camera engine libraries unavailable')
  if s.observer then s.started=s.gameplay:GetRealTimeSeconds(s.world)end
  s.original_target=s.pc:GetViewTarget();assert(valid(s.original_target),'Original camera target unavailable')
  s.original_auto=s.pc.bAutoManageActiveCameraTarget;s.original_full_tick=s.pc.bShouldPerformFullTickWhenPaused
  assert(type(s.original_auto)=='boolean'and type(s.original_full_tick)=='boolean','Camera flag schema mismatch')
  local class=api.static('/Script/Engine.CameraActor');assert(valid(class))
  local ok,err=xpcall(function()
   local at=view.follow(assert(source()))
   s.camera=s.world:SpawnActor(class,at,{});assert(valid(s.camera),'Guest camera spawn failed')
   s.camera:SetOwner(s.pc);s.camera:SetActorEnableCollision(false)
   assert(valid(s.camera.CameraComponent),'Guest CameraComponent unavailable');s.camera.CameraComponent.FieldOfView=80
   s.pc.bAutoManageActiveCameraTarget=false;s.pc.bShouldPerformFullTickWhenPaused=true
   s.pc:SetViewTargetWithBlend(s.camera,0,0,0,false);s.active=true;s.reason=nil;s.update()
   s.loop=api.loop(1,function()
    if not s.active then return end
    local updated,message=xpcall(s.update,debug.traceback);if not updated then s.stop(message)end
   end)
  end,debug.traceback)
  if not ok then s.stop(err);error(err)end;return s
 end
 return s
end
return M
