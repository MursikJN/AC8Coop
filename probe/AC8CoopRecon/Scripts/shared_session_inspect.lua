-- Read-only host-session capability survey. No travel, session creation or object writes.
return function(output,stamp)
 local f=assert(io.open(output..'/shared-session-'..stamp..'.tsv','w'))
 local function row(...)local a={...};for i,v in ipairs(a)do a[i]=tostring(v):gsub('[\r\n\t]',' '):sub(1,2048)end;f:write(table.concat(a,'\t'),'\n')end
 local function valid(o)return o and o:IsValid()end
 local function label(o)return valid(o)and o:GetFullName()or'invalid'end
 local function address(o)return valid(o)and string.format('0x%x',o:GetAddress())or'0'end
 local seen={};local total=0
 local function schema(c)
  for _=1,16 do
   if not valid(c)or seen[label(c)]then return end
   total=total+1;assert(total<=256,'class survey bound')
   local owner=label(c);seen[owner]=true;row('class',owner,address(c),label(c:GetSuperStruct()))
   local n=0;c:ForEachProperty(function(p)n=n+1;if n>512 then return true end
    row('property',owner,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal())
   end)
   n=0;c:ForEachFunction(function(fn)n=n+1;if n>512 then return true end
    local name=fn:GetFName():ToString();row('function',owner,name,fn:GetFunctionFlags(),address(fn))
    local a=0;fn:ForEachProperty(function(p)a=a+1;if a>48 then return true end
     row('argument',owner,name,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal())
    end)
   end)
   c=c:GetSuperStruct()
  end
 end
 local ok,err=pcall(function()
  for _,pair in ipairs({
   {'Engine','World'},{'Engine','Engine'},{'Engine','NetDriverDefinition'},
   {'OnlineSubsystemUtils','IpNetDriver'},{'OnlineSubsystemSteam','SteamNetDriver'},
   {'StrixSDK','StrixNetworkFacade'},{'StrixSDK','StrixBlueprintFunctionLibrary'},
   {'StrixSDK','StrixSettings'},{'StrixSDK','StrixReplicatorComponent'},
   {'StrixSDK','StrixRoom'},{'StrixSDK','StrixRoomMember'},{'Engine','GameInstance'},{'Engine','GameModeBase'},
   {'Engine','GameStateBase'},{'Engine','PlayerState'},{'Engine','PlayerController'},
   {'Engine','NetDriver'},{'Engine','IpNetDriver'},{'Engine','GameSession'},
   {'Engine','GameplayStatics'},{'Engine','KismetSystemLibrary'},
   {'Live','LiveGameInstance'},{'Live','LiveGameMode'},{'Live','LiveOnlineGameModeBase'},{'Live','LiveOnlineGameMode'},
   {'Live','LiveTeamDeathMatchGameMode'},{'Live','LiveNetworkManager'},{'Live','LiveNetworkP2P'},
   {'Live','LiveNetworkGameMode'},{'Live','LiveNetworkCoopGameMode'},{'Live','LiveNetworkCompetitiveCoopGameMode'},
   {'Live','LiveNetworkAircraftSelector'},{'Live','LiveNetworkPlayerPlane'},{'Live','LiveNetworkUnit'},
   {'Live','LivePlayerController'},{'Live','LivePlayerPlane'},{'Live','LiveAIWingmanPlane'},
   {'Live','LiveWingmanUnit'},{'Live','LiveUnit'},{'Live','LiveGameObject'},{'Live','LiveHUD'},
   {'Live','LiveHangarManager'},{'Live','LiveBlueprintLibrary'},{'Live','LiveNetworkDebugCommand'}
  })do
   local path='/Script/'..pair[1]..'.'..pair[2];local c=StaticFindObject(path)
   row('lookup',path,valid(c));if valid(c)then schema(c)end
  end
  for _,query in ipairs({'LiveGameEngine','StrixNetworkFacade','LiveGameInstance','LiveNetworkManager','LiveNetworkP2P','NetDriver','GameSession','LivePlayerController','LiveOnlineGameMode','LiveGameMode','LiveHUD'})do
   local objects=FindAllOf(query)or{};row('query',query,#objects)
   for i,o in ipairs(objects)do if i>8 then break end;if valid(o)then
    row('instance',query,label(o),address(o));schema(o:GetClass())
    if query=='LiveGameEngine'then pcall(function()
     local list=o.NetDriverDefinitions;local n=list:GetArrayNum();row('driver_count',label(o),n);assert(n<=16,'driver count')
     for i=1,n do local v=list[i];row('driver',i,v.DefName:ToString(),v.DriverClassName:ToString(),v.DriverClassNameFallback:ToString())end
    end)end
    if query=='LivePlayerController'then pcall(function()local w=o:GetWorld();row('world',label(w),address(w));schema(w:GetClass());row('world_net_driver',label(w.NetDriver),address(w.NetDriver));row('world_mode',label(w.AuthorityGameMode),address(w.AuthorityGameMode));if valid(w.AuthorityGameMode)then schema(w.AuthorityGameMode:GetClass())end end)end
    local c=o:GetClass();local read={}
    for _=1,16 do if not valid(c)then break end
     c:ForEachProperty(function(p)
      local n=p:GetFName():ToString();local t=p:GetClass():GetFName():ToString()
      if read[n]then return end;read[n]=true
      if t=='ObjectProperty'then pcall(function()local v=o[n];row('reference',label(o),n,label(v),address(v));if valid(v)then schema(v:GetClass())end end)
      elseif t=='IntProperty'or t=='BoolProperty'or t=='ByteProperty'or t=='EnumProperty'then pcall(function()row('value',label(o),n,o[n])end)end
     end);c=c:GetSuperStruct()
    end
   end end
  end
 end)
 row('summary',ok,err or'');f:close()
end
