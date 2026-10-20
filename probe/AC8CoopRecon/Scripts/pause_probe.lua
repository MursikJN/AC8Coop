-- Session-bound experiment. Changes only the byte written by the observed
-- LiveGameObjectComponent virtual setter at RVA 0x7d2c180. No task reset.
-- Valid ONLY for build 25201480 and the already inspected 035351 session.
return function(output_dir, stamp)
    local existing = _G.AC8PauseExperiment
    if existing then
        if existing.restore then existing.restore("repeat_F8") end
        print("[AC8Pause] Already attempted; F8 cannot start another experiment.\n")
        return
    end
    assert(output_dir:find("session-20261020-035351", 1, true), "Wrong research session")
    assert(type(ExecuteInGameThreadWithDelay) == "function", "Restore timer unavailable")
    local matches = {}
    for _, plane in ipairs(FindAllOf("BP_WOP1007_f18c_C") or {}) do
        if plane:IsValid() and plane:GetFullName():find("/Mission007/",1,true)
            and plane.CallsignId:ToString() == "ContainerAllyCallsign_Name_Noise"
            and plane.ObjNameID:ToString() == "ContainerAllyCallsign_Name_Joker4" then
            matches[#matches+1] = plane
        end
    end
    assert(#matches == 1, "Target identity is not unique")
    local plane = matches[1]
    local component = plane.AIStateComponent
    assert(plane:GetAddress() == 0x155F75B560, "Target changed since native inspection")
    assert(component:IsValid() and component:GetAddress() == 0x157EFD9BA0, "Component changed")
    assert(component.Owner:GetAddress() == plane:GetAddress(), "Owner mismatch")
    RegisterCustomProperty({Name="AC8LabNativeEnableByte", Type=PropertyTypes.ByteProperty,
        BelongsToClass="/Script/Live.LiveAIStateComponent", OffsetInternal=0xD3})
    local original = component.AC8LabNativeEnableByte
    assert(original == 1, "Expected enabled native byte")
    local state = {done=false, mutated=false}
    _G.AC8PauseExperiment = state
    local path = output_dir .. "/pause-test-" .. stamp .. ".tsv"
    local file = assert(io.open(path,"w"))
    file:write("phase\tflag\tbehavior\tcurrent_node\tx\ty\tz\tdetail\n")
    file:close()
    local function name(obj)
        if not obj or not obj:IsValid() then return "invalid" end
        return obj:GetFullName()
    end
    local function log(phase, detail)
        local behavior = component.RootBehavior
        local node = behavior:IsValid() and behavior.CurrentNode or nil
        local location = plane:K2_GetActorLocation()
        local out = assert(io.open(path,"a"))
        out:write(phase,"\t",tostring(component.AC8LabNativeEnableByte),"\t",name(behavior),"\t",name(node),
            "\t",tostring(location.X),"\t",tostring(location.Y),"\t",tostring(location.Z),"\t",tostring(detail or ""),"\n")
        out:close()
    end
    local function restore(reason)
        if state.done then return end
        -- Restore precedes all logging/getters. A failed log must never leave AI disabled.
        if component:IsValid() and component:GetAddress() == 0x157EFD9BA0 then
            component.AC8LabNativeEnableByte = original
            assert(component.AC8LabNativeEnableByte == original, "RESTORE READBACK FAILED")
            state.done = true
            local ok, err = pcall(log,"restored",reason)
            print("[AC8Pause] Restored native enable byte: " .. reason .. "; log=" .. tostring(ok) .. " " .. tostring(err) .. "\n")
        else
            state.done = true
            print("[AC8Pause] Original component no longer exists; no stale address written.\n")
        end
    end
    state.restore = restore
    RegisterKeyBind(Key.F9, function() ExecuteInGameThread(function() restore("manual_F9") end) end)
    -- Schedule both restoration attempts BEFORE the mutation.
    ExecuteInGameThreadWithDelay(1000, function() restore("automatic_1s") end)
    ExecuteInGameThreadWithDelay(2000, function() restore("watchdog_2s") end)
    local ok, err = pcall(function()
        log("before")
        local behavior = name(component.RootBehavior)
        local node = name(component.RootBehavior.CurrentNode)
        state.mutated = true
        component.AC8LabNativeEnableByte = 0
        assert(component.AC8LabNativeEnableByte == 0, "Disable readback failed")
        assert(name(component.RootBehavior) == behavior and name(component.RootBehavior.CurrentNode) == node,
            "Task references changed during immediate switch")
        log("disabled", "same-frame task references preserved")
        ExecuteInGameThreadWithDelay(400, function()
            local sample_ok, sample_error = pcall(log,"during_400ms")
            if not sample_ok then restore("sample_error: " .. tostring(sample_error)) end
        end)
        ExecuteInGameThreadWithDelay(4000, function()
            local sample_ok, sample_error = pcall(log,"after_4s")
            print("[AC8Pause] Final sample=" .. tostring(sample_ok) .. " " .. tostring(sample_error) .. "\n")
        end)
    end)
    if not ok then restore("error: " .. tostring(err)); error(err) end
    print("[AC8Pause] One wingman native enable flag suspended; automatic restoration in 1 second. F9 restores now.\n")
end
