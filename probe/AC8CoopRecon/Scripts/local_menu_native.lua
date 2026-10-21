local M={}
function M.new(output)
 local call=assert(package.loadlib(_G.AC8LocalMenuDll or assert(os.getenv('AC8_COOP_MENU_ROUTE_DLL')),'luaopen_ac8_menu_route'))
 local api={}
 function api.find(query)
  local result
  for _,o in ipairs(FindAllOf(query)or{})do if o:IsValid()and o.Visibility==0 then assert(not result,'Несколько активных '..query);result=o end end
  return result
 end
 function api.command(operation,kind,object)
  assert(object and object:IsValid(),'Исчез объект меню.')
  _G.AC8LocalMenuSequence=(_G.AC8LocalMenuSequence or 0)+1
  local stamp='hangar-'..os.time()..'-'.._G.AC8LocalMenuSequence
  local ticket='format\tac8-menu-route-v1\nstamp\t'..stamp..'\ncreated_unix\t'..os.time()..'\nobject\t'..string.format('0x%x',object:GetAddress())..'\noperation\t'..operation..'\nkind\t'..kind..'\n'
  local f=assert(io.open(output..'/menu-route-request.tsv','wb'));f:write(ticket);f:close();call()
  f=assert(io.open(output..'/menu-route-status.tsv','r'));local text=f:read(2049);f:close();assert(#text<=2048,'Слишком большой ответ меню.')
  local result={};for k,v in text:gmatch('([^\t\r\n]+)\t([^\r\n]*)')do assert(not result[k]);result[k]=v end
  assert(result.format=='ac8-menu-route-v1'and result.stamp==stamp,'Устаревший ответ меню.')
  if operation~='inspect'or result.status~='verified'then
   f=assert(io.open(output..'/'..stamp..'-'..kind..'.tsv','w'));f:write(ticket,'\n',text);f:close()
  end
  return result
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
