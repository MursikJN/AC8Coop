-- UI-independent session controller. Native R8 retains allocation, lifetime and peer gates.
local M={}
function M.new(api)
    local continuous=api.continuous==true
    local revision=continuous and "r10"or"r8"
    local self={phase='idle',detail='Выберите роль и SteamID64 второго участника.',consent=false,consumed=false,started=false}
    local started_at,last_sequence,lifecycle,cleanup_at,verifications=0,nil,nil,nil,0
    function self.configure(role,peer)
        assert(self.phase=='idle','Настройки уже зафиксированы; начните новый процесс игры.')
        assert(role=='host'or role=='guest','Выберите роль.')
        assert(type(peer)=='string'and #peer==17 and peer:match('^[1-9]%d+$'),'Нужен SteamID64 другого участника: 17 цифр.')
        api.configure(role,peer)
        self.role=role;self.peer=peer;self.phase='configured'
        self.detail='Задание 6, F-14D, одинаковое оснащение. После дозаправки нажмите «Готов». '
        api.log('configured',role)
    end
    function self.reset_configuration()
        assert(not self.consumed and not lifecycle,'После начала полёта нужен перезапуск игры.')
        self.phase='idle';self.role=nil;self.peer=nil;self.consent=false
    end
    function self.ready()
        assert(self.phase=='configured','Сначала создайте сессию или подключитесь.')
        self.consent=true;self.phase='waiting_flight';self.detail='Ожидание активного F-14D в задании 6.'
        api.log('ready_intent','mission6_f14d')
    end
    function self.stop(reason)
        self.consent=false
        if lifecycle then lifecycle.stop()end
        self.phase='stopped';self.detail=reason or 'Остановлено. Для нового опыта перезапустите игру.'
        cleanup_at=api.now();api.log('stop',self.detail)
    end
    function self.report()api.report();api.log('report_requested','local_only')end
    local function update()
        if self.phase=='waiting_flight'then
            local supported,why=api.flight_supported()
            if not supported then self.detail=why or 'Ожидание нужного задания и самолёта.';return end
            lifecycle=api.preflight();started_at=api.now();self.phase='waiting_peer';self.detail='Проверки выполнены. Ожидание второго участника.'
            api.log('preflight',lifecycle.stamp)
        end
        if self.phase=='waiting_peer'then
            if api.now()-started_at>=90 then self.stop('Второй участник не готов: время подготовки истекло. Перезапустите игру.');return end
            local n,c=api.status()
            assert(n.status=='ready'and n.attempted=='0'and n.module_revision==revision and (not continuous or n.lifetime_ms=='0')and n.native_detail=='preflight_verified'and n.dispatcher_verified=='1'and n.stamp==lifecycle.stamp,'Нативная проверка не пройдена: '..tostring(n.native_detail or n.reason))
            if c.stopped=='1'then self.stop('Сессия остановлена: '..tostring(c.detail));return end
            local fresh=c.revision==revision and c.stamp==lifecycle.stamp and c.transport_ready=='1'and c.peer_ready=='1'and c.has_peer=='1'and c.local_armed=='0'and tonumber(c.epoch)and tonumber(c.epoch)>0 and tonumber(c.peer_age_ms)and tonumber(c.peer_age_ms)<=1000
            if not fresh then last_sequence=nil;self.detail='Ожидание связи и одинакового оснащения: '..tostring(c.detail or 'подключение');return end
            local sequence=tonumber(c.peer_sequence)
            if not sequence or sequence<=0 then last_sequence=nil;return end
            if not last_sequence then last_sequence=sequence;return end
            if sequence<=last_sequence then return end
            assert(self.consent and not self.consumed,'Нет согласия на запуск.')
            api.arm(lifecycle.stamp) -- same reviewed native contract; no bypass of the native gates
            self.consumed=true
            lifecycle.run() -- installs the existing watchdog before entering native arm/create
            self.phase='running';self.detail=continuous and 'Ожидание готовности второго участника.'or'Ожидание готовности второго участника; полёт до 15 секунд.'
            api.log('automatic_arm',lifecycle.stamp)
        end
        if self.phase=='running'then
            local n=api.status()
            if n.status=='active'then self.started=true;self.detail=continuous and 'Самолёт друга отображается. F9 — остановить.'or'Совместный полёт: состояние второго игрока. До 15 секунд.'
            elseif n.status=='waiting_peer'then self.detail='Второй участник ещё не разрешил запуск.'
            else
                self.stop('Опыт завершён: '..tostring(n.reason or n.status));self.report()
            end
        end
        if self.phase=='stopped'and lifecycle and cleanup_at and verifications<2 and api.now()-cleanup_at>=verifications+1 then
            lifecycle.stop();verifications=verifications+1
            local n=api.status()
            if n.status=='retired'then self.detail='Все собственные объекты удалены. Отчёт сохранён; для повтора перезапустите игру.'
            elseif n.status=='quarantine'then self.detail='Удаление не подтверждено. Закройте игру обычным выходом; журналы сохранятся.'end
        end
    end
    function self.update()
        local ok,err=pcall(update)
        if not ok then
            self.consent=false
            if lifecycle then pcall(lifecycle.stop)end
            self.phase='error';self.detail=tostring(err);api.log('error',self.detail);api.report()
        end
    end
    return self
end
return M
