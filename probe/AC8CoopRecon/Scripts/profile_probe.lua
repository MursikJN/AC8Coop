-- Bounded read-only profile discovery and 60 s original-player input recording.
-- Does not apply a profile, call weapon functions, or change aircraft settings.
return function(output_dir, stamp)
    local s=assert(_G.AC8ManualControl,"Manual state absent")
    if _G.AC8ProfileRecording then
        assert(type(_G.AC8ProfileRecording.stop)=="function","Older recording still active; wait for completion")
        _G.AC8ProfileRecording.stop("restarted_by_F8")
    end
    assert(s.restore("profile_capture"),"Restore incomplete")
    local function valid(o) return o and o:IsValid() end
    assert(valid(s.player) and valid(s.pc),"Player unavailable")
    local function label(o) return valid(o) and o:GetFullName() or "invalid" end
    local function clean(v) return tostring(v):gsub("[\r\n\t]"," ") end
    local path=output_dir.."/player-profile-"..stamp..".tsv"
    local file=assert(io.open(path,"w"))
    local function row(kind,owner,field,value)
        file:write(clean(kind),"\t",clean(owner),"\t",clean(field),"\t",clean(value),"\n")
    end
    local scalars={BoolProperty=true,IntProperty=true,Int8Property=true,Int16Property=true,
        Int64Property=true,UInt16Property=true,UInt32Property=true,UInt64Property=true,
        FloatProperty=true,DoubleProperty=true,ByteProperty=true,EnumProperty=true}
    local queue,seen={},{}
    local function enqueue(o,depth)
        if not valid(o) or seen[o:GetAddress()] then return end
        if #queue>=40 then row("limit",label(o),"objects",40); return end
        seen[o:GetAddress()]=true; queue[#queue+1]={object=o,depth=depth}
    end
    local function follow(n)
        n=n:lower()
        for _,part in ipairs({"flight","movement","parameter","setting","upgrade","camera","firecontrol","aimodule"}) do
            if n:find(part,1,true) then return true end
        end
        return false
    end
    local native={InputPitch=true,InputRoll=true,InputYaw=true,AIFlightEngineTick=true,
        FireOneShotWeapon=true,FireOneShotWeaponWithTargetTracking=true,
        FireContinuousShotWeapon=true,StopFireContinuousShotWeapon=true}
    local ok,err=pcall(function()
        row("meta","profile","build",25201480)
        row("meta","profile","status","discovery_only_not_portable_or_complete")
        row("meta","profile","player",label(s.player))
        row("meta","profile","view_target",label(s.pc:GetViewTarget()))
        enqueue(s.player,0); enqueue(s.pc.PlayerInput,0); enqueue(s.pc.PlayerCameraManager,0)
        for _,slot in ipairs(s.slots) do enqueue(slot.plane,0) end
        local cursor=1
        while cursor<=#queue do
            local entry=queue[cursor]; cursor=cursor+1
            local obj=entry.object; local owner=label(obj)
            row("object",owner,"address",string.format("0x%X",obj:GetAddress()))
            local class,depth=obj:GetClass(),0
            while valid(class) and depth<14 do
                depth=depth+1
                local count=0
                class:ForEachProperty(function(p)
                    count=count+1
                    if count>384 then return true end
                    local n=p:GetFName():ToString(); local t=p:GetClass():GetFName():ToString()
                    row("schema",label(class),n,t.." offset="..p:GetOffset_Internal())
                    if not (scalars[t] or t=="NameProperty" or t=="StrProperty" or t=="ObjectProperty") then return end
                    local read_ok,value=pcall(function() return obj[n] end)
                    if not read_ok then row("read_error",owner,n,value); return end
                    if t=="ObjectProperty" then
                        row("reference",owner,n,label(value))
                        if entry.depth<2 and follow(n) then enqueue(value,entry.depth+1) end
                    elseif t=="NameProperty" or t=="StrProperty" then
                        local text_ok,rendered=pcall(function() return type(value)=="string" and value or value:ToString() end)
                        row(text_ok and "value" or "read_error",owner,n,rendered)
                    else row("value",owner,n,value) end
                end)
                if count>384 then row("limit",owner,label(class),"property_cap=384") end
                local funcs=0
                class:ForEachFunction(function(fn)
                    funcs=funcs+1
                    if funcs>384 then return true end
                    local n=fn:GetFName():ToString()
                    if native[n] or follow(n) or n:find("Input",1,true) then
                        row("function",label(class),n,string.format("0x%X",fn:GetAddress()))
                        local args=0
                        fn:ForEachProperty(function(p)
                            args=args+1; if args>32 then return true end
                            row("function_field",label(fn),p:GetFName():ToString(),p:GetClass():GetFName():ToString().." offset="..p:GetOffset_Internal())
                        end)
                    end
                end)
                if funcs>384 then row("limit",owner,label(class),"function_cap=384") end
                class=class:GetSuperStruct()
            end
            if depth>=14 then row("limit",owner,"inheritance",14) end
        end
        row("meta","profile","object_count",#queue)
    end)
    file:close()
    if not ok then error(err) end

    local sample_path=output_dir.."/player-input-"..stamp..".tsv"
    local function append(values)
        local f=assert(io.open(sample_path,"a")); f:write(table.concat(values,"\t"),"\n"); f:close()
    end
    local axes={"InputRoll","InputPitch","InputLeftYaw","InputRightYaw","InputThrottle","InputBrake"}
    local key_names={"Gamepad_LeftX","Gamepad_LeftY","Gamepad_RightX","Gamepad_RightY","Gamepad_LeftTriggerAxis","Gamepad_RightTriggerAxis"}
    local keys={}; for _,n in ipairs(key_names) do keys[#keys+1]={KeyName=FName(n)} end
    local header={"sample","scheduled_delay_ms"}
    for _,n in ipairs(key_names) do header[#header+1]=n end
    for _,n in ipairs(axes) do header[#header+1]=n end
    for _,n in ipairs({"speed_field","x","y","z","pitch","yaw","roll","cam_x","cam_y","cam_z","cam_fov","camera_distance"}) do header[#header+1]=n end
    append(header)
    local mgr=s.pc.PlayerCameraManager
    local can_camera=valid(mgr) and valid(StaticFindObject("/Script/Engine.PlayerCameraManager:GetCameraLocation"))
        and valid(StaticFindObject("/Script/Engine.PlayerCameraManager:GetFOVAngle"))
    local original_busy=s.busy
    local token={}; _G.AC8ProfileRecording=token; s.busy=true
    local function finish(reason)
        if _G.AC8ProfileRecording~=token then return end
        _G.AC8ProfileRecording=nil; s.busy=original_busy
        print("[AC8Profile] Finished "..stamp.." reason="..reason.."\n")
    end
    token.stop=finish
    local schedule_ok,schedule_error=pcall(function()
        ExecuteInGameThreadWithDelay(62000,function() finish("watchdog") end)
        for i=0,1200 do
            local index=i
            ExecuteInGameThreadWithDelay(i*50,function()
                if _G.AC8ProfileRecording~=token then return end
                local sample_ok,sample_error=pcall(function()
                    assert(valid(s.player) and valid(s.pc) and s.player:GetWorld():GetAddress()==s.world_id,"World changed")
                    assert(s.pc.Pawn:GetAddress()==s.player:GetAddress(),"Player changed")
                    local v={tostring(index),tostring(index*50)}
                    for _,key in ipairs(keys) do v[#v+1]=clean(s.pc:GetInputAnalogKeyState(key)) end
                    for _,n in ipairs(axes) do v[#v+1]=clean(s.player[n]) end
                    local p=s.player:K2_GetActorLocation(); local r=s.player:K2_GetActorRotation()
                    for _,value in ipairs({s.player.Speed,p.X,p.Y,p.Z,r.pitch or r.Pitch or "NA",r.Yaw,r.Roll}) do v[#v+1]=clean(value) end
                    if can_camera then
                        local c=mgr:GetCameraLocation()
                        for _,value in ipairs({c.X,c.Y,c.Z,mgr:GetFOVAngle(),math.sqrt((c.X-p.X)^2+(c.Y-p.Y)^2+(c.Z-p.Z)^2)}) do v[#v+1]=clean(value) end
                    else for _=1,5 do v[#v+1]="NA" end end
                    append(v)
                end)
                if not sample_ok then
                    print("[AC8Profile] Sample error "..clean(sample_error).."\n"); finish("sample_error")
                elseif index==1200 then finish("complete") end
            end)
        end
    end)
    if not schedule_ok then finish("schedule_error"); error(schedule_error) end
    print("[AC8Profile] Recording original player for 60 seconds; F6/F7 temporarily inactive.\n")
end
