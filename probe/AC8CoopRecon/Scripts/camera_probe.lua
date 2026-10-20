-- Diagnose only a temporary camera; never transfers view or changes aircraft input/AI.
return function(output_dir,stamp)
    local s=assert(_G.AC8ManualControl,"Manual state missing")
    assert(s.restore("camera_diagnostic"),"Previous restoration incomplete")
    local plane=s.slots[s.selection].plane
    local path=output_dir.."/camera-diagnostic-"..stamp..".tsv"
    local function row(phase,data)
        local f=assert(io.open(path,"a")); f:write(phase,"\t",tostring(data),"\n"); f:close()
        print("[AC8CameraDiagnostic] "..phase.." "..tostring(data).."\n")
    end
    local function fields(value)
        local items={"type="..type(value)}
        if type(value)=="table" then for k,v in pairs(value) do items[#items+1]=tostring(k).."="..tostring(v) end end
        table.sort(items); return table.concat(items," ")
    end
    local camera
    local ok,err=pcall(function()
        local class=StaticFindObject("/Script/Engine.CameraActor")
        local position=plane:K2_GetActorLocation()
        camera=plane:GetWorld():SpawnActor(class,position,{Pitch=20,Yaw=30,Roll=0})
        assert(camera:IsValid(),"Camera spawn failed")
        local function sample(phase)
            row(phase.."_rotation",fields(camera:K2_GetActorRotation()))
            row(phase.."_forward",fields(camera:GetActorForwardVector()))
        end
        sample("spawn_20_30")
        row("set_rotation_result",camera:K2_SetActorRotation({Pitch=20,Yaw=30,Roll=0},false))
        sample("set_rotation_20_30")
        row("set_transform_result",camera:K2_SetActorLocationAndRotation(position,{Pitch=-20,Yaw=60,Roll=0},false,{},false))
        sample("set_transform_minus20_60")
        local rotator=StaticFindObject("/Script/CoreUObject.Rotator")
        if rotator:IsValid() then rotator:ForEachProperty(function(p)
            row("rotator_field",p:GetFName():ToString().." offset="..tostring(p:GetOffset_Internal()).." type="..p:GetClass():GetFName():ToString())
        end) end
        local mathlib=StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
        if mathlib:IsValid() then
            local made=mathlib:MakeRotator(0,20,30)
            row("make_rotator",fields(made))
            row("made_rotation_result",camera:K2_SetActorRotation(made,false))
            sample("made_rotation_20_30")
        end
        ExecuteInGameThreadWithDelay(100,function()
            local sample_ok,sample_err=pcall(sample,"delayed_100ms")
            if camera:IsValid() then camera:K2_DestroyActor() end
            row("finished",tostring(sample_ok).." "..tostring(sample_err))
        end)
    end)
    if not ok then
        if camera and camera:IsValid() then camera:K2_DestroyActor() end
        row("error",err)
    end
end
