-- Read-only native world/server observations; does not create or join a session.
return function(output,stamp)
 assert(os.getenv('AC8_COOP_RECON')=='1','Research profile required')
 local f=assert(io.open(output..'/native-server-status-'..stamp..'.tsv','w'))
 local function row(...)local a={...};for i,v in ipairs(a)do a[i]=tostring(v):gsub('[\r\n\t]',' ')end;f:write(table.concat(a,'\t'),'\n');f:flush()end
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local ok,err=pcall(function()
  local pc=require('UEHelpers').GetPlayerController();assert(valid(pc),'Controller absent')
  local w=pc:GetWorld();assert(valid(w),'World absent');row('world',name(w))
  local k=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');assert(valid(k),'Kismet CDO absent')
  for _,n in ipairs({'IsServer','IsStandalone','IsDedicatedServer'})do
   local fn=StaticFindObject('/Script/Engine.KismetSystemLibrary:'..n);assert(valid(fn),'Missing '..n)
   local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()..':'..p:GetOffset_Internal()end)
   assert(table.concat(fields,',')=='WorldContextObject:ObjectProperty:0,ReturnValue:BoolProperty:8','Unexpected signature '..n)
   row(n,k[n](k,w))
  end
  local d=w.NetDriver;row('driver',name(d))
  if valid(d)then
   row('server_connection',name(d.ServerConnection));row('client_count',d.ClientConnections:GetArrayNum())
   for _,n in ipairs({'bIsPassthrough','bIsUsingP2PSockets'})do local good,v=pcall(function()return d[n]end);row('driver_field',n,good,v)end
  end
  row('game_mode',name(w.AuthorityGameMode));row('game_state',name(w.GameState))
  if valid(w.GameState)then row('player_count',w.GameState.PlayerArray:GetArrayNum())end
  row('controller',name(pc));row('player_state',name(pc.PlayerState));row('pawn',name(pc.Pawn))
 end)
 row('summary',ok,err or'');f:close()
end
