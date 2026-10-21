-- Read-only host exporter. Runs on the game thread, with bounded inventories.
local M={}
local function valid(o)return o and o:IsValid()end
local function name(o)return valid(o)and o:GetFullName()or''end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function finite(x)return type(x)=='number'and x==x and math.abs(x)<1e12 end
local menu_classes={
 {'LiveMenuHangarStandbyWidget','hangar_standby'},{'LiveMenuHangarAircraftSettingWidget','hangar_aircraft'},
 {'LiveMenuHangarSquadWidget','hangar_squad'},{'LiveMenuHangarTopWidget','hangar'},
 {'LiveMenuBriefingProgressWidget','briefing'},{'LiveMenuCampaignNarrativeSelectWidget','narrative'},
 {'LiveMenuCampaignFreeMissionWidget','mission_select'},{'LiveMenuCampaignFreeMissionDifficultyWidget','difficulty'},
 {'LiveMenuCampaignTopWidget','campaign'},{'LiveMenuMainTopWidget','main_menu'},
}
function M.new(output,source,controller,api)
 api=api or{find=FindAllOf,static=StaticFindObject}
 local clock=assert(loadfile(source..'/scene_clock.lua'))()
 local visuals=assert(loadfile(source..'/scene_visual_host.lua'))().new(source,api)
 local codec=assert(loadfile(source..'/scene_codec.lua'))()
 local s={sequence=0,generation=0,next_id=0,next_event=0,events={},registry={},previous={},schemas={},ticks=0}
 local mathlib=api.static('/Script/Engine.Default__KismetMathLibrary');local gameplay=api.static('/Script/Engine.Default__GameplayStatics')
 local function event(kind,entity,detail)
  s.next_event=s.next_event+1;s.events[#s.events+1]={id=s.next_event,kind=kind,entity=entity,detail=detail or''}
  if #s.events>codec.MAX_EVENTS then table.remove(s.events,1)end
 end
 local function properties(o)
  local c=o:GetClass();local key=name(c);if s.schemas[key]then return s.schemas[key]end
  local result={};for _=1,20 do if not valid(c)then break end
   local count=0;c:ForEachProperty(function(p)count=count+1;assert(count<=1024,'Property budget');result[p:GetFName():ToString()]=true end);c=c:GetSuperStruct()
  end;s.schemas[key]=result;return result
 end
 function s.capture()
  assert(valid(mathlib)and valid(gameplay),'Scene libraries missing')
  local pc,world,host;for _,o in ipairs(api.find('LivePlayerController')or{})do if valid(o)and valid(o:GetWorld())then
   assert(not pc,'Multiple local controllers require a separate scene renderer');pc=o;world=o:GetWorld();host=o.Pawn
  end end
  local current=controller.snapshot or{}
  local observed='loading'
  if valid(host)and valid(world)and world:GetFullName():find('/Maps/Ingame/',1,true)and host:IsA('/Script/Live.LivePlayerPlane')then observed='flight'end
  if observed~='flight'then for _,entry in ipairs(menu_classes)do
   for _,o in ipairs(api.find(entry[1])or{})do if valid(o)and o.Visibility==0 then observed=entry[2];if not world then world=o:GetWorld()end;break end end
   if observed~='loading'then break end
  end end
  if observed=='loading'and valid(host)and host:IsA('/Script/Live.LivePlayerPlane')then observed='flight'end
  s.world=world;s.pc=pc
  local world_name=name(world);local world_key=world_name..(valid(world)and tostring(world:GetAddress())or'')
  if s.world_key~=world_key then
   s.world_key=world_key;s.generation=s.generation+1;s.registry={};s.previous={};s.events={};s.next_event=0;s.schemas={};s.last_menu=nil;s.last_paused=nil
   visuals.clear()
   event('scene',0,world_name)
  end
  local session={observed=observed}
  for _,k in ipairs({'epoch','mission','difficulty','scene','host_aircraft','guest_aircraft'})do session[k]=tonumber(current[k])or 0 end
  session.stage=tonumber(current.phase)or 0;session.ready=tonumber(current.ready_mask)or 0;session.loaded=tonumber(current.loaded_mask)or 0;session.votes=tonumber(current.vote_mask)or 0
  local menu_key=table.concat({session.stage,observed,session.mission,session.difficulty,session.ready,session.host_aircraft,session.guest_aircraft},':')
  if menu_key~=s.last_menu then event('configuration',0,menu_key);s.last_menu=menu_key end
  local paused=valid(world)and gameplay:IsGamePaused(world)or false
  if paused~=s.last_paused then event('pause',0,paused and'paused'or'running');s.last_paused=paused end
  local entities,seen,next_previous={}, {}, {};local complete=true;local visited=0;local parts={};local visual_complete=true
  for _,query in ipairs({'LivePlayerPlane','LiveAIGameObject'})do
   for _,o in ipairs(api.find(query)or{})do
    visited=visited+1;if visited>8192 then complete=false;break end
    if valid(o)and valid(world)and valid(o:GetWorld())and o:GetWorld():GetAddress()==world:GetAddress()then
     local key=name(o)..':'..tostring(o:GetAddress())
     if not seen[key]then
      seen[key]=true;local fields=properties(o)
      if not fields.bIsActivated or o.bIsActivated then
       if #entities>=codec.MAX_ENTITIES then complete=false;break end
       local old=s.registry[key];if not old then s.next_id=s.next_id+1;old={id=s.next_id};s.registry[key]=old end
       old.object=o
       local class=name(o:GetClass()):gsub('^[^ ]+ ','');local kind='object'
       if class:lower():find('plane',1,true)or query=='LivePlayerPlane'then kind='plane'
       elseif class:lower():find('missile',1,true)or class:lower():find('weapon',1,true)then kind='weapon'
       elseif class:lower():find('ship',1,true)then kind='ship'
       elseif class:lower():find('ground',1,true)then kind='ground'end
       local label=fields.ObjNameID and text(o.ObjNameID)or name(o):match('[^.]+$')or''
       local role=4;if valid(host)and o:GetAddress()==host:GetAddress()then role=0
       elseif label:match('Joker2$')then role=1 elseif label:match('Joker3$')then role=2 elseif label:match('Joker4$')then role=3 end
       if _G.AC8GuestRoleRuntime and valid(_G.AC8GuestRoleRuntime.player)and o:GetAddress()==_G.AC8GuestRoleRuntime.player:GetAddress()then role=1 end
       local p=o:K2_GetActorLocation();local q=mathlib:Conv_RotatorToQuaternion(o:K2_GetActorRotation())
       local health=false;if fields.HealthInternal then local hp=o.HealthInternal;if finite(hp)and hp>=0 then health=hp end end
       local e={id=old.id,kind=kind,role=role,alive=health==false or health>0,health=health,asset=class,label=label,position={p.X,p.Y,p.Z},rotation={q.X,q.Y,q.Z,q.W}}
       entities[#entities+1]=e;next_previous[e.id]=e
       local ok,catalog=pcall(visuals.collect,o,e)
       if ok then for _,v in ipairs(catalog)do if #parts<codec.MAX_VISUALS then parts[#parts+1]=v else visual_complete=false end end
       else visual_complete=false;s.visual_error=tostring(catalog)end
       local previous=s.previous[e.id];if not previous then event('spawn',e.id,e.label)
       elseif previous.health~=health then event('health',e.id,tostring(health));if previous.alive and not e.alive then event('death',e.id,e.label)end end
      end
     end
    end
   end
  end
  if complete then
   for id,e in pairs(s.previous)do if not next_previous[id]then event('despawn',id,e.label)end end
   local next_registry={};for key,r in pairs(s.registry)do if next_previous[r.id]then next_registry[key]=r end end;s.registry=next_registry;s.previous=next_previous
  end
  s.sequence=s.sequence+1
  local source_ms=api.clock and api.clock()or(valid(world)and math.floor(clock.milliseconds(world,gameplay))or 0)
  local frame={sequence=s.sequence,generation=s.generation,revision=tonumber(current.revision)or 1,source_ms=source_ms,world=world_name,complete=complete,paused=paused,session=session,entities=entities,events=s.events,event_cursor=s.next_event,visuals=parts,visual_complete=visual_complete}
  return codec.encode(frame)
 end
 function s.update()
  s.ticks=s.ticks+1
  local ok,data=xpcall(s.capture,debug.traceback)
  if ok then
   local f=assert(io.open(output..'/scene-host.ac8w.tmp','wb'));f:write(data);f:close()
   -- Windows rename cannot replace an existing target. Readers require a valid
   -- footer and advancing sequence; an absent file between these calls is OK.
   os.remove(output..'/scene-host.ac8w');local published,why=os.rename(output..'/scene-host.ac8w.tmp',output..'/scene-host.ac8w')
   s.error=not published and('publish_retry: '..tostring(why))or nil
  else s.error=data end
  local f=io.open(output..'/scene-host-status.tsv','w');if f then f:write('sequence\t',s.sequence,'\ngeneration\t',s.generation,'\nerror\t',(s.error or''):gsub('[\r\n\t]',' '),'\nvisual_error\t',(s.visual_error or''):gsub('[\r\n\t]',' '),'\nfull_mission_replication\t0\n');f:close()end
 end
 return s
end
return M
