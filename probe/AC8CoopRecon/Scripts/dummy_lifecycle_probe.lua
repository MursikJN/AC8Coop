-- F8 stages a native dummy-controller lifecycle check. No retained UObject wrappers.
-- F7 invokes ONE native-owned spawn/destroy attempt, only after its reviewed token.
-- F9 and delayed callbacks only verify/finish cleanup of the native-owned object.
return function(output_dir, stamp)
    assert(os.getenv("AC8_COOP_DUMMY_PROBE")=="25201480", "dummy probe launcher gate absent")
    local dll=assert(os.getenv("AC8_COOP_DUMMY_PROBE_DLL"), "dummy DLL absent")
    local preflight=assert(package.loadlib(dll,"luaopen_ac8_dummy_preflight"))
    local run=assert(package.loadlib(dll,"luaopen_ac8_dummy_run"))
    local verify=assert(package.loadlib(dll,"luaopen_ac8_dummy_verify"))
    local function valid(o) return o and o:IsValid() end
    local function addr(o) assert(valid(o),"invalid object"); return string.format("0x%x",o:GetAddress()) end
    local function offset(o,name)
        local c=o:GetClass()
        for _=1,20 do
            if not valid(c) then break end
            local found,count=nil,0
            c:ForEachProperty(function(p)
                count=count+1; assert(count<=512,"property cap")
                if p:GetFName():ToString()==name then
                    assert(p:GetClass():GetFName():ToString()=="ObjectProperty","pointer property type")
                    found=p:GetOffset_Internal(); return true
                end
            end)
            if found then
                assert(found>=0x28 and found<=0x2000 and found%8==0,"pointer bounds")
                return string.format("0x%x",found)
            end
            c=c:GetSuperStruct()
        end
        error("missing property "..name)
    end
    local function request(active_stamp)
        assert(active_stamp:match("^[%w_-]+$") and #active_stamp<=64,"invalid stamp")
        local candidates={}
        local controllers=FindAllOf("LivePlayerController") or {}
        assert(#controllers<=8,"controller cap")
        for _,pc in ipairs(controllers) do
            if valid(pc) then
                local pawn=pc.Pawn
                if valid(pawn) and pawn:IsA("/Script/Live.LivePlayerPlane") then
                    candidates[#candidates+1]={pc=pc,pawn=pawn}
                end
            end
        end
        assert(#candidates==1,"need one local player")
        local pc,pawn=candidates[1].pc,candidates[1].pawn
        local world=pc:GetWorld()
        assert(addr(pawn:GetWorld())==addr(world) and addr(pawn.Controller)==addr(pc),"world/controller mismatch")
        assert(world:GetFullName():find("Mission007",1,true),"mission6 required")
        assert(pawn.bIsActivated==true and pawn.bIsIGCActor==false,"active flight required")
        assert(pawn:GetClass():GetFullName():find("/PP0023_f14d/",1,true),"loaded F14D required")
        local class=StaticFindObject("/Script/Live.LiveNetworkDummyController")
        local cdo=StaticFindObject("/Script/Live.Default__LiveNetworkDummyController")
        assert(valid(class) and class:GetFullName()=="Class /Script/Live.LiveNetworkDummyController","dummy class missing")
        assert(valid(cdo) and addr(cdo:GetClass())==addr(class),"dummy CDO class mismatch")
        local rows={{"format","ac8-dummy-v1"},{"stamp",active_stamp},{"created_unix",tostring(os.time())},
                    {"world",addr(world)},{"controller",addr(pc)},{"pawn",addr(pawn)},
                    {"dummy_class",addr(class)},{"dummy_cdo",addr(cdo)},
                    {"pc_pawn_offset",offset(pc,"Pawn")},{"plane_controller_offset",offset(pawn,"Controller")}}
        assert(addr(pc.Pawn)==addr(pawn) and addr(pawn:GetWorld())==addr(world),"player changed")
        local path=output_dir.."/dummy-request.tsv"
        local f=assert(io.open(path..".tmp","w"))
        for _,r in ipairs(rows) do f:write(r[1],"\t",r[2],"\n") end
        f:close()
        local old=io.open(path,"r")
        if old then old:close(); assert(os.remove(path)) end
        assert(os.rename(path..".tmp",path))
    end
    local function show_status()
        local f=assert(io.open(output_dir.."/dummy-status.tsv","r"))
        local text=f:read(16385); f:close()
        assert(text and #text<=16384,"invalid native status")
        local fields={}
        for line in text:gmatch("[^\r\n]+") do
            local k,v=line:match("^([^\t]+)\t(.*)$")
            if k then fields[k]=v end
        end
        print("[AC8Dummy] "..tostring(fields.status).." reason="..tostring(fields.reason).."\n")
        return fields
    end
    local old=_G.AC8DummyLifecycle
    if old and old.attempted then
        -- A second F8 must never reset the one-attempt lifetime guard.
        verify(); show_status(); return
    end
    local state={stamp=stamp,attempted=false,busy=false}
    local function verify_owned()
        verify(); show_status() -- deliberately no fresh player lookup for cleanup
    end
    local function attempt()
        assert(not state.attempted,"one attempt only")
        request(state.stamp) -- refresh current world/pawn before crossing native boundary
        state.attempted=true -- conservative even if native gate refuses
        run(); show_status()
        for _,delay in ipairs({250,1000,3000}) do
            ExecuteInGameThreadWithDelay(delay,function()
                local ok,err=pcall(verify_owned)
                if not ok then print("[AC8Dummy] verify_error "..tostring(err).."\n") end
            end)
        end
    end
    state.run=attempt; state.verify=verify_owned
    request(stamp); preflight()
    local status=show_status()
    state.ready=(status.status=="ready" and status.stamp==stamp)
    _G.AC8DummyLifecycle=state
    if not _G.AC8DummyKeysInstalled then
        local function dispatch(kind)
            ExecuteInGameThread(function()
                local current=_G.AC8DummyLifecycle
                if not current or current.busy then return end
                current.busy=true
                local ok,err=pcall(function()
                    if kind=="run" then assert(current.ready,"preflight not ready"); current.run()
                    else current.verify() end
                end)
                current.busy=false
                if not ok then print("[AC8Dummy] action_error "..tostring(err).."\n") end
            end)
        end
        RegisterKeyBind(Key.F7,function() dispatch("run") end)
        RegisterKeyBind(Key.F9,function() dispatch("verify") end)
        _G.AC8DummyKeysInstalled=true
    end
    print("[AC8Dummy] F8 preflight completed. F7 remains subject to reviewed native token.\n")
end
