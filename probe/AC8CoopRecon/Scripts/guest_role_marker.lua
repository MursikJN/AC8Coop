-- World-space nickname using the game's TargetContainer blueprint and font.
-- This owns one HUD actor, never an aircraft, controller, viewport or AI slot.
local M={}
local path='/Game/UI/Material/HUD/TargetContainer3DUI/ChronicleTargetContainerActorBP.ChronicleTargetContainerActorBP_C'
local parts={'ContainerBox','EscortBillboardImage','EmblemBillboardImage','AntiClockTargetPinBillboardImage','ClockTargetPinBillboardImage','StarStatusBillboardImage','SuppliesBillboardImage','SimpleRadioAttackBillboardImage','SimpleRadioReliefBillboardImage','ClientNameBillboardImage','HPGaugeBillboardImage','HPGaugeSliderBillboardImage','AllianceText','DistanceText','ObjectTypeText','ObjectCallsignText','GamerTagText','NextTargetText'}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
local function text(s)return type(s)=='string'and s or s:ToString()end
local function finite(x)return type(x)=='number'and x==x and math.abs(x)<1e10 end
function M.new(api)
 api=api or{static=StaticFindObject,loop=LoopInGameThreadAfterFrames,cancel=CancelDelayedAction,ftext=FText}
 local s={active=false,updates=0}
 function s.stop(reason)
  s.active=false;s.reason=reason or'stopped'
  if s.loop then api.cancel(s.loop);s.loop=nil end
  if valid(s.marker)then
   -- Paused worlds can defer actor retirement. Hide synchronously so a
   -- replacement attachment cannot leave two rendered nickname labels.
   s.marker:SetActorHiddenInGame(true)
   if valid(s.label)then s.label:SetVisibility(false,false);s.label:SetHiddenInGame(true,false)end
   s.marker:K2_DestroyActor()
  end
  s.marker=nil;s.label=nil
 end
 function s.update()
  assert(s.active and valid(s.player)and valid(s.controller)and same(s.player:GetWorld(),s.world),'Marker world expired')
  assert(same(s.controller.Pawn,s.host)and same(s.host.Controller,s.controller),'Host ownership changed')
  assert(not valid(s.player.Controller)and s.player.bIsActivated,'Guest role inactive')
  assert(valid(s.marker)and same(s.marker:GetOwner(),s.player),'Marker owner changed')
  if s.verify then assert(s.verify(),'Role binding expired')end
  local p=s.player:K2_GetActorLocation();local c=s.controller.PlayerCameraManager:GetCameraLocation()
  for _,v in ipairs({p.X,p.Y,p.Z,c.X,c.Y,c.Z})do assert(finite(v),'Nonfinite marker pose')end
  p={X=p.X,Y=p.Y,Z=p.Z+1200}
  local dx,dy,dz=c.X-p.X,c.Y-p.Y,c.Z-p.Z
  local horizontal=math.sqrt(dx*dx+dy*dy);local distance=math.sqrt(horizontal*horizontal+dz*dz)
  assert(distance<1e8,'Marker distance out of bounds')
  local rotation={Pitch=math.deg(math.atan(dz,horizontal)),Yaw=math.deg(math.atan(dy,dx)),Roll=0}
  s.marker:K2_SetActorLocationAndRotation(p,rotation,false,{},true)
  s.label:SetWorldSize(math.max(400,math.min(20000,distance*.015)))
  local nickname=text(s.player:GetObjName());assert(#nickname>0 and #nickname<=512,'Steam nickname unavailable')
  if nickname~=s.nickname then s.label:SetText(api.ftext(nickname));s.nickname=nickname end
  s.label:SetVisibility(true,false);s.label:SetHiddenInGame(false,false)
  s.marker:SetActorHiddenInGame(false);s.updates=s.updates+1
 end
 function s.attach(player,controller,verify)
  s.stop('replace_marker')
  assert(valid(player)and valid(controller)and valid(controller.Pawn),'Missing marker context')
  s.player=player;s.controller=controller;s.host=controller.Pawn;s.world=player:GetWorld();s.verify=verify;s.nickname=nil
  assert(same(s.world,s.host:GetWorld())and not same(player,s.host),'Foreign guest plane')
  assert(valid(controller.PlayerCameraManager),'Host camera unavailable')
  local class=api.static(path);assert(valid(class),'Stock target-container class unavailable')
  local actor=s.world:SpawnActor(class,player:K2_GetActorLocation(),{})
  assert(valid(actor),'Cannot create stock nickname container');s.marker=actor
  local ok,err=xpcall(function()
   assert(actor:GetClass():GetFullName()=='BlueprintGeneratedClass '..path,'Wrong HUD actor class')
   actor:SetOwner(player);actor:SetActorTickEnabled(false);actor:SetActorEnableCollision(false)
   for _,name in ipairs(parts)do local component=actor[name];if valid(component)then component:SetVisibility(false,false);component:SetHiddenInGame(true,false)end end
   s.label=actor.ObjectCallsignText;assert(valid(s.label),'Stock callsign text missing')
   s.label:SetTextRenderColor({R=90,G=255,B=125,A=255})
   s.active=true;s.reason=nil;s.update()
   s.loop=api.loop(1,function()
    if not s.active then return end
    local updated,message=xpcall(s.update,debug.traceback)
    if not updated then s.stop(message)end
   end)
  end,debug.traceback)
  if not ok then s.stop(err);error(err)end
  return s
 end
 return s
end
return M
