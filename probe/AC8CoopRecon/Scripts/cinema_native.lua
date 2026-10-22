-- Exact reflected game APIs. Missing signatures/resources block the barrier.
-- Native LiveCinematics is required for game voice/Sofdec tracks; the generic
-- engine LevelSequence factory cannot stand in for it.
local M={}
local function valid(o)return o and o:IsValid()end
local function path(o,allow_script)
 if not valid(o)then return end
 local p=o:GetFullName():match('^[^ ]+ (/.+)$')
 if p and #p<=383 and not p:find('..',1,true)and(p:match('^/Game/[%w_/%.%-]+$')or allow_script and p:match('^/Script/[%w_/%.%-]+$'))then return p end
end
local function seconds(t)
 if type(t)=='number'then return t end
 local rate=t.Rate;local frame=t.Time
 assert(rate and frame and rate.Numerator>0 and rate.Denominator>0,'Unrecognized cinematic time struct')
 return(frame.FrameNumber.Value+(frame.SubFrame or 0))*rate.Denominator/rate.Numerator
end
function M.new(c,source,log,api)
 api=api or{find=FindAllOf,static=StaticFindObject,load=LoadAsset,construct=StaticConstructObject,player=function()return require('UEHelpers').GetPlayerController()end}
 local cache={};local observed={};local owned={};local serial=0
 local function check(pathname,expected)
  if cache[pathname]then return end
  local fn=api.static(pathname);assert(valid(fn),'Missing cinematic API '..pathname)
  local actual={};fn:ForEachProperty(function(p)actual[#actual+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()end)
  assert(table.concat(actual,',')==expected,'Changed cinematic API '..pathname);cache[pathname]=true
 end
 local function mana_checks()
  local base='/Script/Live.LiveManaMovieViewer:'
  for k,v in pairs({PauseMovie='',StopMovie='',CloseMovie='',GetManaPlayer='ReturnValue:ObjectProperty',GetTimeSeconds='ReturnValue:FloatProperty',PlayMovie='IsLoop:BoolProperty,ReturnValue:BoolProperty',SetMediaSource='InSource:ObjectProperty,bIsPlayOnOpen:BoolProperty'})do check(base..k,v)end
 end
 local function enum(entry)
  local e
  for _,p in ipairs({'/Script/CriWareRuntime.EManaPlayerTrack','/Script/Mana.EManaPlayerTrack'})do local o=api.static(p);if valid(o)then e=o;break end end
  assert(valid(e),'Missing reflected Mana track enum');local value
  e:ForEachName(function(n,v)if n:ToString():match('([^:]+)$')==entry then value=v end end)
  assert(value~=nil,'Missing cinema enum entry '..entry);return value
 end
 local duration
 local metadata_log={};local pending_movies={}
 local function metadata(p,state,value)
  local key=tostring(p:GetAddress());local message=state..' seconds='..tostring(value)
  if metadata_log[key]~=message then metadata_log[key]=message;log('cinema_metadata',key..' '..message)end
 end
 local function mana_sample(h)
  local p=h.object:GetManaPlayer()
  if not valid(p)and not h.was_ready then return {ready=false}end
  assert(valid(p),'Native Mana player disappeared')
  assert(not p:HasError(),'Native movie open failed')
  if not p:IsReady()or p:IsPreparing()then return {ready=false}end
  if path(h.object.PlayingManaSource)~=h.descriptor.asset then
   assert(not h.was_ready,'Prepared movie source changed');return {ready=false}
  end
  local video=enum('Video');local audio=enum('Audio')
  local videos=p:GetNumTracks(video);local audios=p:GetNumTracks(audio)
  local ready=valid(h.object.ManaTexture)and videos>0 and p:GetSelectedTrack(video)>=0 and(audios==0 or p:GetSelectedTrack(audio)>=0)
  local local_duration=duration(p)
  if not local_duration then assert(not h.was_ready,'Prepared movie duration disappeared');return {ready=false,reason='duration_pending'}end
  assert(math.abs(local_duration-h.descriptor.duration_ms)<=100,'Local cinematic resource duration mismatch')
  if ready then h.was_ready=true end
  local time=h.object:GetTimeSeconds();assert(type(time)=='number'and time==time and time>=0,'Invalid movie time')
  return {ready=ready,remaining_ms=math.max(0,local_duration-time*1000),ended=time*1000>=local_duration-15}
 end
 duration=function(p)
  -- FTimespan is an opaque reflected struct. Its C++ Ticks member is not a
  -- supported Lua field. Pass the value unchanged to the game's UFunction.
  local pathname='/Script/Engine.KismetMathLibrary:GetTotalSeconds'
  check(pathname,'A:StructProperty,ReturnValue:FloatProperty')
  local fn=api.static(pathname)
  fn:ForEachProperty(function(prop)
   if prop:GetFName():ToString()=='A'then assert(prop:GetStruct():GetFullName()=='ScriptStruct /Script/CoreUObject.Timespan','Changed Timespan conversion input')end
  end)
  local t=p:GetDuration();assert(t~=nil,'Native movie duration struct missing')
  local library=api.static('/Script/Engine.Default__KismetMathLibrary');assert(valid(library),'Timespan converter unavailable')
  local value=library:GetTotalSeconds(t)
  local finite=type(value)=='number'and value==value and value~=math.huge and value~=-math.huge
  if not finite or value<0 or value>3600 or(value>0 and value<.5)then
   metadata(p,'invalid_'..type(value),value);error('Invalid native movie duration from GetTotalSeconds: '..tostring(value))
  end
  if value==0 then metadata(p,'pending',value);return nil end
  metadata(p,'ready',value);return math.floor(value*1000+.5)
 end
 local function options_from(asset)
  local found
  asset:GetClass():ForEachProperty(function(p)
   if p:GetClass():GetFName():ToString()=='StructProperty'and p:GetStruct():GetFullName()=='ScriptStruct /Script/LiveCinematics.LiveCinematicsSequenceOptions'then
    assert(not found,'Ambiguous sequence options');found=asset[p:GetFName():ToString()]
   end
  end)
  return found
 end
 local function sequence_options(sequence)
  local seq=api.static(sequence);if valid(seq)and options_from(seq)then return sequence end
  local seen={};local count=0
  for _,kind in ipairs({'LiveCinematicsSequenceData','LiveCinematicsSequenceDataTable','DataAsset'})do
  local ok,items=pcall(api.find,kind)
  for _,data in ipairs(ok and items or{})do if path(data)and not seen[data:GetAddress()]then
   seen[data:GetAddress()]=true;count=count+1;assert(count<=2048,'Cinematic options scan budget')
   local matches=false;data:GetClass():ForEachProperty(function(p)
    if p:GetClass():GetFName():ToString()=='ObjectProperty'then local v=data[p:GetFName():ToString()];if path(v)==sequence then matches=true end end
   end)
   if matches and options_from(data)then return path(data)end
  end end end
  error('No verified local LiveCinematics options asset for '..sequence)
 end
 local function same_world(o)
  local pc=api.player();if not valid(pc)or not valid(o)then return false end
  local world=o:GetWorld();local player_world=pc:GetWorld()
  return valid(world)and valid(player_world)and world:GetAddress()==player_world:GetAddress()
 end
 local function visible(o)
  local seen={}
  for _=1,64 do
   if not valid(o)or not o:IsA('/Script/UMG.Widget')or not o:IsVisible()then return false end
   local id=o:GetAddress();if seen[id]then return false end;seen[id]=true
   local parent=o:GetParent()
   if valid(parent)then o=parent
   elseif o:IsA('/Script/UMG.UserWidget')and o:IsInViewport()then return true
   else
    local tree=o:GetOuter()
    if not valid(tree)or not tree:IsA('/Script/UMG.WidgetTree')then return false end
    o=tree:GetOuter()
   end
  end
  return false
 end
 local E={}
 function E.discover()
  local result
  for _,v in ipairs(api.find('LiveCinematicsLevelSequencePlayer')or{})do if valid(v)and same_world(v)and(v:IsPlaying()or v:IsPaused())then
   assert(not result,'Multiple native cinematic sequences');local asset=assert(path(v:GetSequence()),'Unknown sequence asset')
   local id=tostring(v:GetAddress())..':'..asset;result=observed[id]
   if not result then
    local length=seconds(v:GetEndTime())-seconds(v:GetStartTime());assert(length>=.5 and length<=3600,'Invalid sequence duration')
    result={object=v,identity=id,descriptor={kind=2,asset=asset,options=sequence_options(asset),viewer='',duration_ms=math.floor(length*1000+.5)}};observed[id]=result
   end
  end end
  if result then return result end
  for _,v in ipairs(api.find('LiveManaMovieViewer')or{})do if valid(v)and same_world(v)and visible(v)and path(v.PlayingManaSource)then
   mana_checks();local player=v:GetManaPlayer()
   if valid(player)and player:IsReady()and not player:IsPreparing()and(player:IsPlaying()or player:IsPaused())then
    assert(not result,'Multiple active cinematic sources');local id=tostring(v:GetAddress())..':'..path(v.PlayingManaSource)
    assert(not player:HasError(),'Native movie open failed')
    local length=duration(player)
    if not length then
     if not pending_movies[id]then v:PauseMovie();assert(player:IsPaused()or not player:IsPlaying(),'Pending movie did not pause');pending_movies[id]=true end
     return nil -- No descriptor or prepared receipt until actual metadata exists.
    end
    pending_movies[id]=nil
    result=observed[id]or{object=v,identity=id,descriptor={kind=1,asset=path(v.PlayingManaSource),viewer=path(v:GetClass(),true),options='',duration_ms=length}};observed[id]=result
    assert(result.descriptor.viewer,'Unverified movie viewer class')
   end
  end end
  return result
 end
 function E.open(d)
  assert((d.kind==1 or d.kind==2)and type(d.duration_ms)=='number'and d.duration_ms>=500 and d.duration_ms<=3600000,'Invalid cinematic descriptor')
  local asset=api.load(d.asset);assert(valid(asset)and path(asset)==d.asset,'Cinematic asset could not be loaded locally')
  if _G.AC8MainMenuEntry then _G.AC8MainMenuEntry.close()end
  local h={descriptor=d,owned=true,pc=api.player()};owned[h]=true
  local function create()
  h.view_target=h.pc:GetViewTarget()
  if d.kind==1 then
   mana_checks();local cls=api.static(d.viewer);if not valid(cls)then cls=api.load(d.viewer)end
   assert(valid(cls)and cls:IsChildOf(api.static('/Script/Live.LiveManaMovieViewer'))and cls:IsChildOf(api.static('/Script/UMG.Widget')),'Not a movie viewer widget class')
   -- The same display-only stock template as r26's status UI. Its real asset
   -- path is in skip-ticket-skip1.tsv. No stock skip manager is attached.
   local surface_class=api.load('/Game/Blueprints/UI/Cinematics/WBP_Cinema_SkipButton_000.WBP_Cinema_SkipButton_000_C')
   assert(valid(surface_class),'Guest cinema surface template unavailable')
   local library=api.static('/Script/UMG.Default__WidgetBlueprintLibrary')
   h.surface=library:Create(h.pc,surface_class,h.pc)
   assert(valid(h.surface)and valid(h.surface.WidgetTree),'Guest cinema surface creation failed')
   local root=h.surface.RootPanel;assert(valid(root)and root:IsA('/Script/UMG.CanvasPanel'),'Guest movie canvas is unavailable')
   assert(root:GetChildrenCount()<=32,'Cinema surface child budget')
   for i=0,root:GetChildrenCount()-1 do root:GetChildAt(i):SetVisibility(1)end
   serial=serial+1;local pc=api.player()
   if cls:IsChildOf(api.static('/Script/UMG.UserWidget'))then h.object=library:Create(pc,cls,pc)
   else h.object=api.construct(cls,h.surface.WidgetTree,FName('AC8_LocalMovie_'..serial))end
   assert(valid(h.object),'Movie widget creation failed')
   local slot=root:AddChildToCanvas(h.object);slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}});slot:SetOffsets({Left=0,Top=0,Right=0,Bottom=0});slot:SetZOrder(1000)
   h.object:SetVisibility(3);h.object:SetMediaSource(asset,false)
   h.label=api.construct(api.static('/Script/UMG.TextBlock'),h.surface.WidgetTree,FName('AC8_CinemaStatus_'..serial));assert(valid(h.label),'Guest cinema status unavailable')
   h.label.Font.Size=30;h.label:SetVisibility(3)
   local label_slot=root:AddChildToCanvas(h.label);label_slot:SetPosition({X=80,Y=85});label_slot:SetSize({X=1700,Y=100});label_slot:SetZOrder(1001)
   root:SetVisibility(3);h.surface:SetVisibility(3);h.surface:AddToViewport(1000)
  else
   local p='/Script/LiveCinematics.LiveCinematicsBlueprintFunctionLibrary:PlayNotRegisteredSequence'
   check(p,'WorldContextObject:ObjectProperty,SequenceAssetPath:StrProperty,Options:StructProperty,PlaybackSettings:StructProperty,OnFinished:DelegateProperty,ReturnValue:BoolProperty')
   local data=api.load(d.options);assert(valid(data)and path(data)==d.options,'Sequence environment options missing')
   local options=assert(options_from(data),'Native sequence options unavailable')
   local settings={bDisableGameProcess=true,bDisableCameraCuts=false,bOverrideSkipDisabled=true,bSkipDisabledOverride=true,bOverridePauseDisabled=true,bPauseDisabledOverride=false,bOverrideStartTime=true,StartTimeOverride=0,bOverridePlayRate=true,PlayRateOverride=1,bDisableWaitLoadingScreenFadeOut=true,bOverrideSkipFadeIn=true,bSkipFadeInOverride=true}
   h.before={};for _,v in ipairs(api.find('LiveCinematicsLevelSequencePlayer')or{})do if valid(v)then h.before[v:GetAddress()]=true end end
   local library=api.static('/Script/LiveCinematics.Default__LiveCinematicsBlueprintFunctionLibrary')
   -- No campaign completion delegate is attached on the guest.
   assert(library:PlayNotRegisteredSequence(api.player():GetWorld(),d.asset,options,settings,nil),'Native sequence preparation failed')
  end
  log('cinema_asset_open',d.asset);return h
  end
  local ok,result=xpcall(create,debug.traceback)
  if not ok then pcall(E.close,h,true);error(result)end
  return result
 end
 function E.sample(h)
  if h.descriptor.kind==2 and not valid(h.object)then
   for _,v in ipairs(api.find('LiveCinematicsLevelSequencePlayer')or{})do if valid(v)and same_world(v)and not h.before[v:GetAddress()]and path(v:GetSequence())==h.descriptor.asset then
    assert(not h.object,'Multiple guest sequence players');h.object=v;v:Pause();assert(v:IsPaused(),'Sequence did not pause')
   end end
   if not h.object then return {ready=false}end
  end
  assert(valid(h.object),'Cinematic player disappeared before a terminal receipt')
  if h.descriptor.kind==1 then return mana_sample(h)end
  local time=seconds(h.object:GetCurrentTime())-seconds(h.object:GetStartTime())
  local length=seconds(h.object:GetEndTime())-seconds(h.object:GetStartTime())
  assert(time>=0 and length>0,'Invalid sequence timeline')
  -- A real camera and the native Live player are required, not a waiting panel.
  return {ready=valid(h.object:GetActiveCameraComponent()),remaining_ms=math.max(0,(length-time)*1000),ended=time>=length-.015}
 end
 function E.pause(h)
  if not valid(h.object)then return end
  if h.descriptor.kind==1 then
   h.object:PauseMovie();local p=h.object:GetManaPlayer()
   if valid(p)and p:IsReady()then assert(p:IsPaused()or not p:IsPlaying(),'Movie did not pause')end
  else h.object:Pause();assert(h.object:IsPaused()or not h.object:IsPlaying(),'Sequence did not pause')end
 end
 function E.play(h)
  assert(valid(h.object),'Cinematic player unavailable')
  if h.descriptor.kind==1 then assert(h.object:GetManaPlayer():Play(),'Movie failed to resume')else h.object:Play()end
 end
 function E.skip(h,guest)
  -- The host's existing two-vote guard invokes its stock campaign skip once.
  if not guest then return end
  assert(valid(h.object),'Cinematic player unavailable at shared skip')
  if h.descriptor.kind==1 then h.object:StopMovie()else h.object:GoToEndAndStop()end
 end
 function E.status(h,text)if valid(h.label)then h.label:SetText(FText(text))end end
 function E.close(h,guest)
  if guest and h.owned and valid(h.object)then
   if h.descriptor.kind==1 then h.object:CloseMovie();h.object:RemoveFromParent()else h.object:Stop()end
  end
  if guest and h.owned and valid(h.surface)then h.surface:RemoveFromParent()end
  if guest and h.owned and valid(h.pc)and valid(h.view_target)and h.pc:GetWorld():GetAddress()==h.view_target:GetWorld():GetAddress()then
   check('/Script/Engine.PlayerController:SetViewTargetWithBlend','NewViewTarget:ObjectProperty,BlendTime:FloatProperty,BlendFunc:ByteProperty,BlendExp:FloatProperty,bLockOutgoing:BoolProperty')
   h.pc:SetViewTargetWithBlend(h.view_target,0,0,0,false)
  end;owned[h]=nil
 end
 function E.abort()
  local all={};for h in pairs(owned)do all[#all+1]=h end
  for _,h in ipairs(all)do local ok,err=pcall(E.close,h,true);if not ok then log('cinema_cleanup_error',err)end end
 end
 -- Keep the innermost stage in the crash report if ProcessEvent cannot return.
 if c.engine_call then
  for _,name in ipairs({'discover','open','sample','pause','play','skip','status','close','abort'})do
   local fn=E[name]
   E[name]=function(...)return c.engine_call('cinema.'..name,fn,...)end
  end
 end
 return E
end
return M
