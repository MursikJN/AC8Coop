local M={}
function M.new(output,source)
 local call=assert(package.loadlib(source..'/../../../ac8_cinema_guard_r26_3.dll','luaopen_ac8_cinema_guard'))
 local g={}
 function g.poll(object,scene,voting,authorize,operation)
  assert(object and object:IsValid(),'Исчез обработчик пропуска.')
  local address=string.format('0x%x',object:GetAddress())
  local f=assert(io.open(output..'/cinema-guard-request.tsv','w'))
  f:write('object\t',address,'\nscene\t',scene,'\nvoting\t',voting and 1 or 0,'\nauthorize\t',authorize and 1 or 0,'\nop\t',operation or'install','\n');f:close();call()
  f=assert(io.open(output..'/cinema-guard-status.tsv','r'));local text=f:read(2049);f:close();assert(#text<=2048)
  local s={};for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)')do s[k]=v end
  assert(s.object==address and tonumber(s.scene)==scene and s.ok=='1','Защита пропуска: '..tostring(s.reason))
  return s
 end
 return g
end
return M
