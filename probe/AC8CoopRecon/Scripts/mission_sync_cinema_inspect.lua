-- Bounded, read-only schemas and values. No game mutation.
return function(output,id)
 local f=assert(io.open(output..'/cinema-inspect-'..id..'.tsv','w'))
 local function row(...)local a={...};for i,v in ipairs(a)do a[i]=tostring(v):gsub('[\r\n\t]',' '):sub(1,1024)end;f:write(table.concat(a,'\t'),'\n')end
 local function valid(o)return o and o:IsValid()end
 local function name(o)return valid(o)and o:GetFullName()or'invalid'end
 local seen={}
 local function schema(c)
  for depth=1,16 do
   if not valid(c)or seen[name(c)]then return end;seen[name(c)]=true
   row('class',name(c),'super',name(c:GetSuperStruct()))
   c:ForEachProperty(function(p)
    local t=p:GetClass():GetFName():ToString();local extra=''
    if t=='StructProperty'then pcall(function()extra=name(p:GetStruct());schema(p:GetStruct())end)end
    row('property',name(c),p:GetFName():ToString(),t,p:GetOffset_Internal(),extra)
   end)
   c:ForEachFunction(function(fn)
    row('function',fn:GetFullName(),fn:GetFunctionFlags())
    fn:ForEachProperty(function(p)local extra='';pcall(function()extra=name(p:GetStruct())end);row('argument',fn:GetFullName(),p:GetFName():ToString(),p:GetClass():GetFName():ToString(),extra)end)
   end)
   c=c:GetSuperStruct();if valid(c)and name(c):find('/Script/UMG.',1,true)then return end
  end
 end
 local ok,err=pcall(function()
  for _,path in ipairs({'/Script/LiveCinematics.ELiveCinematicsPlayableState','/Script/Live.ELiveSkipOperationType'})do
   local e=StaticFindObject(path);if valid(e)then e:ForEachName(function(n,v)row('enum',path,n:ToString(),v)end)end
  end
  for _,q in ipairs({'LiveCinematicsCinemaPlayer','LiveCinematicsSubsystem','LiveCinematicsWorldSubsystem','LiveCinematicsPlayableStateManager','LiveCinematicsLevelSequencePlayer','LiveCinematicsSkipPauseSubsystem','LiveSkipOperationManager','LiveSkipOperationPressHoldSkipStrategy','LiveCinematicsSkipWidget','LiveNUISettings','LiveUISettings'})do
   local cc=StaticFindObject('/Script/Live.'..q);if valid(cc)then schema(cc)end
   cc=StaticFindObject('/Script/LiveCinematics.'..q);if valid(cc)then schema(cc)end
   local all=FindAllOf(q)or{};row('query',q,#all);assert(#all<256,'Instance cap')
   for _,o in ipairs(all)do if valid(o)then
    row('object',name(o));schema(o:GetClass());local c=o:GetClass()
    for depth=1,10 do
     if not valid(c)then break end
     c:ForEachProperty(function(p)local n=p:GetFName():ToString();local t=p:GetClass():GetFName():ToString()
      pcall(function()
       local v=o[n]
       if t=='ObjectProperty'then row('reference',name(o),n,name(v))
       elseif t=='FloatProperty'or t=='BoolProperty'or t=='IntProperty'or t=='EnumProperty'then row('value',name(o),n,v)
       elseif t=='StructProperty'then p:GetStruct():ForEachProperty(function(pp)local nn=pp:GetFName():ToString();local vv=v[nn];if type(vv)=='number'or type(vv)=='boolean'then row('structvalue',name(o),n,nn,vv)end end)end
      end)
     end)
     c=c:GetSuperStruct();if valid(c)and name(c):find('/Script/UMG.',1,true)then break end
    end
   end end
  end
 end)
 row('summary',ok,err or'');f:close()
end
