-- One explicit native listen-server trial in the already-loaded MAIN MENU only.
-- Never opens a campaign, calls the menu route, edits saves or joins a third-party room.
return function(output,stamp)
 assert(os.getenv('AC8_COOP_RECON')=='1','Research profile required')
 assert(not _G.AC8SharedListenAttempted,'One listen attempt per process')
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local function log(event,...)
  local f=assert(io.open(output..'/native-listen-'..stamp..'.tsv','a'))
  local row={os.time(),event,...};for i,v in ipairs(row)do row[i]=tostring(v):gsub('[\r\n\t]',' ')end
  f:write(table.concat(row,'\t'),'\n');f:close()
 end
 local pc=require('UEHelpers').GetPlayerController();assert(valid(pc),'Controller absent')
 local world=pc:GetWorld();assert(valid(world)and name(world):find('/Game/Maps/Menu/PL_MainMenu',1,true),'Trial requires stock main menu')
 assert(not valid(world.NetDriver),'World already has a network driver')
 local engines=FindAllOf('LiveGameEngine')or{};assert(#engines==1 and valid(engines[1]),'Engine ambiguous')
 local list=engines[1].NetDriverDefinitions;local count=list:GetArrayNum();assert(count>0 and count<=16,'Invalid driver definitions')
 local game_driver
 for i=1,count do local d=list[i];local key=d.DefName:ToString();local cls=d.DriverClassName:ToString();log('driver_definition',key,cls,d.DriverClassNameFallback:ToString());if key=='GameNetDriver'then game_driver=cls end end
 assert(game_driver and valid(StaticFindObject(game_driver)),'Configured native game driver is unavailable')
 local fn=StaticFindObject('/Script/Engine.GameplayStatics:OpenLevel');assert(valid(fn),'OpenLevel absent')
 local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()..':'..p:GetOffset_Internal()end)
 assert(table.concat(fields,',')=='WorldContextObject:ObjectProperty:0,LevelName:NameProperty:8,bAbsolute:BoolProperty:16,Options:StrProperty:24','OpenLevel signature changed')
 local library=StaticFindObject('/Script/Engine.Default__GameplayStatics');assert(valid(library),'GameplayStatics CDO absent')
 _G.AC8SharedListenAttempted=true
 log('open_level_enter',name(world),game_driver,'/Game/Maps/Menu/PL_MainMenu?listen?Port=7777')
 library:OpenLevel(world,FName('/Game/Maps/Menu/PL_MainMenu'),true,'listen?Port=7777')
 log('open_level_returned')
 local samples=0
 local function observe()
  samples=samples+1
  local ok,err=pcall(function()
   local controller=require('UEHelpers').GetPlayerController()
   if not valid(controller)then log('waiting_controller',samples);return end
   local w=controller:GetWorld();if not valid(w)then log('waiting_world',samples);return end
   local driver=w.NetDriver;log('world',name(w),'driver',name(driver),'mode',name(w.AuthorityGameMode))
   if valid(driver)then
    log('driver_verified',name(driver),name(driver.ServerConnection),driver.ClientConnections:GetArrayNum());samples=30
   end
  end)
  if not ok then log('observation_error',err)end
  if samples<30 then ExecuteInGameThreadWithDelay(1000,_G.AC8SharedListenObserve)else log('trial_observation_finished')end
 end
 _G.AC8SharedListenObserve=observe;ExecuteInGameThreadWithDelay(1000,observe)
end
