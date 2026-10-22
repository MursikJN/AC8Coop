-- The r19 role handoff is one-shot. A shared restart uses a fresh process,
-- never resets that ledger or reuses actors from an expired world.
local M={}
function M.new(c,output,source,log,engine)
 local E=engine
 if not E then
  local pause=assert(loadfile(source..'/mission_sync_pause.lua'))().new(output,source)
  local function pc()return require('UEHelpers').GetPlayerController()end
  E={hold=function()
   local s=pause.command('acquire');assert(s.held=='1'and s.paused=='1','Не удалось остановить мир сессии.')
   assert(StaticFindObject('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc():GetWorld()),'Мир продолжает идти.')
  end,quit=function()
   local fn=StaticFindObject('/Script/Engine.KismetSystemLibrary:QuitGame');assert(fn and fn:IsValid(),'Штатный выход недоступен.')
   local fields={};fn:ForEachProperty(function(p)fields[#fields+1]=p:GetFName():ToString()..':'..p:GetClass():GetFName():ToString()end)
   local sig=table.concat(fields,',')
   assert(sig=='WorldContextObject:ObjectProperty,SpecificPlayer:ObjectProperty,QuitPreference:ByteProperty,bIgnorePlatformRestrictions:BoolProperty'or sig=='WorldContextObject:ObjectProperty,SpecificPlayer:ObjectProperty,QuitPreference:EnumProperty,bIgnorePlatformRestrictions:BoolProperty','Изменилась сигнатура штатного выхода.')
   StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):QuitGame(pc():GetWorld(),pc(),0,false)
  end}
 end
 local r={halted=false,quitting=false}
 local function save()
  local f=assert(io.open(output..'/session-lifecycle.tsv','wb'));f:write('config_token\t',c.token,'\nphase\t',c.snapshot.phase or'0','\nhalted\t',r.halted and 1 or 0,'\nquiesced\t',r.quiesced and 1 or 0,'\nquitting\t',r.quitting and 1 or 0,'\nreason\t',(r.error or r.reason or''):gsub('[\r\n\t]',' '),'\nrestart_mode\tfresh_process_return_to_lobby\nhost_progress_only\t1\n');f:close()
 end
 local function quiesce(parts)
  E.hold() -- Before touching any input, role, camera or actor lease.
  if r.quiesced then return end
  if parts.pilot then parts.pilot.stop('session_quiesce')end
  if parts.role and parts.role.runtime then parts.role.runtime.stop('session_quiesce')end
  if parts.client then parts.client.stop('session_quiesce')end
  if c.cinema then c.cinema.stop('session_quiesce')end
  if parts.client and parts.client.drain and not parts.client.drain()then return false end
  if parts.pilot and parts.pilot.cleanup_pending then parts.pilot.update(parts.role);if parts.pilot.cleanup_pending then return false end end
  r.quiesced=true;log('session_quiesced',c.snapshot.generation)
  return true
 end
 local function ticket()
  local s=c.snapshot;assert(s.phase=='10'and s.restart_ack=='2'and not c.pending,'Общий перезапуск ещё не подтверждён.')
  local host=c.role=='host'and s.self or s.peer
  assert(type(host)=='string'and host:match('^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$'),'Нет SteamID хоста.')
  local f=assert(io.open(output..'/session-restart.tsv.tmp','wb'))
  f:write('format\tac8-restart-r29\nconfig_token\t',c.token,'\nrole\t',c.role,'\nhost_id\t',host,'\nmission\t',s.mission,'\ndifficulty\t',s.difficulty,'\nrestart_id\t',s.restart_id,'\nepoch\t',s.epoch,'\nrevision\t',s.revision,'\nsealed\t1\ncreated_unix\t',os.time(),'\n');f:close()
  os.remove(output..'/session-restart.tsv');assert(os.rename(output..'/session-restart.tsv.tmp',output..'/session-restart.tsv'))
 end
 function r.quit()
  -- This explicit user action is not a shared restart and writes no ticket.
  if r.quitting then return end
  if r.parts and tonumber(c.snapshot.phase or'0')>0 then local ok,err=pcall(quiesce,r.parts);if not ok then log('quit_quiesce_error',err)end end
  r.quitting=true;local ok,err=pcall(E.quit);if not ok then r.quitting=false;error(err)end;log('session_user_quit_requested')
 end
 function r.update(parts)
  r.parts=parts
  if r.quitting then return true end
  local ok,err=xpcall(function()
   local s=c.snapshot;local phase=tonumber(s.phase)or 0
   if phase>0 and phase<8 then
   for _,name in ipairs({'adapter','role','client','pilot'})do
    local part=parts[name];if part and(part.error or(name=='pilot'and part.reason))then c.fault(tostring(part.error or part.reason))end
   end
   if c.cinema and c.cinema.error then c.fault(c.cinema.error)end
   end
   r.halted=phase==8 or phase==9 or phase==10 or c.local_failure~=nil or(phase>0 and not c.view().connected)
   if not r.halted then return end
   r.reason=c.status();if quiesce(parts)==false then return end
   if phase==9 then
    local loaded=tonumber(s.loaded_mask)or 0;local own=c.role=='host'and loaded%2==1 or c.role=='guest'and loaded>=2
    if not own and not c.pending then c.loaded()end
   elseif phase==10 then
    if c.role=='guest'and s.restart_ack~='2'and not c.pending then c.restart_ack()end
    if s.restart_ack=='2'and not c.pending then
     r.sealed_at=r.sealed_at or c.now
     -- Give the guest's confirmation snapshot time to drain before the host exits.
     if c.role=='guest'or c.now-r.sealed_at>=2000 then ticket();r.quitting=true;E.quit();log('shared_restart_quit',s.restart_id)end
    end
   end
  end,debug.traceback)
  if not ok then r.error=tostring(err);r.quitting=false;r.halted=true;c.local_failure=r.error;pcall(E.hold);log('session_lifecycle_error',r.error)end
  save();return r.halted
 end
 return r
end
return M
