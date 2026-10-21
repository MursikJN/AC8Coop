-- Read class defaults and replication annotations. Never modifies a class or actor.
return function(output,stamp)
 assert(os.getenv('AC8_COOP_RECON')=='1')
 local f=assert(io.open(output..'/native-replication-'..stamp..'.tsv','w'))
 local function row(...)local a={...};for i,v in ipairs(a)do a[i]=tostring(v):gsub('[\r\n\t]',' ')end;f:write(table.concat(a,'\t'),'\n')end
 local function valid(o)return o and o:IsValid()end
 local ok,err=pcall(function()
  for _,n in ipairs({'LiveGameObject','LivePlayerPlane','LiveAIPlane','LiveAIWingmanPlane','LiveUnit','LiveWingmanUnit','LivePlayerController','LiveGameMode','LiveOnlineGameMode','LiveOnlineGameModeBase','LiveNetworkPlayerPlane','LiveNetworkCoopGameMode','LiveNetworkUnit'})do
   local c=StaticFindObject('/Script/Live.'..n);local d=StaticFindObject('/Script/Live.Default__'..n)
   row('default',n,valid(c),valid(d))
   if valid(d)then
    for _,p in ipairs({'bReplicates','bReplicateMovement','bAlwaysRelevant','bOnlyRelevantToOwner','NetDormancy','Role','RemoteRole','PlayerControllerClass','PlayerStateClass','GameStateClass','DefaultPawnClass'})do
     local good,v=pcall(function()return d[p]end)
     if good then if type(v)=='userdata'then local a,b=pcall(function()return v:IsValid()and v:GetFullName()or'invalid'end);v=a and b or'non-object userdata'end;row('default_field',n,p,v)end
    end
   end
   local total=0
   for _=1,16 do if not valid(c)then break end
    c:ForEachProperty(function(p)
     total=total+1;assert(total<=2048,'Property bound')
     local good,flags=pcall(function()return p:GetPropertyFlags()end)
     if good then row('property_flags',n,c:GetFullName(),p:GetFName():ToString(),flags)end
    end)
    c=c:GetSuperStruct()
   end
  end
 end)
 row('summary',ok,err or'');f:close()
end
