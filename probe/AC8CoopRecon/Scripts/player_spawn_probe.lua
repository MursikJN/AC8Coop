-- Stage by F8; one deferred-only F14D allocation by F7; F9 retries owned cleanup.
-- Never calls FinishSpawningActor, Possess or a flight-update function.
return function(output_dir,stamp)
    local manual=assert(_G.AC8ManualControl,"Manual context absent")
    assert(not manual.active,"Restore active manual control before staging this probe")
    manual.busy=true
    local prior=_G.AC8PlayerSpawnProbe
    if prior then
        assert(prior.cleanup("reload") and prior.owned==nil,"Previous cleanup still pending")
        prior.retired=true
    end
    local s={attempted=false,busy=false,retired=false,owned=nil}
    local path=output_dir.."/player-spawn-"..stamp..".tsv"
    local function valid(o) return o and o:IsValid() end
    local function name(o) return valid(o) and o:GetFullName() or "invalid" end
    local function id(o) return valid(o) and o:GetAddress() or 0 end
    local function clean(v) return tostring(v):gsub("[\r\n\t]"," ") end
    local function log(event,detail)
        local f
        local ok=pcall(function()
            f=assert(io.open(path,"a")); f:write(event,"\t",clean(detail),"\n"); f:close(); f=nil
        end)
        if f then pcall(function() f:close() end) end
        pcall(function() print("[AC8PlayerSpawn] "..event.." "..clean(detail)..(ok and "" or " [file_log_failed]").."\n") end)
    end
    local function identity(o) return tostring(id(o)).." "..name(o) end
    local function resolve()
        local controllers={}
        for _,controller in ipairs(FindAllOf("LivePlayerController") or {}) do
            if valid(controller) and id(controller:GetWorld())==manual.world_id then
                local pawn=controller.Pawn
                if valid(pawn) and pawn:IsA("/Script/Live.LivePlayerPlane") then
                    controllers[#controllers+1]={pc=controller,player=pawn}
                end
            end
        end
        assert(#controllers==1,"Need one current player controller")
        local c=controllers[1]; c.slots={}; c.identities={pc=identity(c.pc),player=identity(c.player)}
        assert(id(c.player:GetWorld())==manual.world_id and not c.player.bIsIGCActor,"Original world/player changed")
        local expected={Joker2="Professor",Joker3="Pinkhead",Joker4="Noise"}
        for _,plane in ipairs(FindAllOf("BP_WOP1007_f18c_C") or {}) do
            if valid(plane) and id(plane:GetWorld())==manual.world_id and plane.bIsActivated
                and not plane.bIsIGCActor and not plane.bIsAnimationPlane then
                local key=plane.ObjNameID:ToString():match("^ContainerAllyCallsign_Name_(Joker%d)$")
                if expected[key] then
                    assert(not c.slots[key],"Duplicate current wingman: "..key)
                    assert(plane.CallsignId:ToString()=="ContainerAllyCallsign_Name_"..expected[key],"Unexpected callsign")
                    local component=plane.AIStateComponent
                    assert(valid(component) and id(component.Owner)==id(plane),"Current wingman component owner mismatch")
                    c.slots[key]={plane=plane,component=component}
                    c.identities[key..".plane"]=identity(plane)
                    c.identities[key..".component"]=identity(component)
                end
            end
        end
        for key in pairs(expected) do assert(c.slots[key],"Missing current wingman: "..key) end
        return c
    end
    local initial=resolve()
    local player,pc=initial.player,initial.pc
    local class=player:GetClass()
    assert(name(class):find("/PP0023_f14d/",1,true),"Only loaded original F14D class admitted")
    local protected={[id(player)]=true,[id(pc)]=true,[id(pc:GetViewTarget())]=true}
    for _,slot in pairs(initial.slots) do protected[id(slot.plane)]=true; protected[id(slot.component)]=true end
    local class_id=id(class)
    local gates={"bEnableMovmentInput","bEnableWingInput","bEnableCameraInput","bEnableCameraViewChange",
        "bEnableWeaponInput","bEnableFlareInput","bEnableChangeTargetInput"}
    local function baseline()
        log("stage","baseline_begin")
        local current=resolve()
        for key,value in pairs(initial.identities) do
            assert(current.identities[key]==value,"Current object changed since installation: "..key)
        end
        local pc,player=current.pc,current.player
        local b={pawn=id(pc.Pawn),view=id(pc:GetViewTarget()),input=id(player.InputComponent),controller=id(player.Controller),
            automatic_camera=pc.bAutoManageActiveCameraTarget}
        for _,k in ipairs(gates) do b[k]=player[k] end
        for key,slot in pairs(current.slots) do
            b[key..".AI"]=slot.component.AC8ManualEnable
            b[key..".fire"]=slot.plane.bPermissionToFire
        end
        log("stage","baseline_ready")
        return b,current
    end
    local function unchanged(before,phase)
        for k,v in pairs(baseline()) do assert(v==before[k],"Original state changed: "..phase.." "..k) end
        log("baseline_unchanged",phase)
    end
    local function cleanup(reason)
        if not s.owned then return true end
        local ok,err=pcall(function()
            assert(s.owned_id and s.owned_name,"Owned identity unavailable; cleanup quarantined")
            assert(not protected[s.owned_id],"Refuse to destroy a baseline object")
            local actor
            for _,candidate in ipairs(FindAllOf("BP_PlayerPlane_PP0023_f14d_C") or {}) do
                if valid(candidate) and id(candidate)==s.owned_id then
                    assert(name(candidate)==s.owned_name,"Owned address reused; cleanup quarantined")
                    assert(not actor,"Duplicate owned lookup")
                    actor=candidate
                end
            end
            -- Absence from this unverified lookup is not proof of destruction.
            assert(actor,"Owned actor absent from fresh lookup; cleanup quarantined")
            assert(id(actor:GetClass())==class_id and id(actor:GetWorld())==manual.world_id,"Owned object identity mismatch")
            if not actor.bActorIsBeingDestroyed then actor:K2_DestroyActor() end
            if not valid(actor) then s.owned=nil; log("removed",reason)
            else assert(actor.bActorIsBeingDestroyed==true,"Destroy not acknowledged"); log("destroy_marked",reason.." address="..string.format("0x%X",id(actor))) end
        end)
        if not ok then log("cleanup_error",err) end
        return ok
    end
    s.cleanup=cleanup
    local function signature(pathname,expected)
        local fn=StaticFindObject(pathname); assert(valid(fn),"Function unavailable: "..pathname)
        local actual,ordered={},{}
        fn:ForEachProperty(function(p)
            local n=p:GetFName():ToString(); local t=p:GetClass():GetFName():ToString()
            actual[n]=t; log("signature",pathname.." "..n.." "..t.." offset="..p:GetOffset_Internal())
            ordered[#ordered+1]={name=n,offset=p:GetOffset_Internal()}
            if expected[n] and expected[n].struct then
                local nested=name(p:GetStruct()); log("parameter_struct",pathname.." "..n.." "..nested)
                assert(nested=="ScriptStruct /Script/CoreUObject."..expected[n].struct,"Unexpected struct: "..n)
            end
        end)
        for n,t in pairs(actual) do
            assert(expected[n],"Unexpected parameter: "..pathname.." "..n)
            assert(expected[n][t],"Unexpected parameter type: "..n.." "..t)
        end
        for n,t in pairs(expected) do if not t.optional then assert(actual[n],"Missing parameter: "..n) end end
        table.sort(ordered,function(a,b) return a.offset<b.offset end)
        return actual,ordered
    end
    local spawn_fields,spawn_order=signature("/Script/Engine.GameplayStatics:BeginDeferredActorSpawnFromClass",{
        WorldContextObject={ObjectProperty=true},ActorClass={ClassProperty=true},SpawnTransform={StructProperty=true,struct="Transform"},
        CollisionHandlingOverride={ByteProperty=true,EnumProperty=true},Owner={ObjectProperty=true},
        TransformScaleMethod={ByteProperty=true,EnumProperty=true,optional=true},ReturnValue={ObjectProperty=true},
    })
    local expected_order={"WorldContextObject","ActorClass","SpawnTransform","CollisionHandlingOverride","Owner"}
    if spawn_fields.TransformScaleMethod then expected_order[#expected_order+1]="TransformScaleMethod" end
    expected_order[#expected_order+1]="ReturnValue"
    for i,n in ipairs(expected_order) do assert(spawn_order[i].name==n,"Unexpected spawn argument order") end
    local _,transform_order=signature("/Script/Engine.KismetMathLibrary:MakeTransform",{
        Location={StructProperty=true,struct="Vector"},Rotation={StructProperty=true,struct="Rotator"},
        Scale={StructProperty=true,struct="Vector"},ReturnValue={StructProperty=true,struct="Transform"},
    })
    for i,n in ipairs({"Location","Rotation","Scale","ReturnValue"}) do
        assert(transform_order[i].name==n,"Unexpected MakeTransform argument order")
    end
    signature("/Script/Engine.Actor:K2_DestroyActor",{})
    local function enum_value(pathname,member)
        local e=StaticFindObject(pathname); assert(valid(e),"Enum unavailable")
        local found
        e:ForEachName(function(n,v)
            local label=n:ToString(); log("enum",pathname.." "..label.."="..v)
            if label==member or label:match("::([^:]+)$")==member then found=v end
        end)
        assert(type(found)=="number","Enum member absent: "..member); return found
    end
    local collision=enum_value("/Script/Engine.ESpawnActorCollisionHandlingMethod","DontSpawnIfColliding")
    local scale=spawn_fields.TransformScaleMethod and enum_value("/Script/Engine.ESpawnActorScaleMethod","MultiplyWithRoot") or nil
    local statics=StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local mathlib=StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    assert(valid(statics) and valid(mathlib),"Function libraries missing")

    local tables=FindAllOf("DataTable") or {}
    local inventory=assert(io.open(output_dir.."/loaded-aircraft-tables-"..stamp..".tsv","w"))
    inventory:write("# loaded in this process only; no assets loaded and no row contents read\n")
    local matches=0
    for i,t in ipairs(tables) do
        if i>2048 then inventory:write("# table_visit_cap=2048\n"); break end
        local n=name(t); local l=n:lower()
        if l:find("plane",1,true) or l:find("flight",1,true) or l:find("weapon",1,true)
            or l:find("missile",1,true) or l:find("upgrade",1,true) or l:find("parts",1,true) then
            matches=matches+1
            if matches>256 then inventory:write("# matched_cap=256\n"); break end
            local ok,rowstruct=pcall(function() return name(t.RowStruct) end)
            inventory:write(clean(n),"\t",clean(ok and rowstruct or "row_struct_unavailable"),"\n")
        end
    end
    inventory:close(); log("loaded_tables","total="..#tables.." matched="..matches)

    local function run()
        assert(not s.attempted and not s.owned,"Only one attempt per installation")
        local f=io.open(output_dir.."/spawn-ready.txt","r"); local token=f and f:read("*a") or ""; if f then f:close() end
        assert(token==stamp,"Spawn metadata has not been reviewed")
        local before,current=baseline(); s.before=before
        local player=current.player
        local class=player:GetClass()
        assert(id(class)==class_id,"Player class changed")
        local p=player:K2_GetActorLocation()
        for _,axis in ipairs({"X","Y","Z"}) do
            local v=p[axis]; assert(type(v)=="number" and v==v and math.abs(v)<math.huge,"Invalid location "..axis)
        end
        log("stage","transform_begin")
        local transform=mathlib:MakeTransform({X=p.X,Y=p.Y,Z=p.Z+30000},mathlib:MakeRotator(0,0,0),{X=1,Y=1,Z=1})
        log("stage","transform_ready")
        s.attempted=true
        -- Arm fallback before allocation; same-frame cleanup is the normal path.
        ExecuteInGameThreadWithDelay(1000,function() cleanup("watchdog_1s") end)
        ExecuteInGameThreadWithDelay(3000,function() cleanup("watchdog_3s") end)
        local actor
        log("stage","spawn_begin")
        if spawn_fields.TransformScaleMethod then
            actor=statics:BeginDeferredActorSpawnFromClass(player,class,transform,collision,nil,scale)
        else actor=statics:BeginDeferredActorSpawnFromClass(player,class,transform,collision,nil) end
        s.owned=actor -- Register cleanup ownership before inspection can fail.
        log("stage","spawn_returned")
        assert(valid(actor),"Deferred spawn returned invalid; possibly collision rejected")
        s.owned_id=id(actor); s.owned_name=name(actor)
        assert(not protected[id(actor)] and id(actor:GetClass())==id(class),"Unexpected returned actor")
        log("created",name(actor).." address="..string.format("0x%X",id(actor)))
        assert(not valid(actor.Controller),"Deferred actor unexpectedly has a controller")
        local info=assert(io.open(output_dir.."/deferred-player-"..stamp..".tsv","w"))
        local ok,err=pcall(function()
            info:write("object\t",clean(name(actor)),"\t",string.format("0x%X",id(actor)),"\n")
            for _,key in ipairs({"PlaneTypeID","PlaneSWP","PlaneSpWeaponID1","PlaneSpWeaponID2","bIsActivated","bIsIGCActor",
                "AutoPossessPlayer","AutoPossessAI","AutoReceiveInput","bActorIsBeingDestroyed","bEnableMovmentInput","bEnableWingInput"}) do
                info:write("value\t",key,"\t",clean(actor[key]),"\n")
            end
            for _,key in ipairs({"Controller","RootComponent","InputComponent","PlayerWeaponActivator","UpgradeParts","LocalUserSettings","CameraViewComponent","ThirdPersonCamera"}) do
                info:write("reference\t",key,"\t",clean(name(actor[key])),"\n")
            end
        end)
        info:close(); if not ok then error(err) end
        unchanged(before,"after_deferred_spawn")
        assert(cleanup("same_frame"),"Cleanup requires retry")
        unchanged(before,"after_destroy_request")
        ExecuteInGameThreadWithDelay(250,function()
            local ok,err=pcall(function() cleanup("verification_250ms"); unchanged(before,"250ms") end)
            if not ok then log("verification_error",err) end
        end)
        log("attempt_complete","Deferred-only; FinishSpawningActor/Possess not called; not a flight-ready aircraft")
    end
    local function dispatch(fn)
        ExecuteInGameThread(function()
            if s.retired or s.busy then return end
            s.busy=true
            local ok,err=pcall(fn)
            if not ok then cleanup("action_error"); log("action_error",err) end
            s.busy=false
        end)
    end
    RegisterKeyBind(Key.F7,function() dispatch(run) end)
    RegisterKeyBind(Key.F9,function() dispatch(function() cleanup("F9") end) end)
    _G.AC8PlayerSpawnProbe=s
    log("installed","stamp="..stamp.." exact_class="..name(class).."; awaiting metadata review token and F7")
end
