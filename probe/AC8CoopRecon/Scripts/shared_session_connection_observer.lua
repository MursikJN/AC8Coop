-- Observe an actual native connection. Never creates actors or advances game menus.
return function(output,role,options)
 assert(role=='host'or role=='guest','Invalid observer role')
 assert(not _G.AC8NativeConnectionObserver,'Observer already running')
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local events=0;local previous;local ticks=0;local seen_pending=false;local previous_steam
 options=options or{}
 local function emit(text)
  if events>=4096 then return end;events=events+1
  local f=assert(io.open(output..'/native-connection-events.tsv','a'));f:write(os.time(),'\t',text,'\n');f:close()
 end
 local function observe()
  ticks=ticks+1
  local ok,state=pcall(function()
   local pc=require('UEHelpers').GetPlayerController()
   if not valid(pc)then return 'phase\twaiting_controller' end
   local w=pc:GetWorld();if not valid(w)then return 'phase\twaiting_world'end
   local d=w.NetDriver;local gs=w.GameState
   local a={'format\tac8-native-connection-v1','role\t'..role,'world\t'..name(w),'driver\t'..name(d),'controller\t'..name(pc),'controller_connection\t'..name(pc.NetConnection),'pawn\t'..name(pc.Pawn),'game_mode\t'..name(w.AuthorityGameMode),'game_state\t'..name(gs)}
   local function field(k,v)a[#a+1]=k..'\t'..tostring(v):gsub('[\r\n\t]',' ')end
   local clients=0;local server=false
   if valid(d)then
    clients=d.ClientConnections:GetArrayNum();assert(clients>=0 and clients<=64,'Client count bound')
    server=valid(d.ServerConnection);field('server_connection',name(d.ServerConnection));field('client_count',clients)
    local cls=d.NetConnectionClassName;field('connection_class',type(cls)=='string'and cls or cls:ToString())
    for i=1,clients do local c=d.ClientConnections[i];field('client_'..i,name(c));if valid(c)then field('client_controller_'..i,name(c.PlayerController))end end
   end
   local players=0
   if valid(gs)then
    players=gs.PlayerArray:GetArrayNum();assert(players>=0 and players<=64,'Player count bound');field('player_count',players)
    for i=1,players do field('player_'..i,name(gs.PlayerArray[i]))end
   end
   local pending=FindAllOf('NetDriver')or{};field('all_driver_count',#pending)
   if #pending>0 then seen_pending=true end
   for i=1,math.min(#pending,8)do
    field('all_driver_'..i,name(pending[i]))
    if valid(pending[i])then field('all_driver_'..i..'_server_connection',name(pending[i].ServerConnection))end
   end
   local failed=_G.AC8NativeLastFailure
   local phase
   if role=='host'then phase=clients>0 and'host_has_native_client'or'host_waiting'
   elseif server then phase='guest_has_native_server'
   elseif failed or seen_pending and #pending==0 then phase='guest_connection_failed'
   else phase='guest_connecting'end
   field('phase',phase)
   if failed then field('failure_kind',failed.kind);field('failure_code',failed.code);field('failure_unix',failed.at)end
   if (role=='host'and clients>0 or role=='guest'and server)and players>=2 then field('two_players_observed',true)end
   return table.concat(a,'\n')..'\n'
  end)
  if not ok then state='phase\tobservation_error\nerror\t'..tostring(state):gsub('[\r\n\t]',' ')..'\n'end
  if options.steam_state then
   local good,why=pcall(options.steam_state)
   if not good then emit('steam_state_error\t'..tostring(why):gsub('[\r\n\t]',' '))else
    local sf=io.open(output..'/native-steam-state.tsv','r')
    if sf then local text=sf:read(4097);sf:close();assert(#text<=4096,'Steam state budget')
     text=text:gsub('observed_tick_ms\t%d+\n','')
     if text~=previous_steam then emit('steam_state\t'..text:gsub('\n',' | '));previous_steam=text end
    end
   end
  end
  local f=assert(io.open(output..'/native-connection-status.tsv','w'));f:write('observed_unix\t',os.time(),'\n',state);f:close()
  if state~=previous then emit('state\t'..state:gsub('\n',' | '));previous=state
  elseif ticks%10==0 then emit('heartbeat\t'..role)end
  if events<4096 then ExecuteInGameThreadWithDelay(1000,_G.AC8NativeConnectionObserver)else emit('observer_log_capacity')end
 end
 _G.AC8NativeConnectionObserver=observe;observe()
end
