-- First-flight candidate: load the stock terrain under Engine.GameModeBase,
-- keep local simulation paused, hide local gameplay actors per view, and render
-- host replicas through the GT adapter. Runtime readback, never a manual flag,
-- establishes readiness. This path has not yet been exercised in the game.
local M={}
local MAP='/Game/Maps/Ingame/Mission007/PL_Mission007'
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
function M.new(c,output,source,log,api)
 api=api or{player=function()return require('UEHelpers').GetPlayerController()end,find=FindAllOf,static=StaticFindObject}
 local gameplay=api.static('/Script/Engine.Default__GameplayStatics')
 local pause=api.pause or assert(loadfile(source..'/mission_sync_pause.lua'))().new(output,source)
 local visibility=api.visibility or assert(loadfile(source..'/scene_visibility.lua'))()
 local s={phase='waiting_host',requested=false,observed={},checks=0}
 local function save()
  local f=io.open(output..'/client-world-status.tsv','wb');if not f then return end
  f:write('phase\t',s.phase,'\nmap\t',MAP,'\ntravel_requested\t',s.requested and 1 or 0,'\npaused_readback_checks\t',s.checks,'\nready\t',s.context and s.context.isolated_world_verified and 1 or 0,'\ncinematic_adapter_enabled\t',c.cinema and 1 or 0,'\n');f:close()
 end
 local function belongs(o,world)return valid(o)and same(o:GetWorld(),world)end
 local function generic_mode(world)
  local found
  for _,o in ipairs(api.find('GameModeBase')or{})do if belongs(o,world)then assert(not found,'Multiple guest game modes');found=o end end
  return valid(found)and found:GetClass():GetFullName()=='Class /Script/Engine.GameModeBase'
 end
 local function actors(world)
  local found={};local count=0
  for _,kind in ipairs({'LiveGameObject','LiveAIGameObject','LivePlayerPlane'})do
   for _,o in ipairs(api.find(kind)or{})do if belongs(o,world)then
    local key=o:GetAddress();if not found[key]then count=count+1;assert(count<=2048,'Guest original actor budget');found[key]=o end
   end end
  end;return found
 end
 local function check_frozen(context)
  assert(same(api.player(),context.pc)and same(context.pc:GetWorld(),context.world)and same(context.pc.Pawn,context.pawn),'Guest world/controller changed')
  assert(generic_mode(context.world),'Guest campaign GameMode must not run')
  assert(not valid(context.world.NetDriver),'Replica terrain must not open a native NetDriver')
  local state=pause.command('acquire');assert(state.held=='1'and state.paused=='1','Guest stock pause not held')
  assert(gameplay:IsGamePaused(context.world),'Guest world unpaused')
  assert(math.abs(gameplay:GetTimeSeconds(context.world)-context.baseline)<.001,'Guest simulation advanced')
  local originals=actors(context.world)
  for key,o in pairs(originals)do
   local at=o:K2_GetActorLocation();local old=s.observed[key]
   if old then assert(math.abs(at.X-old.X)<.01 and math.abs(at.Y-old.Y)<.01 and math.abs(at.Z-old.Z)<.01,'Local guest actor moved')
   else s.observed[key]={X=at.X,Y=at.Y,Z=at.Z};s.stable_since=c.now end
  end
  originals[context.pawn:GetAddress()]=context.pawn;context.visibility.set(originals)
  s.checks=s.checks+1
  return c.now-(s.stable_since or c.now)>=1000 and s.checks>=10
 end
 function s.prepare_stage(phase,scene,snapshot)
  assert(c.role=='guest'and snapshot.mission=='6'and snapshot.difficulty=='1','Unsupported guest stage')
  if phase==1 and c.cinema then return {ready=c.cinema.ready and not c.cinema.error and(tonumber(snapshot.cinema_prepared)or 0)>=2,session_token=c.token,scene=scene}end
  -- This milestone displays the shared phase/loadout in the existing lobby.
  -- It does not claim to play the host cinematic on the guest yet.
  local visible=false
  for _,o in ipairs(api.find('LiveMenuMainTopWidget')or{})do if valid(o)and o:IsVisible()then visible=true end end
  s.phase=phase==1 and'waiting_ui_prepared'or'guest_loadout_ui_prepared';save()
  return {ready=visible,session_token=c.token,presentation='waiting_ui',scene=scene}
 end
 function s.cutscene(snapshot)
  if c.cinema then return end
  c.info='Хост смотрит вступление · Пропуск: '..(tonumber(snapshot.vote_mask)%2+(tonumber(snapshot.vote_mask)>=2 and 1 or 0))..'/2'
 end
 function s.prepare_flight(snapshot)
  assert(c.role=='guest'and snapshot.mission=='6'and snapshot.difficulty=='1'and snapshot.guest_aircraft=='23','Unsupported guest flight')
  if not s.requested then
   local pc=api.player();assert(valid(pc)and valid(pc:GetWorld()),'Guest menu world missing')
   assert(pc:GetWorld():GetFullName():find('/Game/Maps/Menu/PL_MainMenu',1,true),'Load replica terrain from main menu only')
   local fn=api.static('/Script/Engine.GameplayStatics:OpenLevel');assert(valid(fn),'OpenLevel missing')
   local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()..':'..p:GetOffset_Internal()end)
   assert(table.concat(fields,',')=='WorldContextObject:ObjectProperty:0,LevelName:NameProperty:8,bAbsolute:BoolProperty:16,Options:StrProperty:24','OpenLevel signature changed')
   if _G.AC8MainMenuEntry then _G.AC8MainMenuEntry.close()end
   s.requested=true;s.phase='loading_replica_terrain';s.requested_at=c.now;save();log('client_terrain_load',MAP)
   gameplay:OpenLevel(pc:GetWorld(),FName(MAP),true,'game=/Script/Engine.GameModeBase');return nil
  end
  assert(c.now-s.requested_at<120000 or s.context,'Guest terrain load timed out')
  local pc=api.player();if not valid(pc)or not valid(pc.Pawn)then return nil end
  local world=pc:GetWorld();if not valid(world)or not world:GetFullName():find(MAP,1,true)then return nil end
  assert(generic_mode(world),'GameMode override failed; guest campaign not permitted')
  assert(not valid(world.NetDriver),'Unexpected native guest connection')
  assert(not pc.Pawn:IsA('/Script/Live.LivePlayerPlane'),'Independent guest player simulation is not permitted')
  if not s.context then
   local result=pause.command('acquire');assert(result.held=='1'and result.paused=='1','Cannot hold guest simulation')
   s.context={pc=pc,pawn=pc.Pawn,world=world,load_assets=true,visibility=visibility.new(pc,world),session_token=c.token,generation=tonumber(snapshot.generation),revision=tonumber(snapshot.revision),baseline=gameplay:GetTimeSeconds(world),isolated_world_verified=false}
   s.stable_since=c.now;s.phase='verifying_paused_replica';save()
  end
  if check_frozen(s.context)then s.context.isolated_world_verified=true;s.phase='replica_world_ready';save();return s.context end
  return nil
 end
 function s.verify(context)
  if context~=s.context or context.session_token~=c.token or context.generation~=tonumber(c.snapshot.generation)or context.revision~=tonumber(c.snapshot.revision)then return false end
  return context.isolated_world_verified and check_frozen(context)
 end
 function s.stop(reason)
  if c.cinema then c.cinema.stop(reason)end
  s.phase='stopped';s.reason=reason
  if s.context and s.context.visibility then s.context.visibility.stop()end
  -- Keep local simulation paused until this development process exits. A
  -- stopped replica must not become an independently running campaign.
  save()
 end
 return s
end
return M
