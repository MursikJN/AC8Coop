local M={}
function M.new(output,source)
 local call=assert(package.loadlib(source..'/../../../ac8_mission_pause_r26.dll','luaopen_ac8_mission_pause'))
 local p={}
 local function command(op)
  assert(op=='bootstrap'or op=='acquire'or op=='release'or op=='poll','Неизвестная команда паузы.')
  local manager
  if op~='bootstrap'then
   local gi=require('UEHelpers').GetGameInstance();assert(gi and gi:IsValid(),'Нет игрового профиля.')
   manager=gi.PauseManager_;assert(manager and manager:IsValid(),'Нет штатного менеджера паузы.')
  end
  local address=string.format('0x%x',manager and manager:GetAddress()or 0)
  _G.AC8MissionPauseSequence=(_G.AC8MissionPauseSequence or 0)+1
  local stamp='pause-'..os.time()..'-'.._G.AC8MissionPauseSequence
  os.remove(output..'/mission-pause-status.tsv')
  local f=assert(io.open(output..'/mission-pause-request.tsv','wb'))
  assert(f:write('format\tac8-mission-pause-v2\nstamp\t',stamp,'\ncreated_unix\t',os.time(),'\nobject\t',address,'\nop\t',op,'\n'));assert(f:close());call()
  local why;f,why=io.open(output..'/mission-pause-status.tsv','r');assert(f,'pause_native_response_missing: '..tostring(why))
  local text=f:read(2049);f:close();assert(text and #text<=2048,'Слишком большой ответ паузы.')
  local s={};for line in text:gmatch('[^\r\n]+')do local k,v=line:match('^([^\t]+)\t([^\t]*)$');assert(k and s[k]==nil,'Некорректный ответ паузы.');s[k]=v end
  assert(s.format=='ac8-mission-pause-v2'and s.stamp==stamp,'Устаревший ответ паузы.')
  assert(s.ok=='1','pause_native_'..tostring(s.reason))
  assert(s.object==address,'Ответ паузы относится к другому объекту.');return s
 end
 function p.command(op)
  assert(not p.error,p.error)
  local ok,result=xpcall(function()return command(op)end,debug.traceback)
  if not ok then p.error=tostring(result);error(p.error,0)end
  return result
 end
 function p.bootstrap()return p.command('bootstrap')end
 return p
end
return M
