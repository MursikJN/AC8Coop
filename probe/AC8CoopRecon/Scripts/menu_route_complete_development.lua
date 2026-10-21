-- Development fixture: exercise the production route without Steam or spawning a copy.
-- The game must already be at the stock main menu before this explicit job.
return function(output,stamp)
 assert(not _G.AC8CompleteRouteFixture,'A route fixture already ran in this process')
 local root=assert(os.getenv('AC8_COOP_RECON_EXTENSION')):match('^(.*)[/\\][^/\\]+$')
 local function log(action,detail)
  local f=assert(io.open(output..'/complete-route-events.tsv','a'));f:write(os.time(),'\t',action,'\t',tostring(detail):gsub('[\r\n\t]',' '),'\n');f:close()
 end
 local function loaded()
  local count=0
  for _,pc in ipairs(FindAllOf('LivePlayerController')or{})do
   if pc:IsValid()then
    local pawn=pc.Pawn;local world=pc:GetWorld()
    if pawn and pawn:IsValid()and pawn:IsA('/Script/Live.LivePlayerPlane')then
     if not world:IsValid()or not world:GetFullName():find('Mission007',1,true)or not pawn:GetClass():GetFullName():find('/PP0023_f14d/',1,true)then return false end
     count=count+1
    end
   end
  end
  return count==1
 end
 local route=assert(loadfile(root..'/coop_lobby_route.lua'))().game({now=os.time,log=log,flight_supported=loaded},output)
 _G.AC8CompleteRouteFixture=route
 route.begin(7,23,1)
 local function drive()
  local ok,err=pcall(route.update)
  local f=assert(io.open(output..'/complete-route-status.tsv','w'))
  f:write('fixture\tproduction_route_without_steam\nstamp\t',stamp,'\nphase\t',route.phase,'\nstep\t',route.step,'\nmission_loaded\t',loaded()and'1'or'0','\nerror\t',ok and''or tostring(err),'\n');f:close()
  if not ok then log('fixture_error',err);return end
  if route.phase=='flight'then log('fixture_mission_loaded','Mission007/F14D; activation not required by this read-only fixture');return end
  ExecuteInGameThreadWithDelay(1000,_G.AC8CompleteRouteDrive)
 end
 _G.AC8CompleteRouteDrive=drive;drive()
end
