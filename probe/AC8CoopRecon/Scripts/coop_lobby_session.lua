-- Two-peer lobby; route adapter owns verified local menu transitions.
-- Wire phases: room=0, prepare=1, ack=2, commit=3, loading=4, flight=5, abort=6.
local M={}
function M.new(api,flight)
    local s={phase='idle',detail='Создайте лобби или присоединитесь к ведущему.',revision=1,mission=7,plane=23,ready_local=false,ready_peer=false,connected=false,launch=0,wire_phase=0,consent=false}
    local last_sequence,bound_session,bound_peer,transition_at,travelled=0,nil,nil,nil,false
    local function publish()
        local capable=api.route_supported(s.mission,s.plane)==true
        api.publish({revision=s.revision,ready_revision=s.ready_local and s.revision or 0,launch=s.launch,mission=s.mission,plane=s.plane,flags=(s.ready_local and 1 or 0)+(capable and 2 or 0),phase=s.wire_phase})
    end
    local function terminal(why)
        s.phase='stopped';s.wire_phase=6;s.ready_local=false;s.ready_peer=false;s.consent=false;s.detail=why
        if travelled then flight.stop(why)end
        publish();api.log('lobby_stopped',why);api.report()
    end
    function s.configure(role,peer)
        assert(s.phase=='idle','Лобби уже открыто.')
        assert(role=='host'or role=='guest','Неверная роль.')
        assert(type(peer)=='string'and #peer==17 and peer:match('^[1-9]%d+$'),'Нужен SteamID64: 17 цифр.')
        api.configure(role,peer);s.role=role;s.peer=peer;s.phase='room';publish();api.connect()
        s.detail=role=='host'and'Лобби создано. Ожидание друга.'or'Подключение к лобби ведущего.'
    end
    function s.select(mission,plane)
        assert(s.role=='host'and s.phase=='room','Параметры выбирает ведущий в лобби.')
        assert(mission==7 and plane==23,'Поддерживаются задание 6 и F-14D.')
        if mission~=s.mission or plane~=s.plane then
            assert(s.revision<4294967295,'Исчерпана версия выбора.')
            s.revision=s.revision+1;s.mission=mission;s.plane=plane;s.ready_local=false;s.ready_peer=false;publish()
        end
        api.log('lobby_selection','mission6_f14d')
    end
    function s.ready()
        assert(s.phase=='room'and s.connected,'Дождитесь подключения друга.')
        s.ready_local=not s.ready_local;s.consent=s.ready_local;publish();api.log('lobby_ready',s.ready_local)
    end
    function s.can_start()
        return s.role=='host'and s.phase=='room'and s.connected and s.peer_phase==0 and s.ready_local and s.ready_peer and s.peer_capable and api.route_supported(s.mission,s.plane)==true
    end
    function s.start()
        assert(s.can_start(),'Для старта нужны оба готовых участника и проверенный маршрут задания.')
        assert(s.launch<4294967295,'Исчерпан номер запуска.')
        s.launch=s.launch+1;s.phase='prepare';s.wire_phase=1;transition_at=api.now();publish();api.log('lobby_prepare',s.launch)
    end
    function s.stop()terminal('Лобби остановлено. Для нового опыта перезапустите игру.');api.disconnect()end
    function s.reset()
        assert(not travelled,'После начала загрузки нужен перезапуск игры.')
        if s.phase~='idle'then s.wire_phase=6;s.ready_local=false;publish();api.disconnect()end
        if api.reset then api.reset()end
        if flight.reset_configuration then flight.reset_configuration()end
        last_sequence,bound_session,bound_peer,transition_at=0,nil,nil,nil
        s.phase='idle';s.role=nil;s.peer=nil;s.ready_local=false;s.ready_peer=false;s.connected=false
        s.launch=0;s.wire_phase=0;s.consent=false;s.peer_phase=nil;s.peer_capable=false
        s.detail='Введите SteamID64 и выберите создание или подключение.'
    end
    function s.report()api.report()end
    local function travel()
        assert(not travelled and s.consent and s.ready_local,'Нет локальной готовности для загрузки.')
        assert(api.route_supported(s.mission,s.plane)==true,'Маршрут запуска недоступен.')
        travelled=true;s.phase='loading';transition_at=api.now()
        api.launch(s.mission,s.plane,s.launch)
        s.wire_phase=4;publish()
        flight.ready();api.log('lobby_local_launch',s.launch)
    end
    local function update()
        if s.phase=='idle'or s.phase=='stopped'then return end
        api.pump();local p=api.receive()
        local fresh=p and p.connected and p.age_ms>=0 and p.age_ms<=3000 and p.sequence>0
        s.connected=fresh==true
        if not fresh then
            s.ready_peer=false
            if bound_session then terminal('Связь с участником потеряна; запуск отменён.');return end
            s.detail='Ожидание подключения второго участника.';return
        end
        if bound_session and(p.session~=bound_session or p.peer_session~=bound_peer)then terminal('Сессия участника изменилась; запуск отменён.');return end
        bound_session=p.session;bound_peer=p.peer_session
        assert(p.mission==7 and p.plane==23,'Неподдерживаемые параметры лобби.')
        assert(p.sequence>=last_sequence,'Последовательность лобби откатилась.')
        local advanced=p.sequence>last_sequence;last_sequence=p.sequence
        if p.phase==6 then terminal('Второй участник остановил лобби.');return end
        if s.role=='guest'and p.revision~=s.revision then
            assert(s.phase=='room'and p.revision>s.revision and p.phase==0,'Выбор изменился во время запуска.')
            s.revision=p.revision;s.ready_local=false;s.consent=false;publish()
        end
        s.ready_peer=p.revision==s.revision and p.ready_revision==s.revision and p.flags%2==1
        s.peer_capable=p.flags>=2
        s.peer_phase=p.phase
        if s.phase=='room'then
            s.detail='Вы: '..(s.ready_local and'готов'or'не готов')..' | Друг: '..(s.ready_peer and'готов'or'не готов')..' | Задание 6 · F-14D'
            if s.role=='guest'and p.phase==1 and advanced then
                assert(s.ready_local and s.ready_peer and s.consent and s.peer_capable,'Запуск получен без готовности обоих.')
                assert(p.launch>s.launch and api.route_supported(s.mission,s.plane)==true,'Маршрут запуска не подтверждён.')
                s.launch=p.launch;s.phase='ack';s.wire_phase=2;transition_at=api.now();publish();api.log('lobby_start_ack',s.launch)
            end
        elseif s.phase=='prepare'then
            if not s.ready_peer or not s.peer_capable then terminal('Готовность друга снята; запуск отменён.');return end
            if advanced and p.phase==2 and p.revision==s.revision and p.launch==s.launch then
                s.phase='commit';s.wire_phase=3;transition_at=api.now();publish();api.log('lobby_start_commit',s.launch)
            end
        elseif s.phase=='ack'then
            if not s.ready_peer or not s.peer_capable then terminal('Готовность ведущего снята; запуск отменён.');return end
            if advanced and p.phase==3 and p.revision==s.revision and p.launch==s.launch then
                s.wire_phase=4;publish();travel()
            end
        elseif s.phase=='commit'then
            if not s.ready_peer or not s.peer_capable then terminal('Готовность друга снята; запуск отменён.');return end
            if advanced and p.phase==4 and p.revision==s.revision and p.launch==s.launch and s.ready_peer and s.peer_capable then travel()end
        end
        if s.phase=='loading'then
            api.route_update()
            local supported=api.flight_supported()
            if supported then s.phase='flight';s.wire_phase=5;publish()end
            flight.update();s.detail='Общий запуск: '..flight.detail
        elseif s.phase=='flight'then flight.update();s.detail=flight.detail end
        if transition_at and s.phase~='flight'and api.now()-transition_at>(s.phase=='loading'and 600 or 15)then terminal('Время общего запуска истекло.');return end
    end
    function s.update()
        local ok,err=pcall(update)
        if not ok then terminal('Ошибка лобби: '..tostring(err));api.log('lobby_error',err)end
    end
    return s
end
return M
