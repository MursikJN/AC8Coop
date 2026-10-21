local M={}
function M.new(output,host,token,start_native,catalog)
 local self={snapshot={},sequence=0,pending=nil,selection=nil,detail='Ожидание локального соединения…'}
 local labels={};for _,e in ipairs(catalog and catalog.difficulties or{})do labels[e.value]=e.caption end
 local function write_request(op,a,b)
  assert(not self.pending,'Предыдущее действие ещё подтверждается.')
  local s=self.snapshot;assert(s.config_token==token and s.have_snapshot=='1','Ожидание состояния хоста.')
  self.sequence=self.sequence+1
  local f=assert(io.open(output..'/shared-session-command.tsv','wb'))
  f:write(string.format('request\t%d\nepoch\t%s\nrevision\t%s\nop\t%d\narg0\t%d\narg1\t%d\n',self.sequence,s.epoch,s.revision,op,a,b or 0));f:close()
  self.pending={request=self.sequence,op=op,arg=a,revision=s.revision,ticks=0}
 end
 function self.start()start_native()end
 function self.poll()
  local f=io.open(output..'/shared-session-status.tsv','rb');if not f then return end
  local content=f:read(4097);f:close();if not content or #content>4096 then return end
  local s={};for key,value in content:gmatch('([%w_]+)\t([^\r\n]+)\r?\n')do s[key]=value end
  if s.config_token~=token or s.format~='ac8-session-status-v2' then return end
  self.snapshot=s
  self.sequence=math.max(self.sequence,tonumber(s.request_ack)or 0)
  if host and not self.selection and s.have_snapshot=='1'then
   self.selection=true
   local adapter=os.getenv('AC8_LOCAL_HANGAR')=='25201480'
   write_request(2,adapter and 6 or 1,adapter and 1 or 2)
  end
  local p=self.pending
  if p then
   p.ticks=p.ticks+1
   local mask=tonumber(s.ready_mask)or 0;local ready=host and mask%2==1 or not host and mask>=2
   local ack=tonumber(s.request_ack)or 0
   local confirmed=tonumber(s.request_confirmed)
   if ack>=p.request and (host or (confirmed and confirmed>=p.request)or(not confirmed and (p.op~=1 or ready==(p.arg==1)or s.revision~=p.revision)))then
    self.pending=nil
    if s.reject~='0'then self.detail='Действие отклонено: '..s.reject end
   elseif p.ticks>=100 then self.pending=nil;self.detail='Нет подтверждения действия. Проверьте соединение.' end
  end
 end
 function self.ready()
  local v=self.view();assert(v.can_ready,'Сначала дождитесь подключения и выбора задания.')
  write_request(1,v.ready and 0 or 1)
 end
 function self.select(mission,difficulty)
  assert(host,'Задание выбирает хост.');write_request(2,mission,difficulty)
 end
 function self.open_hangar()
  assert(host and self.view().can_open_hangar,'Для ангара нужны оба готовых участника, задание 6, «ПИЛОТ» и F-14D гостя.')
  write_request(10,0,0)
 end
 function self.hangar_verified(player,guest)
  assert(host and player>0 and player<=65535 and guest==23,'Выбор самолётов в ангаре не подтверждён.')
  write_request(11,player,guest)
 end
 function self.start_flight()
  assert(host and self.view().can_start_flight,'В ангаре нужны обе новые готовности.')
  write_request(6,0,0)
 end
 function self.flight_verified()assert(host);write_request(12,0,0)end
 function self.view()
  local s=self.snapshot;local mask=tonumber(s.ready_mask)or 0
  local phase=tonumber(s.phase)or 0
  return {can_ready=s.connected=='1'and s.have_snapshot=='1'and(phase==0 or phase==4)and(tonumber(s.mission)or 0)>0 and not self.pending,
   ready=host and mask%2==1 or not host and mask>=2,
   can_open_hangar=host and s.connected=='1'and phase==0 and mask==3 and s.mission=='6'and s.difficulty=='1'and s.guest_aircraft=='23'and not self.pending,
   can_start_flight=host and s.connected=='1'and phase==4 and mask==3 and (tonumber(s.host_aircraft)or 0)>0 and s.guest_aircraft=='23'and not self.pending,
   phase=phase,connected=s.connected=='1',have_snapshot=s.have_snapshot=='1',pending=self.pending~=nil,
   mission=tonumber(s.mission),difficulty=tonumber(s.difficulty),host_ready=mask%2==1,guest_ready=mask>=2,guest_aircraft=tonumber(s.guest_aircraft),
   error=(tonumber(s.reject)or 0)>0 and'Действие отклонено хостом. Повторите выбор.'or nil,
   choice=string.format('%s · Задание %s · %s',host and 'ХОСТ' or 'ГОСТЬ',s.mission or '—',labels[tonumber(s.difficulty)]or '—')}
 end
 function self.status()
  local s=self.snapshot;local mask=tonumber(s.ready_mask)or 0
  if s.transport=='disconnected'or s.transport=='error'then return 'Связь закрыта: '..(s.reason or '?')..'. Перезапустите локальную пару.'end
  if s.connected~='1'then return 'Ожидание второго экземпляра на 127.0.0.1…'end
  local a=mask%2==1 and '✓'or'—';local b=mask>=2 and '✓'or'—'
  local plane=s.guest_aircraft or '0'
  local aircraft=plane=='23'and'F-14D'or(plane=='0'and'не выбран'or('ID '..plane))
  if os.getenv('AC8_LOCAL_HANGAR')=='25201480'then
   local phases={['0']='Лобби: оба готовы → хост открывает ангар.',['3']='Загрузка и настройка штатного ангара…',['4']='Ангар: подтвердите готовность ещё раз.',['5']='Хост запускает миссию…',['6']='Миссия запущена на хосте.',['8']='Сессия остановлена.'}
   return (phases[s.phase]or'Ожидание этапа.')..'\nХост '..a..'   Гость '..b..' · Самолёт гостя: '..aircraft
  end
  return 'Связь установлена. Хост '..a..'   Гость '..b..'\nСамолёт гостя: '..aircraft..(self.pending and '\nПодтверждение…'or(mask==3 and '\nОба готовы. Игровой запуск ещё не подключён.'or'\nГость управляется из своего окна или панели.'))
 end
 return self
end
return M
