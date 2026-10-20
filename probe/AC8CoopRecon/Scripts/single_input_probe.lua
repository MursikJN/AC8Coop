-- One session-bound roll pulse, after the pause experiment has restored successfully.
-- Native InputRoll: plane[0x2A94] = clamp(-Power * plane[0x6C8], -1, 1).
return function(output_dir, stamp)
    local existing = _G.AC8ControlExperiment
    if existing then
        if existing.restore then existing.restore("repeat_F8") end
        print("[AC8Control] Already attempted; repeated F8 only restores.\n")
        return
    end
    assert(output_dir:find("session-20261020-035351",1,true), "Wrong session")
    assert(_G.AC8PauseExperiment and _G.AC8PauseExperiment.done, "Pause experiment must finish first")
    local matches = {}
    for _, candidate in ipairs(FindAllOf("BP_WOP1007_f18c_C") or {}) do
        if candidate:IsValid() and candidate:GetFullName():find("/Mission007/",1,true)
            and candidate.CallsignId:ToString() == "ContainerAllyCallsign_Name_Noise"
            and candidate.ObjNameID:ToString() == "ContainerAllyCallsign_Name_Joker4" then
            matches[#matches+1] = candidate
        end
    end
    assert(#matches == 1, "Target identity is not unique")
    local plane = matches[1]
    local component = plane.AIStateComponent
    assert(plane:GetAddress() == 0x155F75B560, "Plane changed")
    assert(component:IsValid() and component:GetAddress() == 0x157EFD9BA0, "Component changed")
    assert(component.Owner:GetAddress() == plane:GetAddress(), "Owner mismatch")
    RegisterCustomProperty({Name="AC8LabRollInput",Type=PropertyTypes.FloatProperty,
        BelongsToClass="/Script/Live.LiveAIPlane",OffsetInternal=0x2A94})
    RegisterCustomProperty({Name="AC8LabInputScale",Type=PropertyTypes.FloatProperty,
        BelongsToClass="/Script/Live.LiveAIPlane",OffsetInternal=0x6C8})
    local enabled, roll = component.AC8LabNativeEnableByte, plane.AC8LabRollInput
    assert(enabled == 1, "AI not restored/enabled")
    assert(type(roll) == "number" and roll == roll and math.abs(roll) <= 1, "Unexpected original roll input")
    assert(plane.AC8LabInputScale == 1, "Unexpected input scale")
    local state = {done=false,mutated=false}
    _G.AC8ControlExperiment = state
    local path = output_dir .. "/control-test-" .. stamp .. ".tsv"
    local f = assert(io.open(path,"w"))
    f:write("phase\tflag\troll_input\tpitch\tyaw\troll\tx\ty\tz\tbehavior\tcurrent_node\tdetail\n")
    f:close()
    local function name(obj)
        return obj and obj:IsValid() and obj:GetFullName() or "invalid"
    end
    local function log(phase, detail)
        local position, rotation = plane:K2_GetActorLocation(), plane:K2_GetActorRotation()
        local behavior = component.RootBehavior
        local node = behavior:IsValid() and behavior.CurrentNode or nil
        local out = assert(io.open(path,"a"))
        out:write(phase,"\t",tostring(component.AC8LabNativeEnableByte),"\t",tostring(plane.AC8LabRollInput),
            "\t",tostring(rotation.Pitch),"\t",tostring(rotation.Yaw),"\t",tostring(rotation.Roll),
            "\t",tostring(position.X),"\t",tostring(position.Y),"\t",tostring(position.Z),
            "\t",name(behavior),"\t",name(node),"\t",tostring(detail or ""),"\n")
        out:close()
    end
    local function restore(reason)
        if state.done then return end
        -- Independent attempts: an input/log failure must not prevent enabling the AI.
        local input_ok, input_error = pcall(function()
            if plane:IsValid() and plane:GetAddress() == 0x155F75B560 then
                plane.AC8LabRollInput = roll
                assert(plane.AC8LabRollInput == roll, "Input restore readback failed")
            end
        end)
        local flag_ok, flag_error = pcall(function()
            if component:IsValid() and component:GetAddress() == 0x157EFD9BA0 then
                component.AC8LabNativeEnableByte = enabled
                assert(component.AC8LabNativeEnableByte == enabled, "AI restore readback failed")
            end
        end)
        state.done = input_ok and flag_ok
        local log_ok = pcall(log,"restored",reason)
        print("[AC8Control] Restore " .. reason .. "; input=" .. tostring(input_ok) .. "; AI=" .. tostring(flag_ok)
            .. "; log=" .. tostring(log_ok) .. "; errors=" .. tostring(input_error) .. "/" .. tostring(flag_error) .. "\n")
    end
    state.restore = restore
    RegisterKeyBind(Key.F9, function() ExecuteInGameThread(function() restore("manual_F9") end) end)
    ExecuteInGameThreadWithDelay(600, function() restore("automatic_600ms") end)
    ExecuteInGameThreadWithDelay(1200, function() restore("watchdog_1200ms") end)
    local ok, err = pcall(function()
        log("before")
        local original_behavior = name(component.RootBehavior)
        local original_node = name(component.RootBehavior.CurrentNode)
        state.mutated = true
        component.AC8LabNativeEnableByte = 0
        assert(component.AC8LabNativeEnableByte == 0, "AI switch readback failed")
        plane:InputRoll(0.1, true)
        assert(math.abs(plane.AC8LabRollInput + 0.1) < 0.000001, "InputRoll readback mismatch")
        assert(name(component.RootBehavior) == original_behavior and name(component.RootBehavior.CurrentNode) == original_node,
            "Task reference changed immediately")
        log("input_applied", "Power=0.1 bClamp=true; requested duration=600ms")
        for _, delay in ipairs({100,300,1500,3000}) do
            local sample_delay = delay
            ExecuteInGameThreadWithDelay(sample_delay, function()
                local sample_ok, sample_error = pcall(log,"sample_" .. sample_delay .. "ms")
                if not sample_ok then restore("sample_error: " .. tostring(sample_error)) end
                if sample_delay == 3000 then
                    print("[AC8Control] Final sample=" .. tostring(sample_ok) .. "; restored=" .. tostring(state.done) .. "\n")
                end
            end)
        end
    end)
    if not ok then restore("error: " .. tostring(err)); error(err) end
    print("[AC8Control] Applied one 0.1 roll pulse. Restore scheduled for 600ms; F9 restores now.\n")
end
