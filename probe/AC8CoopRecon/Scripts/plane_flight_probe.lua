-- F8 preflight; reviewed F7 creates one owned local network copy for up to 15 seconds.
-- F9 requests owned cleanup. Native code owns lifetime, readiness and absolute deadline.
return function(output_dir, stamp)
    assert(os.getenv("AC8_COOP_RECON")=="1", "research launcher absent")
    local dll="D:/projects/unreal-mod-tools/profiles/ac8-build25201480/runtime/ac8_plane_flight_probe_r4.dll"
    local preflight=assert(package.loadlib(dll,"luaopen_ac8_flight_preflight"))
    local run=assert(package.loadlib(dll,"luaopen_ac8_flight_run"))
    local cleanup=assert(package.loadlib(dll,"luaopen_ac8_flight_cleanup"))
    local tick=assert(package.loadlib(dll,"luaopen_ac8_flight_tick"))
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
        local class=pawn:GetClass()
        assert(valid(class),"plane class missing")
        local function getter(name, struct)
            local fn=StaticFindObject("/Script/Engine.Actor:"..name)
            assert(valid(fn),"missing getter "..name)
            local count=0
            fn:ForEachProperty(function(field)
                count=count+1
                assert(count==1 and field:GetFName():ToString()=="ReturnValue","unexpected getter parameters")
                assert(field:GetClass():GetFName():ToString()=="StructProperty","unexpected return type")
                assert(field:GetStruct():GetFullName()=="ScriptStruct /Script/CoreUObject."..struct,"unexpected struct")
            end)
            assert(count==1,"missing getter return")
        end
        getter("K2_GetActorLocation","Vector"); getter("K2_GetActorRotation","Rotator")
        local location=pawn:K2_GetActorLocation(); local rotation=pawn:K2_GetActorRotation()
        local pose={{"location_x",location.X},{"location_y",location.Y},{"location_z",location.Z},
                    {"rotation_pitch",rotation.pitch},{"rotation_yaw",rotation.Yaw},{"rotation_roll",rotation.Roll}}
        local rows={{"format","ac8-plane-flight-v1"},{"stamp",active_stamp},{"created_unix",tostring(os.time())},
                    {"world",addr(world)},{"controller",addr(pc)},{"pawn",addr(pawn)},
                    {"plane_class",addr(class)},
                    {"pc_pawn_offset",offset(pc,"Pawn")},{"plane_controller_offset",offset(pawn,"Controller")}}
        for _,row in ipairs(pose) do
            local value=row[2]
            assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"invalid pose field "..row[1])
            rows[#rows+1]={row[1],string.format("%.17g",value)}
        end
        assert(addr(pc.Pawn)==addr(pawn) and addr(pawn:GetWorld())==addr(world),"player changed")
        local path=output_dir.."/plane-flight-request.tsv"
        local f=assert(io.open(path..".tmp","w"))
        for _,r in ipairs(rows) do f:write(r[1],"\t",r[2],"\n") end
        f:close()
        local old=io.open(path,"r")
        if old then old:close(); assert(os.remove(path)) end
        assert(os.rename(path..".tmp",path))
    end
    local last_status
    local function show_status()
        local f=assert(io.open(output_dir.."/plane-flight-status.tsv","r"))
        local text=f:read(16385); f:close()
        assert(text and #text<=16384,"invalid native status")
        local fields={}
        for line in text:gmatch("[^\r\n]+") do
            local k,v=line:match("^([^\t]+)\t(.*)$")
            if k then fields[k]=v end
        end
        local line="[AC8PlaneFlight] "..tostring(fields.status).." reason="..tostring(fields.reason)
        if line~=last_status then print(line.."\n"); last_status=line end
        return fields
    end
    local old=_G.AC8PlaneFlightLifecycle
    if old and old.attempted then
        -- Reload never reallocates or leaves the old loop running.
        old.stop(); return
    end
    local state={stamp=stamp,attempted=false,busy=false,active=false,ticks=0}
    local function stop()
        state.active=false -- stop producer before native cleanup, even if it fails
        cleanup(); show_status() -- no fresh player lookup required for cleanup
    end
    state.stop=stop
    local function step()
        if not state.active or _G.AC8PlaneFlightLifecycle~=state then return end
        local ok,err=pcall(function()
            assert(state.ticks<300,"tick callback bound reached")
            state.ticks=state.ticks+1
            tick()
            local status=show_status()
            if status.status~="active" then stop(); return end
            ExecuteInGameThreadWithDelay(50,step)
        end)
        if not ok then
            state.active=false
            print("[AC8PlaneFlight] tick_error "..tostring(err).."\n")
            local stopped,why=pcall(stop)
            if not stopped then print("[AC8PlaneFlight] cleanup_error "..tostring(why).."\n") end
        end
    end
    local function attempt()
        assert(not state.attempted,"one attempt only")
        request(state.stamp) -- refresh current world/pawn before crossing native boundary
        state.attempted=true -- conservative even if native gate refuses
        -- Install fallback before crossing the mutating native boundary.
        ExecuteInGameThreadWithDelay(15000,function()
            local ok,err=pcall(stop)
            if not ok then print("[AC8PlaneFlight] timeout_cleanup_error "..tostring(err).."\n") end
        end)
        run()
        state.active=show_status().status=="active"
        if state.active then ExecuteInGameThreadWithDelay(50,step) end
        for _,delay in ipairs({16000,18000}) do
            ExecuteInGameThreadWithDelay(delay,function()
                local ok,err=pcall(stop)
                if not ok then print("[AC8PlaneFlight] verify_error "..tostring(err).."\n") end
            end)
        end
    end
    state.run=attempt
    request(stamp); preflight()
    local status=show_status()
    state.ready=(status.status=="ready" and status.stamp==stamp)
    _G.AC8PlaneFlightLifecycle=state
    if not _G.AC8PlaneFlightKeysInstalled then
        local function dispatch(kind)
            ExecuteInGameThread(function()
                local current=_G.AC8PlaneFlightLifecycle
                if not current or current.busy then return end
                current.busy=true
                local ok,err=pcall(function()
                    if kind=="run" then assert(current.ready,"preflight not ready"); current.run()
                    else current.stop() end
                end)
                current.busy=false
                if not ok then
                    print("[AC8PlaneFlight] action_error "..tostring(err).."\n")
                    if current.attempted then pcall(current.stop) end
                end
            end)
        end
        RegisterKeyBind(Key.F7,function() dispatch("run") end)
        RegisterKeyBind(Key.F9,function() dispatch("verify") end)
        _G.AC8PlaneFlightKeysInstalled=true
    end
    print("[AC8PlaneFlight] F8 preflight completed. F7 remains subject to reviewed native token.\n")
end
