-- Explicitly enabled offline diagnostic bridge. No OS keyboard/mouse input.
local M={}
function M.parse(text,now,last)
 assert(#text<=1024,'request_too_large')
 local r={}
 for line in text:gmatch('[^\r\n]+')do
  local k,v=line:match('^(%w+)\t([^\t]+)$');assert(k and not r[k],'invalid_request')
  assert(k=='id'or k=='operation'or k=='created','unknown_field');r[k]=v
 end
 local id=tonumber(r.id);local created=tonumber(r.created)
 assert(id and id%1==0 and id>last and id<=10000,'stale_id')
 assert(created and created<=now+2 and now-created<=30,'expired_request')
 assert(r.operation=='inspect_ui'or r.operation=='screenshot'or r.operation=='quit','operation_not_allowed')
 r.id=id;return r
end
function M.new(output)
 local last=0
 local function valid(o)return o and o:IsValid()end
 local function sig(path)
  local fn=StaticFindObject(path);assert(valid(fn),'function_absent:'..path)
  local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()end)
  return table.concat(fields,',')
 end
 local function controller()
  local found
  for _,o in pairs(FindAllOf('PlayerController')or{})do
   if valid(o)and not o:GetFullName():find('Default__',1,true)then assert(not found,'ambiguous_controller');found=o end
  end
  return assert(found,'no_controller')
 end
 return {tick=function()
  local f=io.open(output..'/automation-request.tsv','r');if not f then return end
  local text=f:read(1025);f:close()
  local readid=tonumber(text:match('id\t(%d+)'));if readid and readid<=last then return end
  local parsed,r=pcall(M.parse,text,os.time(),last)
  if not parsed then return end
  last=r.id -- consume before execution; never replay a side effect
  local result=assert(io.open(output..'/automation-'..r.id..'.tsv','w'))
  local function row(a,b,c)
   local function clean(x)return tostring(x or''):gsub('[\t\r\n]',' ')end
   result:write(clean(a),'\t',clean(b),'\t',clean(c),'\n');result:flush()
  end
  row('request',r.id,r.operation)
  local ok,err=pcall(function()
   assert(IsInGameThread(),'wrong_thread')
   if r.operation=='inspect_ui'then
    local started=os.clock()
    local function budget()assert(os.clock()-started<=0.25,'inspection_time_budget')end
    for _,q in ipairs({'PlayerController','LiveMenuBase','UserWidget'})do
     local n=0
     for _,o in pairs(FindAllOf(q)or{})do
      if valid(o)and not o:GetFullName():find('Default__',1,true)then
       n=n+1;if n>256 then row('cap',q,256);break end
       row('object',q,o:GetFullName())
       local c=o:GetClass()
       for depth=1,(q=='UserWidget'and 0 or 10)do
        budget()
        if not valid(c)then break end
        if c:GetFullName():find('Live',1,true)or c:GetFullName():find('/Game/',1,true)then
         c:ForEachFunction(function(fn)budget();row('function',fn:GetFullName(),sig(fn:GetFullName():gsub('^Function ','')))end)
         c:ForEachProperty(function(p)
          local pn=p:GetFName():ToString();local pt=p:GetClass():GetFName():ToString()
          row('property',c:GetFullName()..'.'..pn,pt)
         end)
        end
        c=c:GetSuperStruct()
       end
      end
     end
    end
   else
    local pc=controller();row('controller',pc:GetFullName())
    local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');assert(valid(lib),'library_absent')
    if r.operation=='screenshot'then
     local s=sig('/Script/Engine.KismetSystemLibrary:ExecuteConsoleCommand');row('signature','ExecuteConsoleCommand',s)
     assert(s=='WorldContextObject:ObjectProperty,Command:StrProperty,SpecificPlayer:ObjectProperty','console_signature_changed')
     -- Standard engine screenshot writes to the launcher's isolated Saved directory.
     lib:ExecuteConsoleCommand(pc,'Shot ShowUI',pc)
     row('issued','Shot ShowUI','image_file_not_yet_verified')
    else
     local s=sig('/Script/Engine.KismetSystemLibrary:QuitGame');row('signature','QuitGame',s)
     assert(s=='WorldContextObject:ObjectProperty,SpecificPlayer:ObjectProperty,QuitPreference:ByteProperty,bIgnorePlatformRestrictions:BoolProperty'or s=='WorldContextObject:ObjectProperty,SpecificPlayer:ObjectProperty,QuitPreference:EnumProperty,bIgnorePlatformRestrictions:BoolProperty','quit_signature_changed')
     row('issuing','QuitGame','normal_engine_exit');lib:QuitGame(pc,pc,0,false)
    end
   end
  end)
  row('result',ok and'returned'or'error',err);result:close()
 end}
end
return M
