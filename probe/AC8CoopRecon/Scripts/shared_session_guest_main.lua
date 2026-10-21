-- Native guest diagnostic entrypoint: wait for normal profile loading, then connect once.
assert(os.getenv('AC8_COOP_RECON')=='1')
local output=assert(os.getenv('AC8_COOP_RECON_OUTPUT'))
local task=assert(os.getenv('AC8_COOP_RECON_EXTENSION'))
local directory=assert(task:match('^(.*)[/\\][^/\\]+$'))
local seen=false;local attempted=false
local function tick()
 if attempted then return end
 if seen then
  for _,o in ipairs(FindAllOf('LiveMenuMainTopWidget')or{})do
   if o:IsValid()and o.Visibility==0 then
    attempted=true
    local ok,err=pcall(function()
     assert(loadfile(directory..'/shared_session_error_observer.lua'))()(output)
     local peer=assert(os.getenv('AC8_NATIVE_HOST_STEAM_ID'));assert(#peer==17 and peer:match('^7656119%d+$'),'Invalid SteamID')
     local f=assert(io.open(output..'/native-steam-peer.txt','w'));f:write(peer);f:close()
     local read_state=assert(package.loadlib(directory..'/../../../ac8_steam_legacy_state_r11b.dll','luaopen_ac8_legacy_state'))
     assert(loadfile(directory..'/shared_session_connection_observer.lua'))()(output,'guest',{steam_state=read_state})
     assert(loadfile(task))()(output,os.date('%Y%m%d-%H%M%S'))
    end)
    print('[AC8NativeGuest] native connection requested '..tostring(ok)..' '..tostring(err)..'\n')
    local f=assert(io.open(output..'/native-guest-result.txt','w'));f:write(tostring(ok),'\n',tostring(err));f:close()
    return
   end
  end
 end
 ExecuteInGameThreadWithDelay(1000,_G.AC8NativeGuestMain)
end
_G.AC8NativeGuestMain=tick
_G.AC8NativeGuestMainCreated=function()seen=true end
NotifyOnNewObject('/Script/Live.LiveMenuMainTopWidget',_G.AC8NativeGuestMainCreated)
ExecuteInGameThreadWithDelay(1000,tick)
