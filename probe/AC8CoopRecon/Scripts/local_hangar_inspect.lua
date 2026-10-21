-- Bounded reflected snapshots for the development adapter; never calls game transitions.
return function(output,stamp)
 local f=assert(io.open(output..'/hangar-inspect-'..stamp..'.tsv','w'))
 local function row(...)local t={...};for i,v in ipairs(t)do t[i]=tostring(v):gsub('[\r\n\t]',' ')end;f:write(table.concat(t,'\t'),'\n')end
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local seen={}
 local function schema(c)
  for _=1,10 do
   if not valid(c)or seen[name(c)]then return end;seen[name(c)]=true
   local cn=name(c);row('class',cn)
   c:ForEachProperty(function(p)row('property',cn,p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal())end)
   c:ForEachFunction(function(fn)
    row('function',cn,fn:GetFName():ToString())
    fn:ForEachProperty(function(p)row('argument',cn,fn:GetFName():ToString(),p:GetFName():ToString(),p:GetClass():GetFName():ToString(),p:GetOffset_Internal())end)
   end);c=c:GetSuperStruct()
  end
 end
 local ok,err=pcall(function()
  for _,path in ipairs({'/Script/Live.ELiveSelectPlaneIndex','/Script/Live.ELiveMenuHangarIDs','/Script/Live.ELiveDifficulty'})do
   local e=StaticFindObject(path);if valid(e)then e:ForEachName(function(n,v)row('enum',path,n:ToString(),v)end)end
  end
  for _,query in ipairs({'LiveMenuBase','LiveHangarManager','LiveHangarGameModeBase','LivePlayerController','LiveCampaignMissionConfig'})do
   local objects=FindAllOf(query)or{};assert(#objects<128,'Snapshot object budget')
   for _,o in ipairs(objects)do if valid(o)and(query~='LiveMenuBase'or o.Visibility==0)then
    row('instance',query,name(o),string.format('0x%x',o:GetAddress()));schema(o:GetClass())
    for _,key in ipairs({'CommandList','ScrollCommandList','HangarManager','GameInstance'})do
     pcall(function()local v=o[key];if valid(v)then row('reference',name(o),key,name(v),string.format('0x%x',v:GetAddress()));row('parent',key,name(v:GetParent()))end end)
    end
   end end
  end
 end)
 row('summary',ok,err or'');f:close()
end
