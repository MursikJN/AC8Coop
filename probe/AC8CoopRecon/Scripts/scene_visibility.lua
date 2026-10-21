-- Local render-only scope using PlayerController.HiddenActors. Actor visibility,
-- AI, collision and all gameplay tick flags remain untouched.
local M={}
local function valid(o)return o and o:IsValid()end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
function M.new(pc,world)
 assert(valid(pc)and valid(world)and same(pc:GetWorld(),world),'Visibility controller/world mismatch')
 local s={pc=pc,world=world,owned={},active=true}
 function s.verify(controller,context)
  assert(s.active and same(pc,controller)and same(world,context)and same(pc:GetWorld(),world),'Visibility scope expired')
 end
 local function read()
  local array=pc.HiddenActors;assert(array:type()=='TArray'and array:GetArrayNum()<=4096,'Hidden actor array contract')
  local entries={};array:ForEach(function(_,entry)local o=entry:get();assert(o,'Invalid hidden actor entry');entries[#entries+1]=o end)
  return array,entries
 end
 local function write(array,entries)
  array:Empty();for i,o in ipairs(entries)do array[i]=o end
  assert(array:GetArrayNum()==#entries,'Hidden actor array write failed')
 end
 function s.set(objects)
  s.verify(pc,world);local array,current=read();local desired={};local count=0
  for _,o in pairs(objects)do assert(valid(o)and same(o:GetWorld(),world),'Hidden actor world changed');desired[o:GetAddress()]=o;count=count+1 end
  assert(count<=2048,'Visibility actor budget')
  local next_entries,present,next_owned={}, {}, {};local changed=false
  for _,o in ipairs(current)do local address=o:GetAddress()
   if s.owned[address]and not desired[address]then changed=true
   else next_entries[#next_entries+1]=o;present[address]=true;if s.owned[address]then next_owned[address]=true end end
  end
  for address,o in pairs(desired)do if not present[address]then next_entries[#next_entries+1]=o;next_owned[address]=true;changed=true end end
  if changed then
   local ok,err=pcall(write,array,next_entries)
   if not ok then local restored,why=pcall(write,array,current);assert(restored,'Visibility rollback failed: '..tostring(why));error(err)end
  end
  s.owned=next_owned
 end
 function s.stop()
  if not s.active then return end
  if valid(pc)and same(pc:GetWorld(),world)then s.set({})end
  s.active=false;s.owned={}
 end
 return s
end
return M
