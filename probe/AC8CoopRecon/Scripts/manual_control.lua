-- AC8 build 25201480 only. F8 installs; F6 selects; F7 takes control; F9 restores.
-- File-level validation token is produced by validate_manual_layout.py for this live snapshot.
return function(output_dir, stamp)
    local version="0.5.3"
    local previous=_G.AC8ManualControl
    if previous then
        if previous.version==version then
            previous.restore("F8")
            print("[AC8Manual] Already installed; F8 requested restoration.\n")
            return
        end
        assert(previous.restore("module_upgrade"),"Cannot upgrade before complete restoration")
        previous.busy=true -- Old registered hotkeys remain inert; they cannot acquire an aircraft.
        _G.AC8ManualControl=nil
    end
    assert(os.getenv("AC8_COOP_MANUAL") == "25201480", "Manual experiment not enabled by launcher")
    assert(EngineTickAvailable, "Engine tick unavailable")
    local s = {version=version,selection=1, active=nil, generation=0, busy=false, slots={}}
    local logfile = output_dir .. "/manual-control-" .. stamp .. ".tsv"
    local function log(event, detail)
        local line = os.date("%H:%M:%S") .. "\t" .. event .. "\t" .. tostring(detail or ""):gsub("[\r\n\t]"," ")
        print("[AC8Manual] " .. line .. "\n")
        local f = io.open(logfile,"a")
        if f then f:write(line,"\n"); f:close() end
    end
    local function valid(obj) return obj and obj:IsValid() end
    local function name(obj) return valid(obj) and obj:GetFullName() or "invalid" end
    local function finite(x) return type(x)=="number" and x==x and math.abs(x)<1e12 end
    local function read_name(obj,key) return obj[key]:ToString() end
    local function same_world(obj) return valid(obj) and obj:GetWorld():GetAddress()==s.world_id end
    local properties = {
        {"AC8ManualEnable","/Script/Live.LiveAIStateComponent",PropertyTypes.ByteProperty,0xD3},
        {"AC8ManualPitch","/Script/Live.LiveAIPlane",PropertyTypes.FloatProperty,0x2A8C},
        {"AC8ManualYaw","/Script/Live.LiveAIPlane",PropertyTypes.FloatProperty,0x2A90},
        {"AC8ManualRoll","/Script/Live.LiveAIPlane",PropertyTypes.FloatProperty,0x2A94},
        {"AC8ManualScale","/Script/Live.LiveAIPlane",PropertyTypes.FloatProperty,0x6C8},
    }
    local expected = {Joker2="Professor",Joker3="Pinkhead",Joker4="Noise"}
    for _, plane in ipairs(FindAllOf("BP_WOP1007_f18c_C") or {}) do
        if valid(plane) and name(plane):find("/Mission007/",1,true) and plane.bIsActivated
            and not plane.bIsIGCActor and not plane.bIsAnimationPlane then
            local id = read_name(plane,"ObjNameID"):match("^ContainerAllyCallsign_Name_(Joker%d)$")
            if expected[id] then
                assert(read_name(plane,"CallsignId")=="ContainerAllyCallsign_Name_"..expected[id],"Unexpected callsign")
                s.slots[#s.slots+1]={id=id,label=id.." / "..expected[id],plane=plane,component=plane.AIStateComponent}
            end
        end
    end
    assert(#s.slots==3,"Need all three mission wingmen after refuelling")
    table.sort(s.slots,function(a,b) return a.id<b.id end)
    assert(s.slots[1].id~=s.slots[2].id and s.slots[2].id~=s.slots[3].id,"Duplicate slot")
    s.world_id = s.slots[1].plane:GetWorld():GetAddress()
    local controllers={}
    for _, pc in ipairs(FindAllOf("LivePlayerController") or {}) do
        if same_world(pc) and valid(pc.Pawn) and pc.Pawn:IsA("/Script/Live.LivePlayerPlane") then controllers[#controllers+1]=pc end
    end
    assert(#controllers==1,"Need one current player controller")
    s.pc, s.player = controllers[1], controllers[1].Pawn
    assert(same_world(s.player) and not s.player.bIsIGCActor,"Player not in controllable mission")
    for _, item in ipairs(s.slots) do
        assert(same_world(item.plane) and valid(item.component),"Wingman world/component mismatch")
        assert(item.component.Owner:GetAddress()==item.plane:GetAddress(),"Wingman owner mismatch")
    end
    -- Export fresh instance addresses; no persistent instance addresses are embedded in this module.
    local a=assert(io.open(output_dir.."/manual-addresses-"..stamp..".tsv","w"))
    a:write("kind\tname\taddress\n")
    for _, item in ipairs(s.slots) do
        a:write("plane\t",item.id,"\t",string.format("0x%X",item.plane:GetAddress()),"\n")
        a:write("component\t",item.id,"\t",string.format("0x%X",item.component:GetAddress()),"\n")
    end
    for _, fnname in ipairs({"InputPitch","InputYaw","InputRoll","SetAIStateActive"}) do
        local fn=StaticFindObject("/Script/Live.LiveAIPlane:"..fnname)
        assert(valid(fn),"Native function missing: "..fnname)
        a:write("ufunction\t",fnname,"\t",string.format("0x%X",fn:GetAddress()),"\n")
    end
    a:close()
    if not previous and not _G.AC8ManualPropertiesRegistered then
        for _, p in ipairs(properties) do RegisterCustomProperty({Name=p[1],BelongsToClass=p[2],Type=p[3],OffsetInternal=p[4]}) end
    end
    _G.AC8ManualPropertiesRegistered=true
    local key_names={"Up","Down","Left","Right","NumPadFour","NumPadSix","Escape",
        "Gamepad_LeftX","Gamepad_LeftY","Gamepad_LeftShoulder","Gamepad_RightShoulder",
        "Gamepad_DPad_Up","Gamepad_DPad_Down","Gamepad_DPad_Left","Gamepad_DPad_Right"}
    local keys={}
    for _, key in ipairs(key_names) do
        keys[key]={KeyName=FName(key)}
        assert(type(s.pc:IsInputKeyDown(keys[key]))=="boolean","Raw key query unavailable")
    end
    for _,key in ipairs({"Gamepad_LeftX","Gamepad_LeftY"}) do
        assert(finite(s.pc:GetInputAnalogKeyState(keys[key])),"Analog input query unavailable")
    end
    local player_gates={"bEnableMovmentInput","bEnableWingInput","bEnableCameraInput","bEnableCameraViewChange",
        "bEnableWeaponInput","bEnableFlareInput","bEnableChangeTargetInput"}
    local player_axes={"InputPitch","InputRoll","InputLeftYaw","InputRightYaw","InputThrottle","InputBrake"}
    local ai_axes={"AC8ManualPitch","AC8ManualYaw","AC8ManualRoll"}
    local camera_class=StaticFindObject("/Script/Engine.CameraActor")
    assert(valid(camera_class),"CameraActor class unavailable")
    local mathlib=StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    assert(valid(mathlib),"Rotator constructor unavailable")
    local system=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local function notify(message)
        log("notice",message)
        if valid(system) then
            pcall(function() system:PrintString(s.player,message,true,false,{R=0.2,G=1,B=1,A=1},8,FName("AC8Manual")) end)
        end
    end
    local function camera_pose(plane)
        local p, forward=plane:K2_GetActorLocation(),plane:GetActorForwardVector()
        assert(finite(p.X) and finite(p.Y) and finite(p.Z) and finite(forward.X) and finite(forward.Y) and finite(forward.Z),"Invalid pose")
        -- Approximate the observed 2042..2256 unit player-camera distance.
        -- This does not reproduce the original camera's lag/roll/turn behavior.
        local pos={X=p.X-forward.X*2000,Y=p.Y-forward.Y*2000,Z=p.Z-forward.Z*2000+400}
        local dx,dy,dz=p.X-pos.X,p.Y-pos.Y,p.Z-pos.Z
        local h=math.sqrt(dx*dx+dy*dy)
        local length=math.sqrt(h*h+dz*dz)
        assert(length>1,"Invalid camera direction")
        -- Reflected Rotator field is lowercase 'pitch' in this game. Use the engine
        -- constructor's exact returned field names instead of handwritten table keys.
        local rot=mathlib:MakeRotator(0,math.deg(math.atan(dz,h)),math.deg(math.atan(dy,dx)))
        return pos,rot,{X=dx/length,Y=dy/length,Z=dz/length}
    end
    local function update_camera(active)
        local pos,rot,wanted=camera_pose(active.slot.plane)
        active.camera:K2_SetActorLocationAndRotation(pos,rot,false,{},false)
        local f=active.camera:GetActorForwardVector()
        assert(finite(f.X) and finite(f.Y) and finite(f.Z) and f.X*wanted.X+f.Y*wanted.Y+f.Z*wanted.Z>0.995,"Camera rotation mismatch")
    end
    local function sample(active,event)
        local p=active.slot.plane
        local r=p:K2_GetActorRotation()
        local v=p:K2_GetActorLocation()
        log(event,string.format("slot=%s flag=%s firePermission=%s writes=%d pitchInput=%.3f yawInput=%.3f rollInput=%.3f roll=%s yaw=%s xyz=%.1f,%.1f,%.1f",
            active.slot.id,tostring(active.slot.component.AC8ManualEnable),tostring(p.bPermissionToFire),active.writes,p.AC8ManualPitch,p.AC8ManualYaw,p.AC8ManualRoll,
            tostring(r.Roll),tostring(r.Yaw),v.X,v.Y,v.Z))
    end
    local function restore(reason)
        local active=s.active
        if not active then return true end
        active.applying=false
        local errors={}
        local function attempt(label,fn)
            local ok,err=pcall(fn)
            if not ok then errors[#errors+1]=label..": "..tostring(err) end
            return ok
        end
        if active.loop then attempt("cancel_loop",function() CancelDelayedAction(active.loop) end); active.loop=nil end
        -- Restore AI and each player field independently; failure of one must not block others.
        if valid(active.slot.plane) then
            for key,value in pairs(active.ai_values) do
                attempt(key,function() active.slot.plane[key]=value; assert(active.slot.plane[key]==value,"readback") end)
            end
        end
        if valid(active.slot.component) then
            attempt("AI",function() active.slot.component.AC8ManualEnable=active.enabled; assert(active.slot.component.AC8ManualEnable==active.enabled,"readback") end)
        end
        if valid(s.player) then
            for key,value in pairs(active.player_values) do
                attempt(key,function() s.player[key]=value; assert(s.player[key]==value,"readback") end)
            end
        end
        local view_restored=true
        if valid(s.pc) then
            view_restored=attempt("view",function()
                local target=valid(active.view) and active.view or s.player
                assert(valid(target),"No valid original view")
                s.pc:SetViewTargetWithBlend(target,0,0,0,false)
                assert(s.pc:GetViewTarget():GetAddress()==target:GetAddress(),"View readback")
            end)
            attempt("camera_auto",function() s.pc.bAutoManageActiveCameraTarget=active.auto_camera end)
        end
        if view_restored and valid(active.camera) then attempt("destroy_camera",function() active.camera:K2_DestroyActor() end) end
        pcall(sample,active,"restored_sample")
        if #errors==0 then
            s.active=nil
            notify("AI restored; original aircraft and camera returned ("..reason..")")
        else
            log("restore_incomplete",reason.." | "..table.concat(errors," | "))
        end
        return #errors==0
    end
    s.restore=restore
    local function selected_valid(slot)
        assert(same_world(s.player) and same_world(s.pc) and same_world(slot.plane),"World changed")
        assert(s.pc.Pawn:GetAddress()==s.player:GetAddress(),"Player pawn changed")
        assert(slot.plane.bIsActivated and not slot.plane.bIsIGCActor and not slot.plane.bIsAnimationPlane,"Wingman unavailable")
        assert(valid(slot.component) and slot.component.Owner:GetAddress()==slot.plane:GetAddress(),"Component owner changed")
    end
    local function take()
        if s.active and not restore("switch") then return end
        local f=io.open(output_dir.."/manual-ready.txt","r")
        local token=f and f:read("*a") or ""
        if f then f:close() end
        assert(token==stamp,"Live native layout has not been validated yet")
        local slot=s.slots[s.selection]
        selected_valid(slot)
        assert(slot.component.AC8ManualEnable==1 and slot.plane.AC8ManualScale==1,"Unexpected AI/scale state")
        local active={slot=slot,enabled=1,ai_values={},player_values={},view=s.pc:GetViewTarget(),
            auto_camera=s.pc.bAutoManageActiveCameraTarget,writes=0,applying=false}
        assert(valid(active.view) and type(active.auto_camera)=="boolean","Camera state unavailable")
        for _, key in ipairs(ai_axes) do
            local x=slot.plane[key]; assert(finite(x) and math.abs(x)<=1,"Invalid AI input")
            active.ai_values[key]=x
        end
        local fire_permission=slot.plane.bPermissionToFire
        assert(type(fire_permission)=="boolean","Fire permission unavailable")
        active.ai_values.bPermissionToFire=fire_permission
        local source_camera=s.player.ThirdPersonCamera
        assert(valid(source_camera),"Original third-person camera unavailable")
        local fov=source_camera.FieldOfView
        assert(finite(fov) and fov>20 and fov<150,"Original camera FOV invalid")
        for _, key in ipairs(player_gates) do
            local x=s.player[key]; assert(type(x)=="boolean","Missing player input gate: "..key)
            active.player_values[key]=x
        end
        for _, key in ipairs(player_axes) do
            local x=s.player[key]; assert(finite(x) and math.abs(x)<=1,"Invalid player input: "..key)
            active.player_values[key]=x
        end
        assert(active.player_values.bEnableMovmentInput and active.player_values.bEnableWingInput,"Player movement already disabled")
        s.generation=s.generation+1
        local generation=s.generation
        s.active=active -- From here on every error has a rollback owner.
        ExecuteInGameThreadWithDelay(15000,function() if s.generation==generation then restore("15s_limit") end end)
        ExecuteInGameThreadWithDelay(16000,function() if s.generation==generation then restore("16s_watchdog") end end)
        local pos,rot=camera_pose(slot.plane)
        -- SpawnActor has a different custom rotator converter. Spawn neutral, then
        -- apply the validated reflected transform in update_camera.
        active.camera=slot.plane:GetWorld():SpawnActor(camera_class,pos,{})
        assert(valid(active.camera),"Camera spawn failed")
        local camera_component=active.camera.CameraComponent
        assert(valid(camera_component),"Temporary camera component unavailable")
        camera_component.FieldOfView=fov
        assert(math.abs(camera_component.FieldOfView-fov)<0.001,"Camera FOV readback failed")
        update_camera(active) -- Validate orientation before switching the view.
        sample(active,"before_take")
        for _,key in ipairs(player_gates) do s.player[key]=false; assert(s.player[key]==false,"Gate write failed") end
        for _,key in ipairs(player_axes) do s.player[key]=0 end
        slot.component.AC8ManualEnable=0
        assert(slot.component.AC8ManualEnable==0,"AI switch readback failed")
        -- This reflected permission is distinct from the flight AI switch.
        -- Whether it cancels queued salvos remains a live-test question.
        slot.plane.bPermissionToFire=false
        assert(slot.plane.bPermissionToFire==false,"Fire permission readback failed")
        s.pc.bAutoManageActiveCameraTarget=false
        s.pc:SetViewTargetWithBlend(active.camera,0,0,0,false)
        assert(s.pc:GetViewTarget():GetAddress()==active.camera:GetAddress(),"Camera switch readback failed")
        active.applying=true
        local function down(key) return s.pc:IsInputKeyDown(keys[key]) and 1 or 0 end
        local function stick(key)
            local x=s.pc:GetInputAnalogKeyState(keys[key])
            assert(finite(x) and math.abs(x)<=1.01,"Invalid stick value")
            -- Capture 044114-8: engine-exposed axes exactly matched original
            -- player InputRoll/InputPitch in 1201 samples. Do not rescale twice.
            return math.max(-1,math.min(1,x))
        end
        local function cap(x) return math.max(-1,math.min(1,x)) end
        active.loop=LoopInGameThreadAfterFrames(1,function()
            if not active.applying then return end
            local ok,err=pcall(function()
                selected_valid(slot)
                assert(slot.component.AC8ManualEnable==0,"AI resumed unexpectedly")
                assert(slot.plane.bPermissionToFire==false,"AI fire permission resumed unexpectedly")
                assert(active.writes<3000,"Frame limit")
                if down("Escape")==1 then restore("pause_key"); return end
                for _,key in ipairs(player_axes) do s.player[key]=0 end
                local pitch=cap((math.max(down("Up"),down("Gamepad_DPad_Up"))-math.max(down("Down"),down("Gamepad_DPad_Down")))*0.25+stick("Gamepad_LeftY"))
                local roll=cap((math.max(down("Right"),down("Gamepad_DPad_Right"))-math.max(down("Left"),down("Gamepad_DPad_Left")))*0.25+stick("Gamepad_LeftX"))
                local yaw=(math.max(down("NumPadSix"),down("Gamepad_RightShoulder"))-math.max(down("NumPadFour"),down("Gamepad_LeftShoulder")))*0.25
                slot.plane:InputPitch(pitch,true)
                slot.plane:InputRoll(roll,true)
                slot.plane:InputYaw(yaw,true)
                active.writes=active.writes+1
                update_camera(active)
                assert(s.pc:GetViewTarget():GetAddress()==active.camera:GetAddress(),"Game replaced camera")
                if active.writes%30==0 then sample(active,"steering") end
            end)
            if not ok then log("tick_error",err); restore("tick_error") end
        end)
        notify("CONTROL: "..slot.label.." | left stick / arrows, LB-RB / Num4-6 | F9 returns | 15 seconds")
        sample(active,"taken")
    end
    local function dispatch(fn)
        ExecuteInGameThread(function()
            if s.busy then return end
            s.busy=true
            local ok,err=pcall(fn)
            if not ok then log("action_error",err); restore("action_error") end
            s.busy=false
        end)
    end
    RegisterKeyBind(Key.F6,function() dispatch(function()
        if s.active and not restore("select_next") then return end
        s.selection=s.selection%#s.slots+1
        notify("Selected "..s.slots[s.selection].label.." | F7 control | F6 next | F9 return")
    end) end)
    RegisterKeyBind(Key.F7,function() dispatch(take) end)
    RegisterKeyBind(Key.F9,function() dispatch(function() restore("F9") end) end)
    _G.AC8ManualControl=s
    -- Expose only lifecycle operations for deterministic offline rollback tests.
    s.take=take
    notify("Ready for validation. Selected "..s.slots[1].label..". F6 next; F7 control; F9 return.")
    log("installed","stamp="..stamp.." slots=3; camera/input mutations await F7 and validation token")
end
