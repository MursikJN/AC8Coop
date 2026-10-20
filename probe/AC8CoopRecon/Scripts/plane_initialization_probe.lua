-- F8 only: fresh local player, reflected world pose, then read-only sampler ticket.
-- No wingman references, cached UObject handles, key hooks, spawn or setters.
return function(output_dir, stamp)
    local function valid(o) return o and o:IsValid() end
    local function addr(o) assert(valid(o), "invalid object"); return string.format("0x%x", o:GetAddress()) end
    local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
    local function offset(o, name)
        local c=o:GetClass()
        for _=1,20 do
            if not valid(c) then break end
            local found, count=nil,0
            c:ForEachProperty(function(p)
                count=count+1; assert(count<=512,"property limit")
                if p:GetFName():ToString()==name then
                    assert(p:GetClass():GetFName():ToString()=="ObjectProperty", "unexpected pointer type")
                    found=p:GetOffset_Internal(); return true
                end
            end)
            if found then
                assert(found>=0x28 and found<=0x2000 and found%8==0,"invalid offset")
                return string.format("0x%x",found)
            end
            c=c:GetSuperStruct()
        end
        error("missing pointer property "..name)
    end
    local candidates={}
    local controllers=FindAllOf("LivePlayerController") or {}
    assert(#controllers<=8,"controller limit")
    for _,pc in ipairs(controllers) do
        if valid(pc) then
            local p=pc.Pawn
            if valid(p) and p:IsA("/Script/Live.LivePlayerPlane") then
                candidates[#candidates+1]={pc=pc,p=p}
            end
        end
    end
    assert(#candidates==1,"need one local player")
    local pc,p=candidates[1].pc,candidates[1].p
    local world=pc:GetWorld()
    assert(addr(p:GetWorld())==addr(world) and addr(p.Controller)==addr(pc),"world/controller mismatch")
    assert(world:GetFullName():find("Mission007",1,true),"only mission 6 supported")
    assert(p.bIsActivated==true and p.bIsIGCActor==false,"need active non-cinematic player")
    local function getter(name, struct)
        local fn=StaticFindObject("/Script/Engine.Actor:"..name)
        assert(valid(fn),"missing getter "..name)
        local count=0
        fn:ForEachProperty(function(field)
            count=count+1
            assert(count==1 and field:GetFName():ToString()=="ReturnValue", "unexpected getter parameters")
            assert(field:GetClass():GetFName():ToString()=="StructProperty", "unexpected return type")
            assert(field:GetStruct():GetFullName()=="ScriptStruct /Script/CoreUObject."..struct,"unexpected struct")
        end)
        assert(count==1,"missing getter return")
    end
    getter("K2_GetActorLocation","Vector"); getter("K2_GetActorRotation","Rotator")
    local location=p:K2_GetActorLocation(); local rotation=p:K2_GetActorRotation()
    local pose={{"location_x",location.X},{"location_y",location.Y},{"location_z",location.Z},
                {"rotation_pitch",rotation.pitch},{"rotation_yaw",rotation.Yaw},{"rotation_roll",rotation.Roll}}
    -- Exact build schema uses lowercase pitch; do not substitute zero when missing.
    for _,row in ipairs(pose) do
        assert(finite(row[2]),"invalid pose field "..row[1].." type="..type(row[2]))
        row[2]=string.format("%.17g",row[2])
    end
    local pawn_address,world_address=addr(p),addr(world)
    local rows={{"format","ac8-flight-ticket-v1"},{"created_unix",tostring(os.time())},
        {"controller",addr(pc)},{"pawn",pawn_address},{"pawn_class",addr(p:GetClass())},{"world",world_address},
        {"world_name",world:GetFullName()},{"plane_class",p:GetClass():GetFullName()},
        {"pc_pawn_offset",offset(pc,"Pawn")},{"plane_controller_offset",offset(p,"Controller")}}
    assert(addr(pc.Pawn)==pawn_address and addr(p:GetWorld())==world_address,"player changed during capture")
    local function write(path, data)
        local existing=io.open(path,"r"); if existing then existing:close(); error("capture already exists") end
        local f=assert(io.open(path..".tmp","w"))
        local ok,err=pcall(function()
            for _,row in ipairs(data) do
                assert(not tostring(row[2]):find("[\r\n\t]"),"invalid ticket text")
                f:write(row[1],"\t",row[2],"\n")
            end
        end)
        f:close(); assert(ok,err); assert(os.rename(path..".tmp",path))
    end
    table.insert(pose,1,{"pawn",pawn_address}); table.insert(pose,2,{"world",world_address})
    -- Publish the ticket last: the companion pose must exist before the reader starts.
    write(output_dir.."/initialization-pose-"..stamp..".tsv",pose)
    write(output_dir.."/initialization-ticket-"..stamp..".tsv",rows)
    print("[AC8CoopRecon] Initialization sources ticket ready: pose, inputs and clock READ ONLY.\n")
end
