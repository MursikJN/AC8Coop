-- Flight-only laboratory integration. Never automatically resumes a stopped session.
local M={}
function M.parse(text,token)
 if not text or #text>8192 then return nil end
 local s={}
 for line in text:gmatch('[^\r\n]+')do
  local k,v=line:match('^([^\t]+)\t([^\t]*)$')
  if not k or s[k]~=nil then return nil end;s[k]=v
 end
 if s.format~='ac8-session-status-v2'or s.config_token~=token or s.role~='host'or s.have_snapshot~='1'then return nil end
 for _,k in ipairs({'epoch','phase','stop_reason','local_tick'})do
  if not s[k]or not s[k]:match('^%d+$')then return nil end
 end
 return s
end
function M.new(pause,token,log)
 local p={state='idle',armed=false,latched=false,error=nil}
 local boot=false;local epoch=0;local last_tick;local last_progress
 local function state(value,why)
  if p.state~=value then p.state=value;log(value,why or'')end
 end
 function p.step(text,rows,now)
  if p.error then return p.state end
  local ok,err=pcall(function()
   if not boot then pause.bootstrap();boot=true end
   local s=M.parse(text,token)
   if s and tonumber(s.epoch)>=epoch then
    epoch=tonumber(s.epoch)
    if s.local_tick~=last_tick then last_tick=s.local_tick;last_progress=now end
    if not p.latched and s.phase=='6'and s.connected=='1'and rows.flight==1 and rows.active==1 then
     p.armed=true;state('armed','live flight and connected peer')
    end
    if p.armed and not p.latched and s.phase=='8'and s.stop_reason=='3'then
     p.latched=true;state('loss_detected','native peer loss; epoch='..s.epoch)
    end
   end
   -- Missing/corrupt status or stalled bridge must not allow unattended flight.
   if p.armed and not p.latched and last_progress and now-last_progress>=5 then
    p.latched=true;state('loss_detected','local bridge/status watchdog')
   end
   if not p.latched then return end
   local r=pause.command('poll')
   if r.held~='1'then
    -- The same override-resistant reason can already belong to the game.
    -- Preserve other reasons and the game's override counter unchanged.
    if tonumber(r.flags)&32~=0 then
     state('waiting_for_stock_pause','flags='..r.flags..'; override='..r.override);return
    end
    r=pause.command('acquire')
   end
   assert(r.held=='1'and r.paused=='1','pause_not_confirmed')
   state('held','flags='..r.flags..'; applied='..r.applied)
  end)
  if not ok then p.error=tostring(err);state('failed',p.error)end
  return p.state
 end
 return p
end
return M
