-- Presentation state only. Authority, acknowledgements and readiness remain in
-- the session controller. No button can manufacture a successful connection.
local M={}
function M.new(options,catalog)
 local s={screen=options.is_host and'create'or'join',error=nil,mission=6,difficulty=1,room=false}
 local function raw()return options.view()end
 local function log(event,detail)if options.log then pcall(options.log,event,detail or'')end end
 local function is_host()return s.room and s.role=='host'or not s.room and(options.create and s.screen=='create'or not options.create and options.is_host==true)end
 local function invoke(fn,...)
  assert(type(fn)=='function','Действие пока недоступно.')
  local ok,err=pcall(fn,...);s.error=not ok and tostring(err):gsub('^.-:%d+:%s*','')or(err==false and'Действие отклонено. Повторите попытку.'or nil)
  if not ok or err==false then log('frontend_action_error',s.error);return false end;return true
 end
 local function known(list,value)for _,e in ipairs(list)do if e.value==value then return e end end end
 function s.mode(mode)
  assert(not s.room,'Сначала выйдите из лобби.');assert(mode=='create'or mode=='join')
  assert(not options.fixed_role or(mode=='create')==(options.fixed_role=='host'),'Роль закреплена лаунчером.')
  s.screen=mode;s.error=nil;log('frontend_mode',mode)
 end
 function s.select(mission,difficulty)
  assert(known(catalog.missions,mission)and known(catalog.difficulties,difficulty),'Выбор отсутствует в меню.')
  local v=raw();assert(is_host()and not v.pending and(v.phase or 0)==0,'Параметры выбирает хост до начала загрузки.')
  if mission==s.mission and difficulty==s.difficulty then return true end
  if s.room and not invoke(options.select,mission,difficulty)then return false end
  s.mission=mission;s.difficulty=difficulty;s.error=nil;log('frontend_selection',mission..'/'..difficulty);return true
 end
 function s.enter(peer)
  local v=raw();assert(not s.room and not v.pending,'Дождитесь подтверждения действия.')
  if s.screen=='create'then
   assert(options.create or options.is_host,'В этом запуске доступно только подключение к хосту.')
   if options.create then if not invoke(options.create,s.mission,s.difficulty)then return false end
   elseif v.mission~=s.mission or v.difficulty~=s.difficulty then if not invoke(options.select,s.mission,s.difficulty)then return false end end
   s.role='host'
  else
   if options.join then
    assert(type(peer)=='string'and #peer==17 and peer:match('^[1-9]%d+$'),'Введите SteamID64 хоста: 17 цифр.')
    if not invoke(options.join,peer)then return false end
   else
    assert(not options.is_host,'В этом локальном запуске открыт хост. Для проверки гостя используйте его панель.')
    assert(v.connected,'Хост пока недоступен.')
   end
   s.role='guest'
  end
  s.room=true;s.screen='room';s.error=nil;log('frontend_room_requested',s.role);return true
 end
 function s.primary()
  local v=raw();assert(s.room,'Сначала создайте лобби или подключитесь.')
  if is_host()and v.can_open_hangar then log('frontend_hangar_requested');return invoke(options.open_hangar)end
  assert(v.can_ready,'Ожидание второго участника или подтверждения действия.')
  log('frontend_ready_requested');return invoke(options.ready)
 end
 function s.unready()
  local v=raw();assert(s.room and v.ready and v.can_ready,'Готовность ещё не подтверждена.')
  log('frontend_unready_requested');return invoke(options.ready)
 end
 function s.invite()
  assert(s.room and is_host()and raw().can_invite,'Приглашение сейчас недоступно.')
  log('frontend_invite_dialog_requested');return invoke(options.invite)
 end
 function s.leave()
  local v=raw();assert(not s.room or(v.phase or 0)==0,'Дождитесь завершения перехода.')
  if s.room and options.leave then if not invoke(options.leave)then return false end
  elseif s.room and v.ready then if not invoke(options.ready)then return false end end
  s.room=false;s.screen=s.role=='guest'and'join'or'create';s.error=nil;return true
 end
 function s.view()
  local v=raw();local host=is_host();local phase=v.phase or 0
  if v.room_role then
   if not s.room or s.role~=v.room_role or(v.join_notice or 0)~=(s.join_notice or 0)then s.error=nil end
   s.room=true;s.role=v.room_role;s.screen='room';s.join_notice=v.join_notice;host=is_host()
  elseif v.manages_room and s.room then s.room=false;s.screen=s.role=='guest'and'join'or'create';host=is_host()end
  if not s.room then
   if v.mission and known(catalog.missions,v.mission)then s.mission=v.mission end
   -- Draft choices remain editable until an explicit Create/Join action.
  end
  local mission=s.room and(v.mission or s.mission)or s.mission
  local difficulty=s.room and(v.difficulty or s.difficulty)or s.difficulty
  local d=known(catalog.difficulties,difficulty);local m=known(catalog.missions,mission)
  local primary,enabled='ГОТОВ',v.can_ready==true
  if host and v.can_open_hangar then primary=v.open_caption or'ПЕРЕЙТИ В АНГАР';enabled=true
  elseif host and v.ready and v.guest_ready then primary=v.lobby_only and'ОБА ГОТОВЫ'or'ПРОДОЛЖЕНИЕ НЕДОСТУПНО';enabled=false
  elseif v.ready then primary=host and'ОЖИДАНИЕ ГОСТЯ'or'СНЯТЬ ГОТОВНОСТЬ';enabled=not host and enabled end
  local detail=s.error or(not v.pending and v.error or nil)or v.info
  if not detail then
   if v.pending then detail='Подтверждение действия…'
   elseif not s.room then detail=s.screen=='join'and(options.join and'Введите SteamID64 хоста и подключитесь.'or(options.is_host and'Локальная проверка: гость подключается из отдельной панели.'or'Подключитесь к локальному хосту.'))or'Выберите параметры и создайте лобби.'
   elseif not v.connected then detail='Ожидание второго участника…'
   elseif phase~=0 then detail='Переход в ангар…'
   elseif v.lobby_only and v.host_ready and v.guest_ready then detail='Оба готовы. Совместный запуск миссии пока не подключён.'
   elseif v.lobby_only and not host and v.guest_aircraft~=23 then detail='Выберите F-14D, затем подтвердите готовность.'
   elseif not v.lobby_only and difficulty~=1 then detail='Для запуска сейчас поддерживается сложность «ПИЛОТ».'
   elseif v.can_open_hangar then detail='Оба участника готовы. Хост может продолжить.'
   elseif v.ready then detail='Ожидание готовности второго участника…'
   else detail='Подтвердите готовность к совместному вылету.'end
  end
  return {screen=s.screen,room=s.room,host=host,mission=mission,difficulty=difficulty,
   mission_caption=m and m.caption or'Задание не выбрано',difficulty_caption=d and d.caption or'Сложность не выбрана',
   connected=v.connected==true,host_ready=v.host_ready==true,guest_ready=v.guest_ready==true,
   host_name=v.host_name or(host and'Вы'or'Хост'),guest_name=v.guest_name or(host and'Друг'or'Вы'),
   guest_aircraft=v.guest_aircraft==23 and'F-14D'or'Самолёт не выбран',
   primary=primary,can_primary=enabled,can_unready=host and v.ready and v.can_ready==true,
   can_edit=host and not v.pending and phase==0,
   can_enter=not v.pending and(s.screen=='create'and host and(options.create~=nil or v.have_snapshot~=false)or s.screen=='join'and(options.join~=nil or not options.is_host and v.connected==true)),
   can_loadout=v.can_loadout==true,host_id=v.host_id,lobby_only=v.lobby_only,
   can_invite=host and s.room and v.can_invite==true,
   fixed_role=options.fixed_role,
   can_leave=phase==0,detail=detail}
 end
 return s
end
return M
