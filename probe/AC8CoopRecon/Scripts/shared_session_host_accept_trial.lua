-- Explicit host-only acceptance experiment, confined to our native Steam main-menu server.
return function(output)
 assert(os.getenv('AC8_COOP_RECON')=='1','Research profile required')
 assert(not _G.AC8NativeHostAcceptance,'Acceptance trial already installed')
 local function valid(o)return o and o:IsValid()end
 local function allowed()
  local pc=require('UEHelpers').GetPlayerController();if not valid(pc)then return false end
  local w=pc:GetWorld();if not valid(w)or not w:GetFullName():find('/Game/Maps/Menu/PL_MainMenu',1,true)then return false end
  local d=w.NetDriver
  return valid(w.AuthorityGameMode)and valid(d)and d:GetFullName():find('SteamNetDriver ',1,true)and not valid(d.ServerConnection)
 end
 assert(allowed(),'An existing native Steam listen host in the stock main menu is required')
 local dll='C:/Users/Administrator/Desktop/ACE/build/steam-legacy-host-r11b/ac8_steam_legacy_host_r11b.dll'
 local start=assert(package.loadlib(dll,'luaopen_ac8_legacy_host_start'))
 local pump=assert(package.loadlib(dll,'luaopen_ac8_legacy_host_tick'))
 local stop=assert(package.loadlib(dll,'luaopen_ac8_legacy_host_stop'))
 local f=assert(io.open(output..'/native-steam-host-enable.txt','w'));f:write('accept-known-peer-25201480');f:close()
 start()
 f=assert(io.open(output..'/native-steam-host-events.tsv','r'));local text=f:read(4097);f:close()
 assert(#text<=4096 and text:find('registered_known_peer',1,true),'Native host callback registration failed')
 local function tick()
  if not allowed()then stop();return end
  pump();ExecuteInGameThreadWithDelay(100,_G.AC8NativeHostAcceptance)
 end
 _G.AC8NativeHostAcceptance=tick;tick()
end
