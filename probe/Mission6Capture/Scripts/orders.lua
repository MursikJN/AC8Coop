-- Build25201480 only. Read-only scalar views; no hooks or gameplay/native calls.
-- Evidence and exact readers: docs/research/baxter-orders-20261023.md.
local M={}
M.fields={
 {'LiveWingmanManager','Mode','ByteProperty',0xba},
 {'LiveWingmanManager','RepeatFlag','ByteProperty',0xc5},
 {'LiveWingmanManager','RepeatCount','IntProperty',0xc8},
 {'LiveAIWingmanSystemComponent','Mode','ByteProperty',0x120},
 {'LiveAIWingmanStateComponent','State','ByteProperty',0x2e4},
 {'LiveWingmanJoinOrLeaveExecution','Target','NameProperty',0x58},
 {'LiveWingmanJoinOrLeaveExecution','Leave','ByteProperty',0x60},
 {'LiveWingmanOrderExecution','Order','ByteProperty',0x58},
 -- B6-P readers:14740ed30/1473ff0d0,147ebc140/147ec4730; build pinned.
 {'LiveSetIsInvincibleFromWingman','ObjectName','NameProperty',0x58},
 {'LiveSetIsInvincibleFromWingman','UnitName','NameProperty',0x60},
 {'LiveSetIsInvincibleFromWingman','GroupName','NameProperty',0x68},
 {'LiveSetIsInvincibleFromWingman','RequestedFlag','ByteProperty',0x70},
 {'LiveInputWingmanStateStatement','ExpectedInput','StrProperty',0x68},
 {'LiveAIWingmanPlane','InvincibleFromWingmanRaw','ByteProperty',0x3fb},
}
local function valid(o)return o and o:IsValid()end
local function instance(o)
 if not valid(o)then return false end
 local n=o:GetFullName()
 return not n:find('Default__',1,true)and not n:find('Archetype',1,true)
end
function M.new(api)
 local registered=false
 return {sample=function(context,emit)
  assert(api.is_game_thread(),'orders_wrong_thread')
  if not context:find('/Mission007/PL_Mission007',1,true)then return end
  if not registered then
   for _,f in ipairs(M.fields)do
    api.register({Name='AC8Observe_'..f[1]..'_'..f[2],BelongsToClass='/Script/Live.'..f[1],Type=api.types[f[3]],OffsetInternal=f[4]})
   end
   registered=true
  end
  local rows={};local count=0
  local queries={};for _,f in ipairs(M.fields)do queries[f[1]]=true end
  for q in pairs(queries)do
   local found=api.find(q)or{};local seen=0
   for _,o in pairs(found)do
    seen=seen+1;assert(seen<=64,'orders_object_budget')
    if instance(o)and o:IsA('/Script/Live.'..q)then
     local name=o:GetFullName();local include=false
     if q=='LiveWingmanManager'then
      local w=o:GetWorld();include=valid(w)and w:GetFullName():find('/Mission007/PL_Mission007',1,true)~=nil
     else include=name:find('/Mission007/PL_Mission007',1,true)~=nil end
     if include then
      local address=o:GetAddress()
      for _,f in ipairs(M.fields)do if f[1]==q then
       local value=o['AC8Observe_'..q..'_'..f[2]]
       if f[3]=='NameProperty'or f[3]=='StrProperty'then
        if type(value)~='string'then value=value:ToString()end
        assert(type(value)=='string'and #value<=512,'orders_string_budget')
       else
        assert(type(value)=='number'and value==math.floor(value),'orders_scalar_type')
        if f[3]=='ByteProperty'then assert(value>=0 and value<=255,'orders_byte_range')end
       end
       count=count+1;assert(count<=192,'orders_row_budget')
       rows[#rows+1]={name,string.format('0x%X',address),f[2],value,string.format('0x%X',f[4])}
      end end
      assert(valid(o)and o:GetAddress()==address and o:GetFullName()==name,'orders_identity_changed')
     end
    end
   end
  end
  -- No partial accepted sample if any identity/type/budget check failed.
  for _,r in ipairs(rows)do emit(table.unpack(r))end
  emit('sample','complete','rows',count,'game_thread;not_execution_trace')
 end}
end
return M
