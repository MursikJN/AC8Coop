-- Session-bound flight orchestration; the native pilot never opens a second
-- Steam connection and never treats a lobby ACK as a loaded client scene.
local M={}
function M.new(c,output,source,native,log)
 local s={active=false,loaded=false,last_capture=0}
 local function write(name,body)local f=assert(io.open(output..'/'..name,'wb'));f:write(body);f:close()end
 local function read(name)
  local f=io.open(output..'/'..name,'rb');if not f then return{}end;local text=f:read(8193);f:close();assert(#text<=8192);local r={};for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)')do r[k]=v end;return r
 end
 function s.stop(reason)
  if s.active then native.pilot_stop()end;s.active=false;s.loaded=false;s.reason=reason
  if s.camera then s.camera.stop(reason);s.camera=nil end
 end
 function s.start(context)
  assert(not s.active and c.view().connected and tonumber(c.snapshot.generation)>0,'Нет подтверждённого вылета.')
  local rows={'created_unix\t'..os.time(),'role\t'..c.role,'transport\tsteam','generation\t'..c.snapshot.generation,'revision\t'..c.snapshot.revision,'peer\t'..c.snapshot.peer}
  if c.role=='host'then
   assert(context and context.ready and context.runtime.active,'Роль Бакстера не подготовлена.')
   local r=context.graph;local function addr(o)assert(o and o:IsValid());return string.format('0x%x',o:GetAddress())end
   for _,e in ipairs({{'controller',r.controller},{'host',r.host_player},{'other0',r.other_wingmen[1]},{'other1',r.other_wingmen[2]},{'manager',context.manager}})do rows[#rows+1]=e[1]..'\t'..addr(e[2])end
   local aircraft={tonumber(c.snapshot.host_aircraft),23}
   for _,o in ipairs(r.other_wingmen)do aircraft[#aircraft+1]=assert(tonumber(o:GetClass():GetFullName():match('BP_WOP10(%d%d)_')),'Неизвестная модель ведомого.')end
   for i,id in ipairs(aircraft)do rows[#rows+1]='aircraft'..(i-1)..'\t'..id end
  else assert(context and context.ready and context.isolated_world_verified,'Клиентская сцена не готова.')end
  write('guest-pilot-request.tsv',table.concat(rows,'\n')..'\n');native.pilot_start()
  local result=read('guest-pilot-status.tsv');assert(result.active=='1','Полётный модуль отказал: '..tostring(result.engine_detail))
  s.active=true;s.binding=c.token..':'..c.snapshot.generation..':'..c.snapshot.revision;log('coop_pilot_started',s.binding)
 end
 function s.try_start(context)
  if s.attempted then return end;s.attempted=true
  local ok,err=xpcall(function()s.start(context)end,debug.traceback)
  if not ok then s.reason=tostring(err);c.error='Полётный модуль: '..s.reason;log('coop_pilot_error',s.reason)end
 end
 function s.update(context)
  if not s.active then return end
  local phase=tonumber(c.snapshot.phase);local binding=c.token..':'..c.snapshot.generation..':'..c.snapshot.revision
  if not c.view().connected or binding~=s.binding or phase==8 then s.stop('room_or_sortie_changed');return end
  local held=phase~=6
  if c.role=='host'then
   local world=context.graph.world;assert(world:IsValid(),'Host world expired')
   held=held or StaticFindObject('/Script/Engine.Default__GameplayStatics'):IsGamePaused(world)
  end
  write('guest-pilot-clock.tsv','created_unix\t'..os.time()..'\npaused\t'..(held and 1 or 0)..'\n')
  native.pilot_tick();local status=read('guest-pilot-status.tsv')
  if status.active~='1'then s.stop(status.state or'native_pilot_stopped');c.error='Управление гостя остановлено: '..s.reason;log('coop_pilot_stopped',s.reason);return end
  if c.role=='guest'and context and context.ready and context.isolated_world_verified then
   if not s.loaded then native.pilot_loaded();s.loaded=read('guest-pilot-status.tsv').state=='guest_world_loaded_sent'end
   if s.loaded and phase==6 and c.now-s.last_capture>=16 then native.pilot_capture_input();s.last_capture=c.now end
  end
 end
 return s
end
return M
