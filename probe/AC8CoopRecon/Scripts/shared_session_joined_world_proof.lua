-- Read-only identity checks after the guest has completed native world login.
return function(output,stamp)
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local f=assert(io.open(output..'/native-joined-world-'..stamp..'.tsv','w'))
 local function row(...)local a={...};for i,v in ipairs(a)do a[i]=tostring(v):gsub('[\r\n\t]',' ')end;f:write(table.concat(a,'\t'),'\n');f:flush()end
 local ok,err=pcall(function()
  local pc=require('UEHelpers').GetPlayerController();assert(valid(pc),'Local controller absent')
  local w=pc:GetWorld();assert(valid(w),'World absent')
  local d=w.NetDriver;assert(valid(d)and not valid(d.ServerConnection),'Native server required')
  local gs=w.GameState;assert(valid(gs),'GameState absent')
  local clients=d.ClientConnections:GetArrayNum();local players=gs.PlayerArray:GetArrayNum()
  assert(clients>0 and clients<=8 and players>=2 and players<=16,'Expected joined world')
  row('world',name(w),string.format('0x%x',w:GetAddress()));row('client_count',clients);row('player_count',players)
  for i=1,clients do
   local c=d.ClientConnections[i];assert(valid(c),'Invalid native connection')
   local remote=c.PlayerController;assert(valid(remote)and remote:GetAddress()~=pc:GetAddress(),'Distinct remote controller absent')
   local remote_world=remote:GetWorld();assert(valid(remote_world)and remote_world:GetAddress()==w:GetAddress(),'Remote controller belongs to another world')
   assert(valid(remote.NetConnection)and remote.NetConnection:GetAddress()==c:GetAddress(),'Connection/controller identity mismatch')
   local ps=remote.PlayerState;assert(valid(ps),'Remote player state absent');local found=false
   for j=1,players do if gs.PlayerArray[j]:GetAddress()==ps:GetAddress()then found=true end end
   assert(found,'Remote player is missing from shared GameState')
   row('remote_identity_verified',i,name(c),name(remote),name(ps));row('remote_pawn',name(remote.Pawn))
   local good,nickname=pcall(function()local text=ps:GetPlayerName();return type(text)=='string'and text or text:ToString()end)
   row('remote_player_name',good,nickname)
  end
 end)
 row('summary',ok,err or'');f:close()
end
