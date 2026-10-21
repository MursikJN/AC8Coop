-- Observe stock failure events without overriding their arguments or return values.
return function(output)
 assert(not _G.AC8NativeErrorHooks,'Error observer already installed')
 local specs={
  {'HandleNetworkError','FailureType:ByteProperty:0,bIsServer:BoolProperty:1','network'},
  {'HandleTravelError','FailureType:ByteProperty:0','travel'},
 }
 local hooks={};_G.AC8NativeErrorHooks=hooks
 for _,spec in ipairs(specs)do
  local path='/Script/Engine.GameInstance:'..spec[1]
  local fn=StaticFindObject(path);assert(fn and fn:IsValid(),'Failure event missing')
  local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()..':'..p:GetOffset_Internal()end)
  assert(table.concat(fields,',')==spec[2],'Failure event signature changed')
  local callback=function(context,code,server)
   local ok,err=pcall(function()
    local value=code:get();local owner=context:get()
    local event={kind=spec[3],code=value,at=os.time()};_G.AC8NativeLastFailure=event
    local f=assert(io.open(output..'/native-failures.tsv','a'))
    f:write(event.at,'\t',event.kind,'\t',tostring(value),'\t',server and tostring(server:get())or'','\t',owner:IsValid()and owner:GetFullName()or'invalid','\n');f:close()
   end)
   if not ok then print('[AC8NativeFailure] '..tostring(err)..'\n')end
  end
  local before,after=RegisterHook(path,callback)
  hooks[#hooks+1]={path=path,before=before,after=after,callback=callback}
 end
end
