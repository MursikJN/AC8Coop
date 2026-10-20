-- Deterministic model of the module's Lua-facing boundary; not an engine simulator.
H = {writes={}, inputs={}, keys={}, analog={}, bindings={}, loops={}, timers={}, files={}, cameras={}, now=0, failures={}}
local serial=1000
local function object(kind, values, methods)
    serial=serial+1
    local data=values or {}
    data.address=serial; data.alive=true; data.kind=kind
    local obj={}
    local base={
        IsValid=function() return data.alive end,
        GetAddress=function() return data.address end,
        GetFullName=function() return data.fullname or kind.." /Mission007/"..data.address end,
        GetWorld=function() return H.world end,
        IsA=function(_, path) return data.class==path end,
    }
    for key,value in pairs(methods or {}) do base[key]=value end
    setmetatable(obj,{
        __index=function(_, key) if base[key] then return base[key] end; return data[key] end,
        __newindex=function(_,key,value)
            local fail=H.failures[kind..":"..key]
            if fail and (fail.value==nil or fail.value==value) and fail.remaining>0 then
                fail.remaining=fail.remaining-1; error("injected write failure "..kind..":"..key)
            end
            H.writes[#H.writes+1]={object=kind,key=key,value=value}
            data[key]=value
        end,
    })
    return obj,data
end
H.object=object
function FName(value) return {ToString=function() return value end, text=value} end
H.world=object("world",{}, {
    SpawnActor=function(_,_,position,rotation)
        if H.spawn_failure then return object("invalid",{},{IsValid=function() return false end}) end
        local camera, data
        camera,data=object("camera",{position=position,rotation={pitch=rotation.Pitch or 0,Yaw=rotation.Yaw or 0,Roll=rotation.Roll or 0}},{
            K2_SetActorLocationAndRotation=function(_,p,r,sweep,hit,teleport)
                assert(sweep==false and type(hit)=="table" and teleport==false)
                -- Live AC8 reflection: lowercase pitch, offset 0. Unknown uppercase
                -- Pitch is silently ignored by UE4SS's reflected table conversion.
                data.position=p; data.rotation={pitch=r.pitch or 0,Yaw=r.Yaw or 0,Roll=r.Roll or 0}
            end,
            GetActorForwardVector=function()
                if H.orientation_failure then return {X=0,Y=0,Z=1} end
                local p,y=math.rad(data.rotation.pitch),math.rad(data.rotation.Yaw)
                return {X=math.cos(p)*math.cos(y),Y=math.cos(p)*math.sin(y),Z=math.sin(p)}
            end,
            K2_DestroyActor=function() data.alive=false; H.destroyed=(H.destroyed or 0)+1 end,
        })
        data.CameraComponent=object("camera_component",{FieldOfView=90})
        H.cameras[#H.cameras+1]=camera
        return camera
    end,
})
H.gates={"bEnableMovmentInput","bEnableWingInput","bEnableCameraInput","bEnableCameraViewChange","bEnableWeaponInput","bEnableFlareInput","bEnableChangeTargetInput"}
H.axes={"InputPitch","InputRoll","InputLeftYaw","InputRightYaw","InputThrottle","InputBrake"}
local player_values={class="/Script/Live.LivePlayerPlane",bIsIGCActor=false}
for _,key in ipairs(H.gates) do player_values[key]=true end
-- A pre-existing disabled unrelated gate must be preserved exactly.
player_values.bEnableFlareInput=false
H.original_player={}
for i,key in ipairs(H.axes) do player_values[key]=i*0.05 end
for key,value in pairs(player_values) do H.original_player[key]=value end
H.player=object("player",player_values)
player_values.ThirdPersonCamera=object("player_camera",{FieldOfView=61.927513122559})
H.view=object("original_view")
H.pc=object("pc",{Pawn=H.player,bAutoManageActiveCameraTarget=true,view=H.view},{
    IsInputKeyDown=function(_,key) return H.keys[key.KeyName.text]==true end,
    GetInputAnalogKeyState=function(_,key) return H.analog[key.KeyName.text] or 0 end,
    GetViewTarget=function(self) return self.view end,
    SetViewTargetWithBlend=function(self,target,blend,fn,exponent,locked)
        assert(blend==0 and fn==0 and exponent==0 and locked==false)
        self.view=target
    end,
})
H.planes={}; H.components={}; H.original_ai={}
for i,call in ipairs({"Professor","Pinkhead","Noise"}) do
    local id="Joker"..(i+1)
    local values={bIsActivated=true,bIsIGCActor=false,bIsAnimationPlane=false,
        ObjNameID=FName("ContainerAllyCallsign_Name_"..id),CallsignId=FName("ContainerAllyCallsign_Name_"..call),
        AC8ManualScale=1,AC8ManualPitch=0.01*i,AC8ManualYaw=0.02*i,AC8ManualRoll=0.03*i,bPermissionToFire=(i~=2)}
    local methods={
        K2_GetActorLocation=function() return {X=10000,Y=20000,Z=30000} end,
        GetActorForwardVector=function() return {X=1,Y=0,Z=0} end,
        K2_GetActorRotation=function() return {pitch=0,Yaw=0,Roll=0} end,
    }
    for _,axis in ipairs({"Pitch","Roll","Yaw"}) do
        methods["Input"..axis]=function(self,power,clamp)
            assert(clamp==true)
            H.inputs[#H.inputs+1]={plane=self,axis=axis,power=power}
            self["AC8Manual"..axis]=-power
        end
    end
    local plane=object(id,values,methods)
    local component=object(id.."_AI",{Owner=plane,AC8ManualEnable=1})
    values.AIStateComponent=component
    H.planes[i]=plane; H.components[i]=component
    H.original_ai[i]={AC8ManualPitch=values.AC8ManualPitch,AC8ManualYaw=values.AC8ManualYaw,AC8ManualRoll=values.AC8ManualRoll,bPermissionToFire=values.bPermissionToFire}
end
function FindAllOf(kind)
    if kind=="BP_WOP1007_f18c_C" then return H.planes end
    if kind=="LivePlayerController" then return {H.pc} end
    return {}
end
function StaticFindObject(path)
    return object("static:"..path,{}, {
        PrintString=function() end,
        -- Live-verified MakeRotator order is Roll, Pitch, Yaw; result uses
        -- reflected lowercase pitch, matching this game's Rotator metadata.
        MakeRotator=function(_,roll,pitch,yaw) return {Roll=roll,pitch=pitch,Yaw=yaw} end,
    })
end
PropertyTypes={ByteProperty=1,FloatProperty=2}
function RegisterCustomProperty(_) H.registered=(H.registered or 0)+1 end
EngineTickAvailable=true
Key={F6="F6",F7="F7",F9="F9"}
function RegisterKeyBind(key,fn) H.bindings[key]=fn end
function ExecuteInGameThread(fn) fn() end
function ExecuteInGameThreadWithDelay(ms,fn)
    local timer={at=H.now+ms,fn=fn}; H.timers[#H.timers+1]=timer; return timer
end
function LoopInGameThreadAfterFrames(frames,fn)
    assert(frames==1)
    local loop={fn=fn,canceled=false}; H.loops[#H.loops+1]=loop; return loop
end
function CancelDelayedAction(action) action.canceled=true end
function H.press(key) assert(H.bindings[key],"unbound "..key)() end
function H.frame()
    for _,loop in ipairs(H.loops) do if not loop.canceled then loop.fn() end end
end
function H.advance(ms)
    local endtime=H.now+ms
    while true do
        local found
        for _,timer in ipairs(H.timers) do
            if not timer.fired and timer.at<=endtime and (not found or timer.at<found.at) then found=timer end
        end
        if not found then break end
        H.now=found.at; found.fired=true; found.fn()
    end
    H.now=endtime
end
function H.ready() H.files["mock/manual-ready.txt"]="stamp" end
function H.fail(kind,key,value,count) H.failures[kind..":"..key]={value=value,remaining=count or 1} end
function H.assert_restored()
    assert(AC8ManualControl.active==nil,"active ownership remains")
    assert(H.pc:GetViewTarget()==H.view,"original view not restored")
    assert(H.pc.bAutoManageActiveCameraTarget==true,"camera policy not restored")
    for key,value in pairs(H.original_player) do assert(H.player[key]==value,"player "..key) end
    for i,plane in ipairs(H.planes) do
        assert(H.components[i].AC8ManualEnable==1,"AI remains off")
        for key,value in pairs(H.original_ai[i]) do assert(plane[key]==value,"AI "..key) end
    end
    for _,camera in ipairs(H.cameras) do assert(not camera:IsValid(),"camera leaked") end
end
local real_getenv=os.getenv
os.getenv=function(key) if key=="AC8_COOP_MANUAL" then return "25201480" end; return real_getenv(key) end
io.open=function(path,mode)
    if mode=="r" and H.files[path]==nil then return nil end
    if mode=="w" then H.files[path]="" end
    local f={}
    function f:write(...)
        local items={...}; for i,value in ipairs(items) do items[i]=tostring(value) end
        H.files[path]=(H.files[path] or "")..table.concat(items); return self
    end
    function f:read(_) return H.files[path] end
    function f:close() end
    return f
end
print=function() end
