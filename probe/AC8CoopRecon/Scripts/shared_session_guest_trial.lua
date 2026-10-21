-- Guest native world connection trial. No campaign selection, input emulation or plane spawn.
return function(output,stamp)
 assert(os.getenv('AC8_COOP_RECON')=='1','Research profile required')
 assert(not _G.AC8NativeGuestAttempted,'Only one native connection attempt per process')
 local id=assert(os.getenv('AC8_NATIVE_HOST_STEAM_ID'),'Host SteamID missing')
 assert(#id==17 and id:match('^7656119%d+$'),'Invalid host SteamID64')
 local function valid(o)return o and o:IsValid()end
 local function log(event,...)
  local f=assert(io.open(output..'/native-guest-'..stamp..'.tsv','a'));local a={os.time(),event,...}
  for i,v in ipairs(a)do a[i]=tostring(v):gsub('[\r\n\t]',' ')end;f:write(table.concat(a,'\t'),'\n');f:close()
 end
 local pc=require('UEHelpers').GetPlayerController();assert(valid(pc),'Controller absent')
 local w=pc:GetWorld();assert(valid(w)and w:GetFullName():find('/Game/Maps/Menu/PL_MainMenu',1,true),'Loaded main menu required')
 assert(not valid(w.NetDriver),'Guest already has a driver')
 local engines=FindAllOf('LiveGameEngine')or{};assert(#engines==1 and valid(engines[1]),'Engine ambiguous')
 local list=engines[1].NetDriverDefinitions;local count=list:GetArrayNum();assert(count>0 and count<=16,'Driver count')
 local slot;for i=1,count do if list[i].DefName:ToString()=='GameNetDriver'then slot=i;break end end;assert(slot,'Driver definition absent')
 local target='/Script/OnlineSubsystemSteam.SteamNetDriver';assert(valid(StaticFindObject(target)),'SteamNetDriver unavailable')
 local fn=StaticFindObject('/Script/Engine.GameplayStatics:OpenLevel');assert(valid(fn),'OpenLevel absent')
 local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()..':'..p:GetOffset_Internal()end)
 assert(table.concat(fields,',')=='WorldContextObject:ObjectProperty:0,LevelName:NameProperty:8,bAbsolute:BoolProperty:16,Options:StrProperty:24','OpenLevel signature changed')
 local library=StaticFindObject('/Script/Engine.Default__GameplayStatics');assert(valid(library),'GameplayStatics CDO absent')
 log('driver_definition_backup',slot,list[slot].DriverClassName:ToString(),list[slot].DriverClassNameFallback:ToString())
 -- Keep the transport definition for pending connection and subsequent host world travel.
 -- This is process-local; no INI or save data is edited.
 list[slot].DriverClassName=FName(target)
 assert(engines[1].NetDriverDefinitions[slot].DriverClassName:ToString()==target,'Definition write failed')
 _G.AC8NativeGuestAttempted=true
 local url='steam.'..id..':7777';log('native_connect_enter',url)
 library:OpenLevel(w,FName(url),true,'')
 log('native_connect_returned')
end
