-- Bounded crash breadcrumbs, closed on disk BEFORE a reflected/native stage.
-- Lua pcall cannot contain a native access violation. A pending entry survives
-- that failure and identifies the last stage in the automatic report.
local M={}
function M.new(output)
 local stack,serial={},0
 local function clean(v)return tostring(v):gsub('[\r\n\t]',' '):sub(1,160)end
 local function save(state,detail)
  serial=serial+1
  local f=assert(io.open(output..'/engine-call-current.tsv','wb'))
  assert(f:write('format\tac8-engine-call-v1\nsequence\t',serial,'\nstate\t',state,'\nunix\t',os.time(),'\npath\t',table.concat(stack,' > '),'\ndetail\t',clean(detail or''),'\n'))
  assert(f:close())
 end
 local function run(name,fn,...)
  assert(#stack<16,'Engine trace nesting limit')
  stack[#stack+1]=clean(name);save('entered')
  local values=table.pack(pcall(fn,...))
  save(values[1]and'returned'or'lua_error',values[1]and''or values[2])
  stack[#stack]=nil
  if not values[1]then error(values[2],0)end
  return table.unpack(values,2,values.n)
 end
 return {run=run}
end
return M
