-- Session-specific file bridge to the native authenticated lobby channel.
return function(base,flight,root,output,route)
    local dll=assert(os.getenv('AC8_COOP_LOBBY_DLL'))
    local start=assert(package.loadlib(dll,'luaopen_ac8_lobby_start'))
    local pump=assert(package.loadlib(dll,'luaopen_ac8_lobby_pump'))
    local reset=assert(package.loadlib(dll,'luaopen_ac8_lobby_reset'))
    local stop=assert(package.loadlib(dll,'luaopen_ac8_lobby_stop'))
    local api={now=base.now,log=base.log,report=base.report,flight_supported=base.flight_supported}
    local previous
    function api.publish(frame)
        local fields={'revision','ready_revision','launch','mission','plane','flags','phase'}
        local text='format\tac8-lobby-command-v1\n'
        for _,k in ipairs(fields)do
            local v=frame[k];assert(type(v)=='number'and v>=0 and v<=4294967295 and v%1==0,'Invalid lobby command')
            text=text..k..'\t'..string.format('%.0f',v)..'\n'
        end
        if text==previous then return end
        local path=output..'/lobby-command.tsv'
        local f=assert(io.open(path..'.tmp','w'));assert(f:write(text));assert(f:close())
        local old=io.open(path,'r');if old then old:close();assert(os.remove(path))end
        assert(os.rename(path..'.tmp',path));previous=text
    end
    function api.configure(role,peer)flight.configure(role,peer)end
    function api.connect()start()end
    function api.pump()pump()end
    function api.disconnect()stop()end
    function api.reset()reset();previous=nil end
    function api.receive()
        local f=io.open(output..'/lobby-status.tsv','r');if not f then return nil end
        local text=f:read(8193);f:close();assert(text and #text<=8192,'Oversized lobby status')
        local fields={};for line in text:gmatch('[^\r\n]+')do
            local k,v=line:match('^([^\t]+)\t(.*)$');if k then assert(not fields[k],'Duplicate lobby status field');fields[k]=v end
        end
        assert(fields.format=='ac8-lobby-status-v1','Lobby status version mismatch')
        if fields.connected~='1'then return {connected=false}end
        local result={connected=true,session=fields.session,peer_session=fields.peer_session}
        for _,k in ipairs({'sequence','revision','ready_revision','launch','mission','plane','flags','phase'})do result[k]=assert(tonumber(fields[k]),'Missing '..k)end
        result.age_ms=assert(tonumber(fields.peer_age_ms));return result
    end
    function api.route_supported(mission,plane)return route.supported(mission,plane)end
    function api.launch(mission,plane,id)route.begin(mission,plane,id)end
    function api.route_update()route.update()end
    return api
end
