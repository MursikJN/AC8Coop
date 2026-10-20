-- Reads key states and actor identity only; no camera or aircraft control changes.
return function(output_dir,stamp)
    local s=assert(_G.AC8ManualControl,"Manual state absent")
    assert(s.restore("key_diagnostic"),"Restore incomplete")
    local path=output_dir.."/key-diagnostic-"..stamp..".tsv"
    local function row(phase,value)
        local f=assert(io.open(path,"a")); f:write(phase,"\t",tostring(value):gsub("[\r\n\t]"," "),"\n"); f:close()
    end
    local keytype=StaticFindObject("/Script/InputCore.Key")
    assert(keytype:IsValid(),"Key struct unavailable")
    local fieldname
    keytype:ForEachProperty(function(p)
        local n=p:GetFName():ToString()
        row("key_field",n.." type="..p:GetClass():GetFName():ToString().." offset="..p:GetOffset_Internal())
        if p:GetClass():GetFName():ToString()=="NameProperty" then fieldname=n end
    end)
    assert(fieldname,"FKey name field unavailable")
    local function describe(obj)
        local p=obj:K2_GetActorLocation()
        return obj:GetFullName()..string.format(" address=0x%X xyz=%.3f,%.3f,%.3f",obj:GetAddress(),p.X,p.Y,p.Z)
    end
    row("player",describe(s.player))
    row("selected",describe(s.slots[s.selection].plane))
    row("current_view",s.pc:GetViewTarget():GetFullName())
    row("player_input",s.pc.PlayerInput:GetFullName())
    local keys={}
    for _,n in ipairs({"Left","Right","Up","Down","A","D","F8"}) do
        keys[#keys+1]={name=n,old={KeyName=FName(n)},canonical={[fieldname]=FName(n)}}
    end
    local function sample(index)
        local values={"playerRoll="..tostring(s.player.InputRoll),"playerPitch="..tostring(s.player.InputPitch)}
        for _,k in ipairs(keys) do
            local old=s.pc:IsInputKeyDown(k.old)
            local canonical=s.pc:IsInputKeyDown(k.canonical)
            local analog=s.pc:GetInputAnalogKeyState(k.canonical)
            values[#values+1]=k.name.."="..tostring(old).."/"..tostring(canonical).."/"..tostring(analog)
        end
        row("sample_"..index,table.concat(values," "))
    end
    for i=0,60 do
        local index=i
        ExecuteInGameThreadWithDelay(i*100,function()
            local ok,err=pcall(sample,index)
            if not ok then row("error",err) end
            if index==60 then print("[AC8KeyDiagnostic] Finished "..stamp.."\n") end
        end)
    end
    print("[AC8KeyDiagnostic] Recording keys for 6 seconds.\n")
end
