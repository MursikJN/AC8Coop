-- Steam lobby controller. UI state changes only after an authenticated host snapshot.
local M={}
function M.new(output,native,clock,options)
 options=options or{};local mission_sync=options.mission_sync==true;local cinema_sync=options.cinema_sync==true;local policy=options.session_policy==true
 local now=clock or os.time
 local c={snapshot={},session_policy=policy,active=false,closing=false,sequence=0,serial=0,invite_seen=0,invite_sequence=0,join_notice=0,menu_available=not native.invites_tick,invite_status={}}
 local function trace(event,detail)if options.trace then pcall(options.trace,event,detail)end end
 c.trace=trace
 local function read(name,format,unscoped)
  local f=io.open(output..'/'..name,'rb');if not f then return end
  local text=f:read(8193);f:close();if not text or #text>8192 then return end
  local s={};for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)\r?\n')do s[k]=v end
  if s.format==format and(unscoped or s.config_token==c.token)then return s end
 end
 local function write(name,text)
  local f=assert(io.open(output..'/'..name,'wb'));assert(f:write(text));assert(f:close())
 end
 local function command(op,a,b)
  assert(c.active and not c.closing and not c.pending,'Дождитесь подтверждения действия.')
  local s=c.snapshot;assert(s.have_snapshot=='1','Ожидание состояния хоста.')
  c.sequence=c.sequence+1
  write('shared-session-command.tsv',string.format('request\t%d\nepoch\t%s\nrevision\t%s\nop\t%d\narg0\t%d\narg1\t%d\n',c.sequence,s.epoch,s.revision,op,a,b or 0))
  c.pending={request=c.sequence,since=now()};c.error=nil
  trace('command_sent',{request=c.sequence,op=op,arg0=a,arg1=b or 0,epoch=s.epoch,revision=s.revision,generation=s.generation})
 end
 local function begin(role,peer,mission,difficulty)
  assert(not c.active and not c.closing,'Сначала выйдите из текущего лобби.')
  if policy then assert(role==options.launch_role,'Для этой роли нужен соответствующий лаунчер.');assert(not c.used_world,'Для новой миссии нужен чистый процесс игры.')end
  native.tick()
  if role=='guest'then assert(type(peer)=='string'and #peer==17 and peer:match('^[1-9]%d+$'),'Введите SteamID64 хоста: 17 цифр.')end
  if mission_sync and role=='host'then assert(mission==6 and difficulty==1,'Первый совместный вылет: задание 6 / ПИЛОТ.')end
  c.serial=c.serial+1;c.token=string.format('%.0f',now()*100000+c.serial)
  c.role=role;c.peer=peer;c.snapshot={};c.sequence=0;c.error=nil;c.info=nil;c.pending=nil;c.started=now();c.last_status=nil;c.initial=role=='host'and{mission,difficulty}or nil;c.local_failure=nil;c.cancel_requested=nil;c.faulted_attempt=nil
  os.remove(output..'/shared-session-status.tsv');os.remove(output..'/shared-session-command.tsv')
  write('shared-session-config.tsv',role..'\n'..(peer or'0')..'\n'..c.token..'\n')
  trace('room_begin',{role=role,peer=peer,config_token=c.token,mission=mission,difficulty=difficulty})
  native.start();c.active=true;return true
 end
 function c.create(m,d)return begin('host',nil,m,d)end
 function c.join(peer)return begin('guest',peer)end
 function c.leave(preserve_invite)
  if not preserve_invite then c.auto_target=nil;c.info=nil end
  if c.active then trace('room_leave',{request=c.pending and c.pending.request});native.stop();c.closing=true;c.pending=nil;c.initial=nil;c.error=nil end
  return true
 end
 function c.set_menu_available(available)c.menu_available=available==true end
 local function poll_invites()
  if not native.invites_tick then return end
  native.invites_tick()
  local s=read('steam-invite-status.tsv','ac8-invite-status-v1',true);if not s then return end
  if s.instance~=c.invite_status.instance then c.invite_seen=0 end
  c.invite_status=s
  if c.invite_request and(tonumber(s.open_seen)or 0)>=c.invite_request then
   c.invite_request=nil
   if s.state=='OVERLAY_UNAVAILABLE'then c.info='Оверлей Steam недоступен. Можно подключиться по SteamID хоста.'
   elseif s.state and s.state:match('^ERROR_')then c.info='Приглашение недоступно: '..s.state
   else c.info='Выберите друга в Steam и отправьте приглашение.'end
  end
  local sequence=tonumber(s.join_sequence)or 0
  if sequence>c.invite_seen then
   trace('invite_received',{sequence=sequence,host=s.join_host,state=s.state})
   c.invite_seen=sequence;local target=s.join_host
   if type(target)=='string'and #target==17 and target:match('^[1-9]%d+$')then
    if policy and(options.launch_role~='guest'or c.used_world or(tonumber(c.snapshot.phase)or 0)~=0)then
     c.info='Вход доступен только в лобби гостевого запуска.';return
    end
    local transport=c.snapshot.transport or'';local closed=transport:match('^DISCONNECTED')or transport:match('^ERROR_')
    if c.active and not c.closing and c.role=='guest'and c.peer==target and not closed then
     c.info='Вы уже подключаетесь к этому хосту.'
    else
     c.auto_target=target;c.info='Приглашение принято. Подключение к хосту…'
     if c.active then c.leave(true)end
    end
   end
  end
 end
 function c.invite()
  assert(c.view().can_invite,'Сначала создайте лобби и дождитесь готовности Steam.')
  c.invite_sequence=c.invite_sequence+1;c.invite_request=c.invite_sequence
  write('steam-invite-command.tsv',string.format('request\t%d\nconfig_token\t%s\n',c.invite_sequence,c.token))
  native.invites_open();c.info='Открытие списка друзей Steam…'
  trace('invite_open',{request=c.invite_sequence})
 end
 function c.poll()
  native.tick();poll_invites()
  local control=read('shared-session-control.tsv','ac8-steam-control-v1')
  if c.closing then
   if control and control.running=='0'then c.active=false;c.closing=false;c.snapshot={};c.last_status=nil end
   if c.closing then return end
  end
  if c.auto_target and c.menu_available and not c.active then
   local target=c.auto_target;c.auto_target=nil;begin('guest',target);c.join_notice=c.join_notice+1;control=nil
   c.info='Приглашение принято. Подключение к хосту…'
  end
  if not c.active then return end
  local s=read('shared-session-status.tsv','ac8-session-status-v3')
  if s then
   if mission_sync and(s.mission_sync~='1'or s.protocol~=(policy and'7'or cinema_sync and'6'or'5')or(cinema_sync and s.cinema_sync~='1')or(policy and(s.session_policy~='1'or s.host_progress_only~='1')))then c.incompatible=true;c.error='Несовместимая сборка совместного полёта.';if policy then c.local_failure=c.error end;return end
   c.incompatible=false
   -- Tokens prevent an old room/status file from confirming a new attempt.
   if c.snapshot.connected=='1'and s.connected~='1'then c.pending=nil;c.error='Связь с участником потеряна. Готовность сброшена.'end
   if s.heartbeat and s.heartbeat~=c.snapshot.heartbeat then c.last_status=now()end
   c.snapshot=s;c.sequence=math.max(c.sequence,tonumber(s.request_ack)or 0)
   if policy and(s.phase=='9'or s.phase=='10')then c.local_failure=nil;if s.phase=='10'and s.restart_ack=='2'then c.error=nil end end
   if policy and tonumber(s.phase)and tonumber(s.phase)>0 then c.used_world=true end
   if mission_sync then c.now=tonumber(s.host_tick)or 0 end
   if s.connected=='1'then c.info=nil end
   if c.pending and(tonumber(s.request_confirmed)or 0)>=c.pending.request then
    trace('command_confirmed',{request=c.pending.request,confirmed=s.request_confirmed,reject=s.reject,epoch=s.epoch,revision=s.revision,generation=s.generation})
    c.pending=nil;c.error=(tonumber(s.reject)or 0)>0 and'Хост отклонил действие. Повторите выбор или готовность.'or nil
   end
   if c.initial and s.have_snapshot=='1'and not c.pending then
    local choice=c.initial;c.initial=nil;command(2,choice[1],choice[2])
   end
   if mission_sync and not c.pending and s.connected=='1'and s.clock_ready=='1'and(tonumber(s.release_at)or 0)>0 then
    local mask=tonumber(s.commit_mask)or 0;local committed=c.role=='host'and mask%2==1 or c.role=='guest'and mask>=2
    if not committed then local deadline=tonumber(s.release_at);command(13,deadline%4294967296,math.floor(deadline/4294967296))end
   end
   if s.transport and s.transport:match('^ERROR_')then c.error='Ошибка Steam: '..s.transport..'. Выйдите из лобби и повторите подключение.'end
   if cinema_sync and not c.pending and s.connected=='1'and s.clock_ready=='1'and(tonumber(s.cinema_at)or 0)>0 then
    local mask=tonumber(s.cinema_commit_mask)or 0;local committed=c.role=='host'and mask%2==1 or c.role=='guest'and mask>=2
    if not committed then local deadline=tonumber(s.cinema_at);command(21,deadline%4294967296,math.floor(deadline/4294967296))end
   end
   if c.role=='guest'and s.transport and s.transport:match('^DISCONNECTED')then c.error='Соединение закрыто: '..(s.reason or'Steam')..'. Выйдите из лобби и подключитесь заново.'end
  end
  if c.pending and now()-c.pending.since>=10 then
   -- A timeout must not release a second command over an unconfirmed first one.
   c.error='Нет подтверждения хоста. Выйдите из лобби и подключитесь заново.'
  end
  if now()-c.started>=15 and not c.last_status then c.error='Мод Steam не ответил. Выйдите из лобби и проверьте журналы.'end
  if control and control.running=='0'then c.error='Транспорт остановлен. Выйдите из лобби и повторите подключение.'end
  if policy then
   local phase=tonumber(c.snapshot.phase)or 0
   if phase==8 then
    local reasons={['1']='Подготовка отменена.', ['2']='Истекло ожидание загрузки (120 с).', ['3']='Связь с участником потеряна. Полёт остановлен.', ['4']='Игровой адаптер сообщил об ошибке. Сессия остановлена.'}
    c.error=reasons[c.snapshot.stop_reason]or'Сессия остановлена.'
   elseif phase~=9 and phase~=10 and((c.last_status and now()-c.last_status>=5)or(control and control.running=='0')or(not c.last_status and now()-c.started>=15))then
    c.local_failure='Нет актуального состояния мода. Действия остановлены.'
    if c.snapshot.have_snapshot=='1'and phase>0 then c.fault(c.local_failure)end
   end
  end
  if mission_sync and c.role=='guest'and native.capture_vote then
   native.capture_vote()
   local f=io.open(output..'/guest-skip-input.tsv','rb');if f then
    local text=f:read(1025);f:close();local vote={};if #text<=1024 then for k,v in text:gmatch('([%w_]+)\t([^\r\n]*)')do vote[k]=v end end
    local id=tonumber(vote.sequence)or 0
    if vote.config_token==c.token and id>(c.skip_seen or 0)then
     local current=c.snapshot
     if tonumber(vote.epoch)<(tonumber(current.epoch)or 0)then c.skip_seen=id
     elseif vote.epoch==current.epoch and vote.scene==current.scene and current.phase=='2'and not c.pending then command(5,tonumber(vote.scene));c.skip_seen=id end
    end
   end
  end
 end
 function c.view()
  local s=c.snapshot;local host=c.role=='host';local mask=tonumber(s.ready_mask)or 0
  local fresh=c.last_status and now()-c.last_status<5
  local connected=c.active and not c.closing and not c.incompatible and fresh and s.connected=='1'or false
  local busy=c.closing or c.auto_target~=nil or c.pending~=nil or(c.active and(not c.last_status or c.initial~=nil))
  local have=not c.incompatible and fresh and s.have_snapshot=='1'or false
  local own_ready=host and mask%2==1 or not host and mask>=2
  local can=connected and have and not busy and not c.local_failure and(tonumber(s.mission)or 0)>0
  local phase=mission_sync and(tonumber(s.phase)or 0)or 0
  local room_phase=phase==0 or phase==4
  return {lobby_only=not mission_sync,phase=phase,pending=busy,connected=connected,have_snapshot=have,
   ready=connected and own_ready or false,host_ready=connected and mask%2==1 or false,guest_ready=connected and mask>=2 or false,
   can_ready=can and room_phase and(host or s.guest_aircraft=='23'),can_loadout=not host and room_phase and connected and have and not busy and not c.local_failure,
   manages_room=true,room_role=c.active and not c.closing and c.role or nil,info=c.info,join_notice=c.join_notice,
   can_invite=host and not c.local_failure and(not policy or phase==0)and c.active and not busy and have and not connected and native.invites_open~=nil and c.invite_status.ready=='1'and not c.invite_request and(s.transport=='HOST_WAITING_FOR_FRIEND'or s.transport=='HOST_WAITING_FOR_REJOIN'),
   mission=tonumber(s.mission),difficulty=tonumber(s.difficulty),guest_aircraft=tonumber(s.guest_aircraft),
   host_name=s.host_name~=''and s.host_name or nil,guest_name=s.guest_name~=''and s.guest_name or nil,
   self_id=s.self,host_id=host and s.self or s.peer,error=c.local_failure or c.error or(c.active and c.last_status and not fresh and'Состояние лобби не обновляется. Выйдите и подключитесь заново.'or nil),
   can_open_hangar=mission_sync and not c.local_failure and host and connected and have and not busy and phase==0 and mask==3 and s.difficulty=='1'and s.guest_aircraft=='23',
   can_start_flight=mission_sync and not c.local_failure and host and connected and have and not busy and phase==4 and mask==3 and(tonumber(s.host_aircraft)or 0)>0 and s.guest_aircraft=='23',
   open_caption='НАЧАТЬ ПОДГОТОВКУ',loaded=tonumber(s.loaded_mask)or 0,votes=tonumber(s.vote_mask)or 0,scene=tonumber(s.scene)or 0,
   release_at=tonumber(s.release_at)or 0,committed=tonumber(s.commit_mask)or 0,closing=c.closing,
   session_policy=policy,can_cancel=policy and c.active and have and not c.cancel_requested and(phase==1 or phase==2 or phase==3 or phase==5 or phase==9 or(phase==10 and s.restart_ack~='2')),
   can_restart=policy and host and connected and have and not busy and(phase==6 or phase==7 or phase==8),
   can_quit=policy and c.active and(phase~=0 or c.local_failure~=nil),local_failure=c.local_failure~=nil}
 end
 function c.ready()local v=c.view();assert(v.can_ready,'Дождитесь подключения и выбора F-14D гостем.');command(1,v.ready and 0 or 1)end
 function c.select(m,d)assert(c.role=='host','Задание выбирает хост.');assert(m==6 and d>=1 and d<=4 and(not mission_sync or d==1),'Первый совместный вылет: задание 6 / ПИЛОТ.');command(2,m,d)end
 function c.loadout(aircraft)assert(c.view().can_loadout and aircraft==23,'Для гостя пока доступен F-14D.');command(3,23,0)end
 function c.open_hangar()assert(mission_sync and c.view().can_open_hangar,'Нужны обе готовности.');command(9,1)end
 function c.loaded()assert(mission_sync);command(7,0)end
 function c.vote_skip()local v=c.view();assert(mission_sync and v.phase==2,'Нет общей катсцены.');command(5,v.scene)end
 function c.scene_segment(id)assert(mission_sync and c.role=='host');command(14,id)end
 function c.flight_scene(id)assert(mission_sync and c.role=='host');command(16,id)end
 function c.scene_ended()assert(mission_sync and c.role=='host');command(8,c.view().scene)end
 function c.cinema_prepared()assert(cinema_sync);command(19,c.view().scene)end
 function c.cinema_finished()assert(cinema_sync);command(20,c.view().scene)end
 function c.hangar_verified(host,guest)assert(mission_sync and c.role=='host');command(11,host,guest)end
 function c.start_flight()assert(mission_sync and c.view().can_start_flight,'Нужны обе новые готовности в ангаре.');command(6,0)end
 function c.flight_verified()assert(mission_sync and c.role=='host');command(12,0)end
 local function emergency(op)
  assert(policy and c.active and c.snapshot.have_snapshot=='1','Нет активной попытки.')
  c.sequence=c.sequence+1;local s=c.snapshot
  write('session-emergency.tsv',string.format('request\t%d\nconfig_token\t%s\nepoch\t%s\nrevision\t%s\nop\t%d\ngeneration\t%s\n',c.sequence,c.token,s.epoch,s.revision,op,s.generation))
  trace('emergency_sent',{request=c.sequence,op=op,epoch=s.epoch,revision=s.revision,generation=s.generation,supersedes=c.pending and c.pending.request})
  c.pending={request=c.sequence,since=now()};return true
 end
 function c.cancel()
  assert(c.view().can_cancel,'Отмена загрузки сейчас недоступна.');emergency(23);c.cancel_requested=true;c.info='Отмена подготовки…'
 end
 function c.fault(reason)
  if not policy or not c.active or c.snapshot.have_snapshot~='1'or c.snapshot.phase=='0'or c.snapshot.phase=='8'or c.snapshot.phase=='10'then return end
  local key=c.snapshot.generation..':'..c.snapshot.revision;if c.faulted_attempt==key then return end
  c.faulted_attempt=key;c.local_failure=reason or'Ошибка игрового адаптера';emergency(24)
 end
 function c.restart()assert(c.view().can_restart,'Общий перезапуск запускает хост при доступном втором участнике.');command(22,tonumber(c.snapshot.generation))end
 function c.restart_ack()assert(policy and c.role=='guest'and c.snapshot.phase=='10');command(25,tonumber(c.snapshot.restart_id))end
 function c.host_loadout(aircraft)assert(policy and c.role=='host'and c.snapshot.phase=='4');command(3,aircraft)end
 function c.invalidate_ready()assert(policy and c.role=='host'and c.snapshot.phase=='4');command(27,0)end
 function c.status()
  if c.local_failure then return c.local_failure end;if c.error then return c.error end;if not mission_sync then return'Подключение Steam: только лобби.'end
  local v=c.view();local names={[0]='Лобби',[1]='Загрузка вступления',[2]='Катсцена',[3]='Подготовка ангара',[4]='Ангар: новая готовность',[5]='Загрузка миссии',[6]='Совместный полёт',[7]='Результат миссии',[8]='Сессия остановлена',[9]='Подготовка общего перезапуска',[10]='Перезапуск подтверждён · Выход в чистый процесс'}
  local text=names[v.phase]or'Ожидание хоста'
  if v.phase==2 then text=text..' · Пропуск: '..((v.votes%2)+(v.votes>=2 and 1 or 0))..'/2'end
  if cinema_sync and v.phase==2 then
   local done=tonumber(c.snapshot.cinema_finished)or 0
   if done==1 or done==2 then text=text..' · Ожидание второго игрока'
   elseif tonumber(c.snapshot.cinema_state)<2 then text=text..' · Подготовка локальной сцены'end
  end
  if v.phase==1 or v.phase==3 or v.phase==5 then text=text..' · Загрузились: '..((v.loaded%2)+(v.loaded>=2 and 1 or 0))..'/2'end
  return text
 end
 return c
end
return M
