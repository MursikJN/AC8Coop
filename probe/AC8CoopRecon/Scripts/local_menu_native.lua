local M={}
function M.new(output)
 local call=assert(package.loadlib(_G.AC8LocalMenuDll or assert(os.getenv('AC8_COOP_MENU_ROUTE_DLL')),'luaopen_ac8_menu_route'))
 local api={}
 function api.find(query)
  local result
  for _,o in ipairs(FindAllOf(query)or{})do if o:IsValid()and o.Visibility==0 then assert(not result,'Несколько активных '..query);result=o end end
  return result
 end
 local function command(operation,kind,object)
  assert(operation=='bootstrap'or(object and object:IsValid()),'Исчез объект меню.')
  _G.AC8LocalMenuSequence=(_G.AC8LocalMenuSequence or 0)+1
  local stamp='hangar-'..os.time()..'-'.._G.AC8LocalMenuSequence
  local ticket='format\tac8-menu-route-v1\nstamp\t'..stamp..'\ncreated_unix\t'..os.time()..'\nobject\t'..string.format('0x%x',object and object:GetAddress()or 0)..'\noperation\t'..operation..'\nkind\t'..kind..'\n'
  os.remove(output..'/menu-route-status.tsv')
  local f=assert(io.open(output..'/menu-route-request.tsv','wb'));assert(f:write(ticket));assert(f:close());call()
  local why;f,why=io.open(output..'/menu-route-status.tsv','r');assert(f,'menu_native_response_missing: '..tostring(why))
  local text=f:read(2049);f:close();assert(text and #text<=2048,'Слишком большой ответ меню.')
  local result={};for line in text:gmatch('[^\r\n]+')do local k,v=line:match('^([^\t]+)\t([^\t]*)$');assert(k and result[k]==nil,'Некорректный ответ меню.');result[k]=v end
  assert(result.format=='ac8-menu-route-v1'and result.stamp==stamp,'Устаревший ответ меню.')
  if operation~='inspect'or result.status~='verified'then
   f=assert(io.open(output..'/'..stamp..'-'..kind..'.tsv','w'));f:write(ticket,'\n',text);f:close()
  end
  assert(not(result.status=='refused'and(result.reason or''):match('^bootstrap_')),'menu_native_'..tostring(result.reason))
  return result
 end
 function api.command(operation,kind,object)
  assert(not api.error,api.error)
  local ok,result=xpcall(function()return command(operation,kind,object)end,debug.traceback)
  if not ok then api.error=tostring(result);error(api.error,0)end
  return result
 end
 function api.bootstrap()
  local result=api.command('bootstrap','bootstrap');assert(result.status=='verified'and result.reason=='bootstrap_ready','menu_native_bootstrap_refused');return result
 end
 function api.step(kind,query)
  local o=api.find(query);if not o then return false end
  local r=api.command('inspect',kind,o)
  if r.reason=='widget_or_selection_contract'then return false end
  assert(r.status=='verified',kind..': '..tostring(r.reason))
  if r.reason=='target_available'then
   local changed=api.command('select',kind,o);assert(changed.status=='selected',kind..': '..tostring(changed.reason))
   r=api.command('inspect',kind,o)
  end
  assert(r.status=='verified'and r.reason=='target_selected','Пункт не выбран: '..kind)
  r=api.command('confirm',kind,o)
  assert(r.status=='returned'and r.returned=='1',kind..': '..tostring(r.reason))
  return true
 end
 return api
end
return M
