-- Read-only reflection collector. Never invokes game UFunctions or reads guessed offsets.
local M = {}
M.queries = {'LiveEventSubsystem','LiveEventContainer','LiveEventPackage','LiveEventData',
 'LiveIndexSavedDataTable','LiveAIActionEventComponent','LiveRandomEventSubsystem',
 'LiveCampaignMissionConfig','LiveMissionRoomMemberManager','LiveAircraftSelector',
 'LiveAIWingmanPlane','LiveAIWingmanUnit','LiveHangarManager','GameModeBase','LiveGameState',
 'LiveCinematicsCinemaPlayer','LiveCinematicsPlayableStateManager','LiveCinematicsWorldSubsystem',
 'LiveStreamingLoader','LevelStreaming','DataTable'}
local scalars={BoolProperty=true,ByteProperty=true,EnumProperty=true,IntProperty=true,
 Int8Property=true,Int16Property=true,Int64Property=true,UInt16Property=true,
 UInt32Property=true,UInt64Property=true,FloatProperty=true,DoubleProperty=true}
local strings={NameProperty=true,StrProperty=true,TextProperty=true}
local refs={ObjectProperty=true,ClassProperty=true}
local function valid(o)
 local ok,v=pcall(function()return o and o:IsValid()end);return ok and v
end
local function name(o)
 if not valid(o)then return '<invalid>'end
 local ok,v=pcall(function()return o:GetFullName()end);return ok and v or '<unavailable>'
end
local function kind(v)
 local ok,t=pcall(function()return v:type()end);return ok and t or type(v)
end
local function text(v)
 if type(v)=='string'then return v end
 return v:ToString()
end
local function address(o)
 local ok,v=pcall(function()return string.format('0x%x',o:GetAddress())end)
 return ok and v or '<unavailable>'
end
local function is_instance(o)
 local n=name(o)
 return valid(o)and not n:find('Default__',1,true)and not n:match('^Class ')
end
local function related(o)
 local n=name(o)
 return n:find('Live',1,true)or n:find('Mission007',1,true)or n:find('Wingman',1,true)
end
M.name=name

-- A discovery pass returns immutable names only. Resolve again on the next tick.
function M.discover(find,query)
 local result={};local scanned=0
 for _,o in pairs(find(query)or{})do
  scanned=scanned+1;assert(scanned<=4096,'discovery_scan_budget')
  local n=name(o)
  if is_instance(o)and(query~='DataTable'or n:find('Mission007',1,true)or n:find('AIAction',1,true)or n:find('RandomEvent',1,true))then
   result[#result+1]=n
  end
 end
 table.sort(result);return result
end

-- Only strings cross ticks: no UObject, property, row or container wrappers are retained.
function M.context(find)
 local out={}
 for _,q in ipairs({'World','GameModeBase','LiveCinematicsCinemaPlayer'})do
  local ok,list=pcall(find,q)
  if ok and list then
   local count=0
   for _,o in pairs(list)do
    count=count+1;if count>64 then out[#out+1]=q..':capped';break end
    if is_instance(o)then
     local id=q..'|'..name(o)..'|'..address(o);out[#out+1]=id
     -- Capture only reflected state fields, never guess a member or invoke getters.
     if q~='World'then pcall(function()
      local c=o:GetClass()
      for depth=1,12 do
       if not valid(c)then break end
       local fields=0;c:ForEachProperty(function(p)
        fields=fields+1;if fields>256 then return true end
        local n=p:GetFName():ToString();local t=p:GetClass():GetFName():ToString()
        if n:find('State',1,true)or n:find('Phase',1,true)or n:find('Mission',1,true)then
         if scalars[t]then out[#out+1]=id..'.'..n..'='..tostring(o[n])
         elseif strings[t]then out[#out+1]=id..'.'..n..'='..text(o[n])
         elseif refs[t]then out[#out+1]=id..'.'..n..'='..name(o[n])end
        end
       end);c=c:GetSuperStruct()
      end
     end)end
    end
   end
  else out[#out+1]=q..':query_error' end
 end
 table.sort(out);return table.concat(out,';')
end

function M.capture(api,reason,limits,selection)
 local L=limits or {objects=256,entries=2048,rows=30000,depth=5,seconds=0.25}
 local lines,issues,objects=0,0,0
 local seen={};local queue={};local cursor=1
 local initial=M.context(api.find)
 local start=api.clock()
 local function row(a,b,c,d,e)
  if lines>=L.rows then error('row_budget')end
  lines=lines+1
  local v={a,b,c,d,e};for i=1,5 do if v[i]==nil then v[i]=''end end
  api.emit(v[1],v[2],v[3],v[4],v[5])
 end
 local function gap(path,why,detail)
  issues=issues+1;row('gap',path,why,detail or'','')
 end
 local function budget()
  if api.clock()-start>L.seconds then error('time_budget')end
 end
 local function enqueue(o,depth)
  if selection and depth>0 then return end -- references are recorded, never recursively chased in a slice
  if not is_instance(o)then return end
  local id=name(o)..'|'..address(o)
  if seen[id]then return end
  if #queue>=L.objects then gap(id,'object_budget');return end
  if depth>L.depth then gap(id,'reference_depth_budget');return end
  seen[id]=true;queue[#queue+1]={o=o,depth=depth}
 end
 local properties,value
 local function attempt(path,fn)
  local ok,err=pcall(fn);if not ok then
   if tostring(err):find('_budget',1,true)then error(err)end
   gap(path,'read_error',err)
  end
 end
 value=function(v,path,depth,p)
  budget()
  if depth>L.depth then gap(path,'value_depth_budget');return end
  local k=type(v)
  if k=='number'or k=='boolean'or k=='string'or v==nil then
   row('value',path,k,tostring(v));return
  end
  local t=kind(v)
  if t=='FName'or t=='FString'or t=='FText'then row('value',path,t,text(v))
  elseif t=='TArray'then
   local n=v:GetArrayNum();assert(n>=0 and n%1==0,'invalid_array_count')
   row('array',path,'count',n)
   for i=1,math.min(n,L.entries)do value(v[i],path..'['..(i-1)..']',depth+1)end
   if n>L.entries then gap(path,'array_capped',n)end
  elseif t=='TMap'then
   local n=0;local count=#v;row('map',path,'count',count)
   if count>L.entries then gap(path,'map_over_budget',count);return end
   v:ForEach(function(key,item)
    n=n+1;if n>L.entries then gap(path,'map_capped',n);return true end
    -- TMap ForEach uses GetParam wrappers, unlike TArray indexed access.
    value(key:get(),path..'{entry'..n..'}.key',depth+1)
    value(item:get(),path..'{entry'..n..'}.value',depth+1)
   end)
  elseif t=='UScriptStruct'then
   properties(v,v,path,depth+1)
  elseif t=='FWeakObjectPtr'then
   local o=v:Get();row('reference',path,'weak',name(o),address(o))
   if related(o)then enqueue(o,depth+1)end
  elseif valid(v)and (t=='UObject'or t=='UClass'or t=='UDataTable'or t=='AActor'or t=='UWorld')then
   row('reference',path,t,name(v),address(v))
   if t~='UClass'and related(v)then enqueue(v,depth+1)end
  else gap(path,'unsupported_wrapper',t)end
 end
 properties=function(o,meta,path,depth)
  if depth>L.depth then gap(path,'struct_depth_budget');return end
  local visited={}
  for generation=1,16 do
   if not valid(meta)then return end
   local mn=name(meta);if visited[mn]then return end;visited[mn]=true
   local n=0
   meta:ForEachProperty(function(p)
    budget();n=n+1;if n>256 then gap(path,'property_capped');return true end
    local field=p:GetFName():ToString();local t=p:GetClass():GetFName():ToString()
    local fp=path..'.'..field
    row('property',fp,t,p:GetOffset_Internal(),mn)
    -- Do not even resolve delegates, soft references or unsupported property kinds.
    if scalars[t]or strings[t]or refs[t]or t=='ArrayProperty'or t=='MapProperty'or t=='StructProperty'or t=='WeakObjectProperty'then
     attempt(fp,function()
      local v=o[field]
      if strings[t]then row('value',fp,t,text(v))
      elseif scalars[t]then
       assert(type(v)=='number'or type(v)=='boolean','non_scalar_wrapper');row('value',fp,t,v)
      elseif refs[t]then
       row('reference',fp,t,name(v),address(v));if t~='ClassProperty'and related(v)then enqueue(v,depth+1)end
      else value(v,fp,depth,p)end
     end)
    else gap(fp,'unsupported_property',t)end
   end)
   meta=meta:GetSuperStruct()
  end
  gap(path,'inheritance_capped')
 end
 local ok,err=pcall(function()
  row('capture',reason,'context',initial)
  if selection then row('scope',selection.query,'single_root',selection.name,'references_not_traversed')end
  for _,q in ipairs(selection and {selection.query}or M.queries)do
   budget()
   local found,list=pcall(api.find,q)
   if not found then gap(q,'query_error',list)
   else
    local count=0
    for _,o in pairs(list or{})do
     count=count+1
     if selection then
      if name(o)==selection.name then enqueue(o,0)end
     elseif q~='DataTable'or name(o):find('Mission007',1,true)or name(o):find('AIAction',1,true)or name(o):find('RandomEvent',1,true)then enqueue(o,0)end
     if count>=4096 then gap(q,'query_scan_capped',count);break end
    end
    row('query',q,'instances',count)
   end
  end
  if selection and #queue==0 then gap(selection.name,'root_no_longer_present')end
  while cursor<=#queue do
   budget();local entry=queue[cursor];cursor=cursor+1
   local o=entry.o;local path=name(o)
   if not is_instance(o)then gap(path,'invalidated')
   else
    objects=objects+1;row('object',path,'address',address(o),name(o:GetClass()))
    attempt(path,function()properties(o,o:GetClass(),path,entry.depth)end)
    if kind(o)=='UDataTable'then
     attempt(path..'.rows',function()
      -- API exists in inspected UE4SS source. Older binaries report a gap.
      assert(type(o.ForEachRow)=='function','datatable_api_unavailable')
      local n=0;row('table',path,'row_struct',name(o:GetRowStruct()))
      o:ForEachRow(function(key,data)
       n=n+1;if n>L.entries then gap(path,'table_rows_capped');return true end
       row('table_row',path,'key',key)
       properties(data,data,path..'.rows['..key..']',entry.depth+1)
      end)
      row('table',path,'rows_visited',math.min(n,L.entries))
     end)
    elseif o:IsA('/Script/Engine.DataTable')then gap(path,'datatable_wrapper_unavailable',kind(o))end
   end
  end
 end)
 local final=M.context(api.find)
 if initial~=final then issues=issues+1 end
 -- Footer bypasses the row budget so a truncated export cannot look complete.
 api.emit('summary',reason,ok and 'traversal_finished'or 'aborted',tostring(err or''),
  'objects='..objects..';rows='..lines..';gaps='..issues..';context_changed='..tostring(initial~=final)..';native_private_fields=not_captured')
 return {ok=ok,gaps=issues,objects=objects,context_changed=initial~=final}
end
return M
