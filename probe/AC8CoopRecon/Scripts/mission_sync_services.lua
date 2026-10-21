-- r26 one-PC synchronization controller; host authority remains in the native worker.
local M={}
function M.new(output,token,native,log)
 local c={snapshot={},sequence=0,pending=nil,now=0,error=nil,selection=false}
 local function read(name)
  local f=io.open(output..'/'..name,'rb');if not f then return{}end;local text=f:read(8193);f:close();if not text or #text>8192 then return{}end
  local s={};for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)\r?\n')do s[k]=v end;return s
 end
 function c.command(op,a,b)
  assert(not c.pending,'Ожидание подтверждения команды.')
  local s=c.snapshot;assert(not c.stale and s.config_token==token and s.have_snapshot=='1','Ожидание состояния хоста.')
  c.sequence=c.sequence+1
  local f=assert(io.open(output..'/shared-session-command.tsv','wb'))
  assert(f:write(string.format('request\t%d\nepoch\t%s\nrevision\t%s\nop\t%d\narg0\t%d\narg1\t%d\n',c.sequence,s.epoch,s.revision,op,a or 0,b or 0)));f:close()
  c.pending={request=c.sequence,since=c.now,op=op};c.error=nil;log('sync_request',c.sequence..'/'..op..'/'..(a or 0))
 end
 function c.start()native.start()end
 function c.poll()
  native.clock();c.now=tonumber(read('sync-clock.tsv').tick)or c.now
  c.stale=c.now-(tonumber(c.snapshot.local_tick)or-10000)>8000
  local s=read('shared-session-status.tsv');if s.config_token~=token or s.mission_sync~='1'then return end
  c.snapshot=s;c.stale=c.now-(tonumber(s.local_tick)or-10000)>8000
  if c.stale then c.error='Нет свежего состояния хоста. Переход удерживается.';return end
  c.sequence=math.max(c.sequence,tonumber(s.request_ack)or 0)
  if c.pending and(tonumber(s.request_confirmed)or 0)>=c.pending.request then
   log('sync_confirmed',c.pending.request..'/reject='..(s.reject or'?'))
   if s.reject~='0'then c.error='Команда отклонена: '..s.reject end;c.pending=nil
  end
  if c.pending and c.now-c.pending.since>10000 then c.error='Нет подтверждения. Переход удерживается.'end
  if not c.selection and not c.pending and s.have_snapshot=='1'then c.selection=true;c.command(2,6,1)end
  if s.connected=='1'and not c.pending and(tonumber(s.release_at)or 0)>0 and(tonumber(s.commit_mask)or 0)%2==0 then
   local deadline=tonumber(s.release_at);c.command(13,deadline%4294967296,math.floor(deadline/4294967296))
  end
 end
 function c.view()
  local s=c.snapshot;local phase=tonumber(s.phase)or 0;local mask=tonumber(s.ready_mask)or 0;local connected=s.connected=='1'and not c.stale;local have=s.have_snapshot=='1'and not c.stale
  return {phase=phase,connected=connected,have_snapshot=have,pending=c.pending~=nil,error=c.error,
   mission=tonumber(s.mission),difficulty=tonumber(s.difficulty),guest_aircraft=tonumber(s.guest_aircraft),host_ready=mask%2==1,guest_ready=mask>=2,ready=mask%2==1,
   can_ready=connected and have and not c.pending and(phase==0 or phase==4)and s.mission=='6',
   can_open_hangar=connected and phase==0 and mask==3 and s.difficulty=='1'and s.guest_aircraft=='23'and not c.pending,
   open_caption='НАЧАТЬ ПОДГОТОВКУ',
   can_start_flight=connected and phase==4 and mask==3 and(tonumber(s.host_aircraft)or 0)>0 and s.guest_aircraft=='23'and not c.pending,
   loaded=tonumber(s.loaded_mask)or 0,votes=tonumber(s.vote_mask)or 0,scene=tonumber(s.scene)or 0,
   release_at=tonumber(s.release_at)or 0,committed=tonumber(s.commit_mask)or 0,
   release_due=(tonumber(s.release_at)or 0)>0 and s.commit_mask=='3'and c.now>=tonumber(s.release_at)}
 end
 function c.select(m,d)assert(m==6 and d==1,'Игровая проверка пока только: задание 6 / ПИЛОТ.');c.command(2,m,d)end
 function c.ready()assert(c.view().can_ready,'Готовность недоступна.');c.command(1,c.view().ready and 0 or 1)end
 function c.open_hangar()assert(c.view().can_open_hangar,'Нужны обе готовности.');c.command(9,1)end
 function c.loaded()c.command(7)end
 function c.vote_skip()local v=c.view();assert(v.phase==2,'Нет общей катсцены.');c.command(5,v.scene)end
 function c.scene_segment(id)c.command(14,id)end
 function c.flight_scene(id)c.command(16,id)end
 function c.scene_ended()c.command(8,c.view().scene)end
 function c.hangar_verified(player,guest)c.command(11,player,guest)end
 function c.start_flight()assert(c.view().can_start_flight,'Нужны обе новые готовности в ангаре.');c.command(6)end
 function c.flight_verified()c.command(12)end
 function c.status()
  local v=c.view();if c.error then return c.error end
  local captions={[0]='Лобби',[1]='Загрузка вступления',[2]='Общая катсцена',[3]='Подготовка ангара',[4]='Ангар: новая готовность',[5]='Загрузка миссии',[6]='Полёт на хосте',[8]='Сессия остановлена'}
  local detail=captions[v.phase]or'Ожидание состояния'
  if v.phase==2 then return detail..' · Пропуск: '..((v.votes%2)+(v.votes>=2 and 1 or 0))..'/2' end
  if v.phase==1 or v.phase==3 or v.phase==5 then return detail..' · Загрузились: '..((v.loaded%2)+(v.loaded>=2 and 1 or 0))..'/2 · Подтверждения старта: '..((v.committed%2)+(v.committed>=2 and 1 or 0))..'/2'end
  return detail..' · Хост '..(v.host_ready and'✓'or'—')..' · Гость '..(v.guest_ready and'✓'or'—')
 end
 return c
end
return M
