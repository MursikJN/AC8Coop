-- Isolated transport trial: reload the stock main-menu map using SteamNetDriver.
-- Only the first GameNetDriver definition is changed, in process memory, then restored.
-- Requires the preceding EOS listen trial and no guest connections; no campaign calls.
return function(output,stamp)
 assert(os.getenv('AC8_COOP_RECON')=='1','Research profile required')
 assert(_G.AC8SharedListenAttempted and not _G.AC8SharedSteamListenAttempted,'Unexpected trial order')
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local function log(event,...)
  local f=assert(io.open(output..'/native-steam-listen-'..stamp..'.tsv','a'))
  local row={os.time(),event,...};for i,v in ipairs(row)do row[i]=tostring(v):gsub('[\r\n\t]',' ')end
  f:write(table.concat(row,'\t'),'\n');f:close()
 end
 local pc=require('UEHelpers').GetPlayerController();assert(valid(pc),'Controller absent')
 local w=pc:GetWorld();assert(valid(w)and name(w):find('/Game/Maps/Menu/PL_MainMenu',1,true),'Main menu required')
 local d=w.NetDriver;assert(valid(d)and name(d):find('NetDriverEOS ',1,true),'Expected previous EOS driver')
 assert(not valid(d.ServerConnection)and d.ClientConnections:GetArrayNum()==0,'Cannot replace a connected world')
 local engines=FindAllOf('LiveGameEngine')or{};assert(#engines==1 and valid(engines[1]),'Engine ambiguous')
 local engine=engines[1];local list=engine.NetDriverDefinitions;local count=list:GetArrayNum();assert(count>0 and count<=16,'Driver count')
 local slot;for i=1,count do if list[i].DefName:ToString()=='GameNetDriver'then slot=i;break end end
 assert(slot,'Game driver definition absent')
 local old=list[slot].DriverClassName:ToString();local fallback=list[slot].DriverClassNameFallback:ToString()
 assert(old=='OnlineSubsystemEOS.NetDriverEOS','Unexpected first definition')
 local target='/Script/OnlineSubsystemSteam.SteamNetDriver'
 assert(valid(StaticFindObject(target))and valid(StaticFindObject('/Script/OnlineSubsystemUtils.IpNetDriver')),'Transport classes absent')
 local fn=StaticFindObject('/Script/Engine.GameplayStatics:OpenLevel');assert(valid(fn),'OpenLevel absent')
 local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()..':'..p:GetOffset_Internal()end)
 assert(table.concat(fields,',')=='WorldContextObject:ObjectProperty:0,LevelName:NameProperty:8,bAbsolute:BoolProperty:16,Options:StrProperty:24','OpenLevel signature changed')
 local library=StaticFindObject('/Script/Engine.Default__GameplayStatics');assert(valid(library),'GameplayStatics CDO absent')
 local restored=false
 local function restore()
  if restored then return end
  assert(valid(engine)and engine.NetDriverDefinitions:GetArrayNum()==count,'Engine definition changed')
  local current=engine.NetDriverDefinitions[slot]
  assert(current.DefName:ToString()=='GameNetDriver','Definition identity changed')
  local cls=current.DriverClassName:ToString();assert(cls==target or cls==old,'Definition externally modified')
  current.DriverClassName=FName(old);current.DriverClassNameFallback=FName(fallback)
  restored=true;log('definition_restored',slot,old,fallback)
 end
 _G.AC8SharedSteamListenAttempted=true
 log('definition_backup',slot,old,fallback)
 local ok,err=pcall(function()
  list[slot].DriverClassName=FName(target)
  assert(engine.NetDriverDefinitions[slot].DriverClassName:ToString()==target,'Driver write did not persist')
  log('open_level_enter',target,'/Game/Maps/Menu/PL_MainMenu?listen?Port=7777')
  library:OpenLevel(w,FName('/Game/Maps/Menu/PL_MainMenu'),true,'listen?Port=7777')
  log('open_level_returned')
 end)
 if not ok then restore();error(err)end
 local samples=0
 local function observe()
  samples=samples+1
  local good,why=pcall(function()
   local controller=require('UEHelpers').GetPlayerController();if not valid(controller)then log('waiting_controller',samples);return end
   local world=controller:GetWorld();if not valid(world)then log('waiting_world',samples);return end
   local driver=world.NetDriver;log('world',name(world),name(driver),name(world.AuthorityGameMode))
   if valid(driver)and driver:GetAddress()~=d:GetAddress()then
    log('new_driver',name(driver),name(driver.ServerConnection),driver.ClientConnections:GetArrayNum())
    restore();samples=30
   end
  end)
  if not good then log('observation_error',why)end
  if samples<30 then ExecuteInGameThreadWithDelay(1000,_G.AC8SharedSteamListenObserve)else
   local good,why=pcall(restore);log('trial_finished',good,why or'')
  end
 end
 _G.AC8SharedSteamListenObserve=observe;ExecuteInGameThreadWithDelay(1000,observe)
end
