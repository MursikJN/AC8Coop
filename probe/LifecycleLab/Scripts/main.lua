-- Lifecycle laboratory: current native loopback protocol + read-only UE observations.
-- Optional flight disconnect stop uses the guarded stock pause adapter only.
assert(os.getenv('AC8_LIFECYCLE_LAB')=='25201480')
local output=assert(os.getenv('AC8_COOP_RECON_OUTPUT'))
local dll=assert(os.getenv('AC8_LOCAL_DLL'))
local start=assert(package.loadlib(dll,'luaopen_ac8_local_start'));start()
local stop
if os.getenv('AC8_LIFECYCLE_STOP')=='25201480'then
 assert(os.getenv('AC8_LOCAL_ROLE')=='host','stop lab requires host')
 local source=assert(os.getenv('AC8_LIFECYCLE_SCRIPTS'))
 local pause=dofile(source..'/mission_sync_pause.lua').new(output,source)
 stop=dofile(source..'/disconnect_stop.lua').new(pause,assert(os.getenv('AC8_LOCAL_TOKEN')),function(event,reason)
  local f=assert(io.open(output..'/disconnect-stop-events.tsv','a'))
  f:write(os.time(),'\t',event,'\t',tostring(reason):gsub('[\t\r\n]',' '),'\n');f:close()
 end)
end
local function valid(o)return o and o:IsValid()end
local function clean(s)return tostring(s or''):gsub('[\t\r\n]',' ')end
local function visible(q,details)
 local active=0
 for _,o in pairs(FindAllOf(q)or{})do
  if valid(o)and not o:GetFullName():find('Default__',1,true)then
   local v=o.Visibility
   details[#details+1]=q..'|'..o:GetFullName()..'|visibility='..tostring(v)..'|visible='..tostring(o:IsVisible())..'|viewport='..tostring(o:IsInViewport())
   -- Stock menu adapter checks Visibility=Visible. Child widgets need not be
   -- directly in the viewport. These are candidates until compared with UI.
   if v==0 then active=active+1 end
  end
 end
 return active
end
local last_payload
local function tick()
 local ok,err=pcall(function()
  assert(IsInGameThread(),'wrong_thread')
  local details={}
  local rows={utc=os.time(),role=os.getenv('AC8_LOCAL_ROLE'),playing_cinema=0,flight=0}
  for name,q in pairs({main_menu='LiveMenuMainTopWidget',campaign='LiveMenuCampaignTopWidget',difficulty='LiveMenuCampaignFreeMissionDifficultyWidget',mission_select='LiveMenuCampaignFreeMissionWidget',narrative='LiveMenuCampaignNarrativeSelectWidget',briefing='LiveMenuBriefingProgressWidget',hangar_top='LiveMenuHangarTopWidget',hangar_squad='LiveMenuHangarSquadWidget',hangar_aircraft='LiveMenuHangarAircraftSettingWidget',hangar_standby='LiveMenuHangarStandbyWidget'})do rows[name]=visible(q,details)end
  for _,o in pairs(FindAllOf('LiveCinematicsLevelSequencePlayer')or{})do
   if valid(o)and not o:GetFullName():find('Default__',1,true)and o:IsPlaying()then rows.playing_cinema=rows.playing_cinema+1 end
  end
  for _,o in pairs(FindAllOf('PlayerController')or{})do
   if valid(o)and not o:GetFullName():find('Default__',1,true)then
    local w=o:GetWorld();if valid(w)then
     rows.world=w:GetFullName();rows.controller=o:GetFullName()
     local gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')
     if valid(gs)then rows.paused=gs:IsGamePaused(o)and 1 or 0;rows.world_time=gs:GetTimeSeconds(o)end
     if valid(o.Pawn)then rows.pawn=o.Pawn:GetFullName()end
     if valid(o.Pawn)and rows.world:find('/Mission007/PL_Mission007',1,true)and o.Pawn:IsA('/Script/Live.LivePlayerPlane')then
      rows.flight=1;rows.active=o.Pawn.bIsActivated and 1 or 0;rows.igc=o.Pawn.bIsIGCActor and 1 or 0
      local p=o.Pawn:K2_GetActorLocation();rows.x=p.X;rows.y=p.Y;rows.z=p.Z
     end
    end
   end
  end
  if stop then
   local f=io.open(output..'/shared-session-status.tsv','r');local text
   if f then text=f:read(8193);f:close()end
   rows.disconnect_stop=stop.step(text,rows,os.time())
   rows.disconnect_stop_error=stop.error or''
  end
  local lines={};for k,v in pairs(rows)do lines[#lines+1]=k..'\t'..clean(v)..'\n'end;table.sort(lines)
  local f=assert(io.open(output..'/game-observation.tsv','w'));f:write(table.concat(lines));f:close()
  local key={};for k,v in pairs(rows)do if k~='utc'and k~='world_time'and k~='x'and k~='y'and k~='z'then key[#key+1]=k..'='..clean(v)end end;table.sort(key)
  local payload=table.concat(key,';')
  if payload~=last_payload then
   f=assert(io.open(output..'/game-transitions.tsv','a'));f:write(os.time(),'\t',payload,'\n');f:close();last_payload=payload
   f=assert(io.open(output..'/widget-details.tsv','w'));f:write(table.concat(details,'\n'));f:close()
  end
 end)
 if not ok then local f=io.open(output..'/game-observation-errors.log','a');if f then f:write(os.time(),'\t',clean(err),'\n');f:close()end end
 ExecuteInGameThreadWithDelay(1000,tick)
end
ExecuteInGameThreadWithDelay(1000,tick)
