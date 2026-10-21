-- r14 bounded ownership discovery. No spawn, AI switch, control or possession.
return function(output,stamp)
 local f=assert(io.open(output..'/guest-control-inspect-'..stamp..'.tsv','w'))
 local function row(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v):gsub('[\r\n\t]',' ')end;f:write(table.concat(t,'\t'),'\n')end
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local seen={};local objects_seen={};local budget=0
 local function schema(c)
  for depth=1,12 do
   if not valid(c)or seen[name(c)]then return end;seen[name(c)]=true
   local cn=name(c);if(cn:find('/Script/Engine.',1,true)or cn:find('/Script/CoreUObject.',1,true))and depth>1 then return end
   local n=0;c:ForEachProperty(function(p)
    n=n+1;if n>512 then return true end
    local pn=p:GetFName():ToString();local pt=p:GetClass():GetFName():ToString()
    if pt=='ObjectProperty'or pt=='ArrayProperty'or pt=='WeakObjectProperty'or pn:lower():find('input',1,true)then row('property',cn,pn,pt,p:GetOffset_Internal())end
   end)
   c:ForEachFunction(function(fn)
    local n=fn:GetFName():ToString();local low=n:lower()
    if low:find('plane',1,true)or low:find('object',1,true)or low:find('player',1,true)or low:find('possess',1,true)or low:find('spawn',1,true)or low:find('input',1,true)or low:find('ai',1,true)then
     row('function',cn,n,string.format('0x%x',fn:GetAddress()))
     fn:ForEachProperty(function(p)row('argument',cn,n,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal())end)
    end
   end);c=c:GetSuperStruct()
  end
 end
 local function object(o,query)
  if not valid(o)or objects_seen[o:GetAddress()]then return end;objects_seen[o:GetAddress()]=true;budget=budget+1;assert(budget<=32,'Object budget')
  row('object',query,name(o),string.format('0x%x',o:GetAddress()),name(o:GetWorld()));schema(o:GetClass())
  for _,k in ipairs({'ObjNameID','CallsignId','GameObjectId','GameObjectSubId','bIsActivated','bIsIGCActor','bIsAnimationPlane','bReplicates','bReplicateMovement'})do
   pcall(function()local v=o[k];if type(v)=='number'or type(v)=='boolean'then row('value',name(o),k,v)else row('value',name(o),k,v:ToString())end end)
  end
  for _,k in ipairs({'Controller','Pawn','AIStateComponent','AIWingmanStateComponent','WingmanSystemComponent','NetworkObject','Owner','RootUnit','ParentUnit','MissionConfig'})do
   pcall(function()local v=o[k];if valid(v)then row('reference',name(o),k,name(v),string.format('0x%x',v:GetAddress()))end end)
  end
  for _,k in ipairs({'RootAIGameObjects','ChildAIGameObjects','GroupLeadPlanes','AliveChildAIGameObjects','TotalChildAIGameObjects','PreAliveChildAIGameObjects','LoadedPlayerPawnAssets'})do
   local array_ok,array_error=pcall(function()local a=o[k];local n=a:GetArrayNum();assert(n<=16,'Array budget');for i=1,n do local v=a[i];if k~='LoadedPlayerPawnAssets'then v=v:Get()end;row('array',name(o),k,i,name(v),valid(v)and string.format('0x%x',v:GetAddress())or'0');if k~='LoadedPlayerPawnAssets'and valid(v)then object(v,'unit_child')end end end)
   if not array_ok then row('array_error',name(o),k,array_error)end
  end
 end
 local ok,err=pcall(function()
  for _,query in ipairs({'LivePlayerController','LivePlayerPlane','LiveAIWingmanPlane','LiveWingmanUnit','BP_WingmanUnit_C','BP_WOP1023_f14d_C','LiveAIPlane','LiveUnit','LiveGameMode'})do
   local all=FindAllOf(query)or{};row('query',query,#all);assert(#all<=512,'Query budget '..query)
   for _,o in ipairs(all)do
    local include=query~='LiveAIPlane'and query~='LiveUnit'
    if not include and valid(o)then
     if query=='LiveUnit'then include=name(o):find('WingmanUnit',1,true)~=nil
     else pcall(function()include=o.ObjNameID:ToString():find('Joker',1,true)~=nil end)end
    end
    if include then object(o,query)end
   end
  end
 end)
 row('summary',ok,err or'');f:close()
end
