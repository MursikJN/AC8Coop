-- Local assets, host-owned clip identity, two explicit completion receipts.
-- Engine calls live in cinema_native; no remote code or menu automation.
local M={}
local function mask(s,key)return tonumber(s[key])or 0 end
local function own(c,key)local n=mask(c.snapshot,key);return c.role=='host'and n%2==1 or c.role=='guest'and n>=2 end
function M.new(c,output,source,log,engine)
 engine=engine or assert(loadfile(source..'/cinema_native.lua'))().new(c,source,log)
 local r={ready=false,playing=false,waiting=false}
 local function read()
  local f=io.open(output..'/cinema-client.tsv','rb');if not f then return end
  local text=f:read(2049);f:close();if #text>2048 then return end
  local d={};for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)\n')do d[k]=v end
  local s=c.snapshot
  if d.config_token~=c.token or d.epoch~=s.epoch or d.revision~=s.revision or d.scene~=s.scene then return end
  d.kind=tonumber(d.kind);d.duration_ms=tonumber(d.duration_ms);return d
 end
 local function write(name,text)
  local path=output..'/'..name;local f=assert(io.open(path..'.tmp','wb'));assert(f:write(text));f:close()
  -- MSVC rename does not replace an existing file. The worker retains its
  -- previous descriptor during the short absent-file interval.
  os.remove(path);assert(os.rename(path..'.tmp',path))
 end
 local function publish(d)
  local s=c.snapshot
  local key=s.epoch..':'..s.revision..':'..s.scene;if r.published==key then return end
  write('cinema-host.tsv',string.format('config_token\t%s\nepoch\t%s\nrevision\t%s\nscene\t%s\nkind\t%d\nduration_ms\t%d\nasset\t%s\nviewer\t%s\noptions\t%s\n',c.token,s.epoch,s.revision,s.scene,d.kind,d.duration_ms,d.asset,d.viewer or'',d.options or''))
  r.published=key
 end
 local function save()
  write('cinema-playback-status.tsv',string.format('config_token\t%s\nscene\t%s\nready\t%d\nplaying\t%d\nwaiting_for_peer\t%d\nlocal_terminal\t%d\nasset\t%s\nerror\t%s\n',c.token,c.snapshot.scene or'0',r.ready and 1 or 0,r.playing and 1 or 0,r.waiting and 1 or 0,r.terminal and 1 or 0,r.descriptor and r.descriptor.asset or'',(r.error or''):gsub('[\r\n\t]',' ')))
 end
 function r.stop(reason)
  if r.handle then engine.close(r.handle,c.role=='guest');r.handle=nil end
  r.ready=false;r.playing=false;r.reason=reason
 end
 local function state()
  local s=c.snapshot;local n=mask(s,'cinema_state');local at=mask(s,'cinema_at')
  if(n==1 or n==3)and mask(s,'cinema_commit_mask')==3 and s.clock_ready=='1'and at>0 and c.now>=at then return n+1 end
  return n
 end
 function r.authorize_skip()return not r.error and c.snapshot.phase=='2'and state()==4 and mask(c.snapshot,'vote_mask')==3 end
 function r.can_end()return not r.error and mask(c.snapshot,'cinema_state')==4 and mask(c.snapshot,'cinema_finished')==3 end
 local function update()
  local s=c.snapshot;local phase=tonumber(s.phase)
  if not c.view().connected then if r.handle then engine.pause(r.handle)end;r.playing=false;return end
  if phase~=1 and phase~=2 then if r.handle then r.stop('left_cinematic')end;return end
  local key=s.revision..':'..s.scene
  if r.key~=key then
   r.stop('new_scene');r.key=key;r.started=false;r.terminal=false;r.finish_released=false;r.waiting=true;r.descriptor=nil;r.began=c.now
  end
  if c.role=='host'then
   local candidate=engine.discover()
   if candidate and r.descriptor and(candidate.descriptor.asset~=r.descriptor.asset or(candidate.identity and r.handle.identity and candidate.identity~=r.handle.identity))then
    engine.pause(candidate)
    assert(r.terminal,'Хост сменил сцену до общего завершения; переход заблокирован.')
    if r.can_end()and not c.pending then c.scene_segment(tonumber(s.scene)+1)end
    r.playing=false;r.waiting=true;return
   end
   if not r.handle and candidate then r.handle=candidate;r.descriptor=candidate.descriptor;engine.pause(r.handle)end
   if r.descriptor then publish(r.descriptor)end
  else
   local d=read()
   if d and r.descriptor then assert(d.asset==r.descriptor.asset and d.viewer==r.descriptor.viewer and d.options==r.descriptor.options and d.kind==r.descriptor.kind and d.duration_ms==r.descriptor.duration_ms,'Хост изменил данные уже подготовленной катсцены.')end
   if not r.handle and d then r.descriptor=d;r.handle=engine.open(d);engine.pause(r.handle)end
  end
  assert(c.now-(r.began or c.now)<120000 or r.started,'Истекло ожидание локальной катсцены; переход заблокирован.')
  if not r.handle then c.info='Ожидание данных катсцены от хоста';return end
  local sample=r.terminal and {ready=true,remaining_ms=0,ended=true}or engine.sample(r.handle)
  r.sample_status={ready=sample.ready,remaining_ms=sample.remaining_ms,ended=sample.ended,error=sample.error}
  assert(not sample.error,sample.error)
  r.ready=sample.ready==true
  if not r.ready then return end
  if not own(c,'cinema_prepared')then if not c.pending then c.cinema_prepared()end;return end
  if phase~=2 then return end
  local current=state()
  if current<2 or s.clock_ready~='1'then engine.pause(r.handle);r.playing=false;r.waiting=true;return end
  if not r.started then
   -- Play preserves the prepared native player's position and selected audio.
   engine.play(r.handle);r.started=true;r.playing=true;r.waiting=false;log('cinema_local_start',key)
  end
  if not r.terminal and not r.playing then engine.play(r.handle);r.playing=true;r.waiting=false end
  if not r.terminal and(sample.ended or sample.remaining_ms<=250)then
   -- Hold the terminal tail before the native completion callback can travel.
   -- Both peers release that tail together. No arbitrary duration timer is an ACK.
   engine.pause(r.handle);r.terminal=true;r.playing=false;r.waiting=true;log('cinema_terminal_ready',key)
  end
  if r.terminal and not own(c,'cinema_finished')and not c.pending then c.cinema_finished();return end
  if current==4 and not r.finish_released then
   if mask(s,'vote_mask')==3 then
    engine.skip(r.handle,c.role=='guest');r.terminal=true;r.playing=c.role=='host'
   else
    assert(mask(s,'cinema_finished')==3,'Missing completion receipts');engine.play(r.handle);r.playing=true
   end
   r.finish_released=true;r.waiting=false;log('cinema_shared_exit',key)
  end
  if r.finish_released and mask(s,'vote_mask')==3 and not own(c,'cinema_finished')and not c.pending then c.cinema_finished()end
  if r.terminal and not r.finish_released then c.info='Катсцена завершена · Ожидание второго игрока'
  elseif current<2 then c.info='Подготовка локальной катсцены'end
 end
 function r.update()
  if r.error then return end
  local ok,err=xpcall(update,debug.traceback)
  if not ok then r.error=tostring(err);if r.handle then pcall(engine.pause,r.handle)end;if engine.abort then pcall(engine.abort)end;r.playing=false;c.error='Катсцена: '..r.error;log('cinema_error',r.error)end
  if r.handle and engine.status then pcall(engine.status,r.handle,r.error and'Ошибка катсцены: '..r.error or r.waiting and r.terminal and'Ожидание второго игрока' or c.status())end
  save()
 end
 function r.diagnostics()return {key=r.key,started=r.started,playing=r.playing,terminal=r.terminal,waiting=r.waiting,finish_released=r.finish_released,asset=r.descriptor and r.descriptor.asset,viewer=r.descriptor and r.descriptor.viewer,options=r.descriptor and r.descriptor.options,sample=r.sample_status}end
 return r
end
return M
