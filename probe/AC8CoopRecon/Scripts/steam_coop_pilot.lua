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
  if native.pilot_prepare and c.role=='host'and s.pause then s.pause.command('acquire');s.host_hold=true end
  if s.active or(native.pilot_prepare and s.attempted)then native.pilot_stop();if native.pilot_prepare and c.role=='guest'then s.cleanup_pending=true end end;s.active=false;s.loaded=false;s.reason=reason
  if s.camera then s.camera.stop(reason);s.camera=nil end
 end
 function s.start(context)
  assert(not s.active and c.view().connected and tonumber(c.snapshot.generation)>0,'Нет подтверждённого вылета.')
  local rows={'created_unix\t'..os.time(),'role\t'..c.role,'transport\tsteam','generation\t'..c.snapshot.generation,'revision\t'..c.snapshot.revision,'peer\t'..c.snapshot.peer}
  if c.role=='host'then
   assert(context and context.ready and context.runtime.active,'Роль Бакстера не подготовлена.')
   if native.pilot_prepare then
    s.pause=assert(loadfile(source..'/mission_sync_pause.lua'))().new(output,source)
    local held=s.pause.command('acquire');assert(held.held=='1'and held.paused=='1','Не удалось удержать вылет до модели гостя.');s.host_hold=true
   end
   local r=context.graph;local function addr(o)assert(o and o:IsValid());return string.format('0x%x',o:GetAddress())end
   for _,e in ipairs({{'controller',r.controller},{'host',r.host_player},{'other0',r.other_wingmen[1]},{'other1',r.other_wingmen[2]},{'manager',context.manager}})do rows[#rows+1]=e[1]..'\t'..addr(e[2])end
   local aircraft={tonumber(c.snapshot.host_aircraft),23}
   for _,o in ipairs(r.other_wingmen)do aircraft[#aircraft+1]=assert(tonumber(o:GetClass():GetFullName():match('BP_WOP10(%d%d)_')),'Неизвестная модель ведомого.')end
   for i,id in ipairs(aircraft)do rows[#rows+1]='aircraft'..(i-1)..'\t'..id end
  else
   assert(context and context.ready and context.isolated_world_verified,'Клиентская сцена не готова.')
   if native.pilot_prepare then assert(loadfile(source..'/guest_owner_preparation.lua'))().request(c,context,rows)end
  end
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
  if not s.active then
   if s.cleanup_pending then
    native.pilot_tick();local status=read('guest-pilot-status.tsv');s.cleanup_pending=status.owner_cleanup_complete~='1'
    if s.cleanup_pending and c.now-(s.last_gc or 0)>=1000 then
     StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):CollectGarbage();s.last_gc=c.now
    end
   end
   return
  end
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
  if native.pilot_prepare and c.role=='host'then
   if s.host_hold and status.peer_loaded=='1'then s.pause.command('release');s.host_hold=false end
   local f=io.open(output..'/guest-owner-remote.ac8p','rb')
   if f then local data=f:read(393);f:close();local frame=assert(loadfile(source..'/guest_pilot_view.lua'))().owner(data)
    if frame.generation==tonumber(c.snapshot.generation)and frame.revision==tonumber(c.snapshot.revision)and not held then
     local p=frame.pose;assert(context.player and context.player:IsValid(),'Remote Baxter actor expired')
     local q=p.rotation;local rot=StaticFindObject('/Script/Engine.Default__KismetMathLibrary'):Quat_Rotator({X=q[1],Y=q[2],Z=q[3],W=q[4]})
     context.player:K2_SetActorLocationAndRotation({X=p.position[1],Y=p.position[2],Z=p.position[3]},rot,false,{},true)
    end
   end
  end
  if c.role=='guest'and context and context.ready and context.isolated_world_verified then
   if native.pilot_prepare and status.owner_ready~='1'and not s.prepare_requested then
    local f=io.open(output..'/guest-pilot-state.ac8p','rb')
    if f then local data=f:read(393);f:close();local view=assert(loadfile(source..'/guest_pilot_view.lua'))();local frame=view.parse(data)
     if frame.generation==tonumber(c.snapshot.generation)and frame.revision==tonumber(c.snapshot.revision)then
      write('guest-owner-seed.tsv',assert(loadfile(source..'/guest_owner_preparation.lua'))().seed(frame,view));s.prepare_requested=true;native.pilot_prepare();status=read('guest-pilot-status.tsv')
      assert(status.active=='1'and status.owner_ready=='1','Штатная модель гостя не готова: '..tostring(status.owner_detail))
     end
    end
   end
   if native.pilot_prepare and status.owner_ready=='1'and not context.context.local_owner_verified then
    local pointer=assert(tonumber(status.owner_pointer));local owned
    for _,o in ipairs(FindAllOf('BP_PlayerPlane_PP0023_f14d_C')or{})do if o:IsValid()and o:GetAddress()==pointer then assert(not owned);owned=o end end
    assert(owned and owned:GetWorld():GetAddress()==context.context.world:GetAddress(),'Prepared owner actor missing from guest world')
    owned:SetActorHiddenInGame(true);owned:SetActorEnableCollision(false)
    context.context.local_owner_actor=owned;context.context.local_owner_verified=true
   end
   if not s.loaded then native.pilot_loaded();s.loaded=read('guest-pilot-status.tsv').state=='guest_world_loaded_sent'end
   if s.loaded and phase==6 and c.now-s.last_capture>=16 then native.pilot_capture_input();s.last_capture=c.now end
  end
 end
 return s
end
return M
