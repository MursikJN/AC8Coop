local M={}
function M.new(output,source)
 local call=assert(package.loadlib(source..'/../../../ac8_mission_pause_r26.dll','luaopen_ac8_mission_pause'))
 local p={}
 function p.command(op)
  local gi=require('UEHelpers').GetGameInstance();assert(gi and gi:IsValid(),'Нет игрового профиля.')
  local manager=gi.PauseManager_;assert(manager and manager:IsValid(),'Нет штатного менеджера паузы.')
  local address=string.format('0x%x',manager:GetAddress())
  local f=assert(io.open(output..'/mission-pause-request.tsv','w'));f:write('object\t',address,'\nop\t',op,'\n');f:close();call()
  f=assert(io.open(output..'/mission-pause-status.tsv','r'));local text=f:read(2049);f:close();assert(#text<=2048)
  local s={};for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)')do s[k]=v end
  assert(s.object==address and s.ok=='1','Ожидание мира: '..tostring(s.reason));return s
 end
 return p
end
return M
