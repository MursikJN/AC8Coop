-- Boundary mocks only, not Unreal initialization or lifecycle simulation.
local object=H.object
H.spawned={}; H.destroyed=0
H.class=object("class",{fullname="Class /Game/PP0023_f14d/BP_PlayerPlane_PP0023_f14d_C"})
H.player.GetClass=function() return H.class end
H.player.K2_GetActorLocation=function() return {X=1,Y=2,Z=3} end
H.player.Controller=H.pc
H.writes={}
AC8ManualControl={player=H.player,pc=H.pc,world_id=H.world:GetAddress(),slots={},restore=function() return true end}
for i=1,3 do AC8ManualControl.slots[i]={id="Joker"..(i+1),plane=H.planes[i],component=H.components[i]} end
local original_find=FindAllOf
function FindAllOf(kind)
    if kind=="BP_PlayerPlane_PP0023_f14d_C" then
        local found={H.player}
        for _,actor in ipairs(H.spawned) do if actor:IsValid() then found[#found+1]=actor end end
        return found
    end
    return original_find(kind)
end
H.stale_accesses=0
function H.poison_cached_components()
    for _,slot in ipairs(AC8ManualControl.slots) do
        slot.component=setmetatable({}, {__index=function(_,key)
            H.stale_accesses=H.stale_accesses+1; error("stale component dereference: "..key)
        end})
    end
end
local signatures={
    BeginDeferredActorSpawnFromClass={{"WorldContextObject","ObjectProperty"},{"ActorClass","ClassProperty"},
        {"SpawnTransform","StructProperty"},{"CollisionHandlingOverride","ByteProperty"},
        {"Owner","ObjectProperty"},{"TransformScaleMethod","ByteProperty"},{"ReturnValue","ObjectProperty"}},
    MakeTransform={{"Location","StructProperty"},{"Rotation","StructProperty"},{"Scale","StructProperty"},{"ReturnValue","StructProperty"}},
    K2_DestroyActor={},
}
H.signatures=signatures
local statics=object("statics",{}, {
    BeginDeferredActorSpawnFromClass=function(_,context,class,transform,collision,owner,scale)
        assert(context==H.player and class==H.class and transform==H.transform)
        assert(collision==4 and owner==nil and scale==1)
        H.spawn_calls=(H.spawn_calls or 0)+1
        if H.return_actor then return H.return_actor end
        local actor,data
        actor,data=object("created",{bActorIsBeingDestroyed=false},{
            GetClass=function() return H.class end,
            K2_DestroyActor=function()
                if H.destroy_fails then error("injected destroy failure") end
                H.destroyed=H.destroyed+1
                if H.destroy_pending then data.bActorIsBeingDestroyed=true else data.alive=false end
            end,
        })
        if H.bad_controller then data.Controller=H.pc end
        H.spawned[#H.spawned+1]=actor
        return actor
    end,
})
local mathlib=object("mathlib",{}, {
    MakeRotator=function(_,r,p,y) return {Roll=r,pitch=p,Yaw=y} end,
    MakeTransform=function(_,p,r,s)
        assert(p.X==1 and p.Y==2 and p.Z==30003 and s.X==1 and r.pitch==0)
        H.transform={location=p,rotation=r,scale=s}; return H.transform
    end,
})
function StaticFindObject(path)
    if path:find("Default__GameplayStatics",1,true) then return statics end
    if path:find("Default__KismetMathLibrary",1,true) then return mathlib end
    if path:find("ESpawnActor",1,true) then
        return object("enum",{}, {ForEachName=function(_,fn)
            fn(FName("Test::DontSpawnIfColliding"),4); fn(FName("Test::MultiplyWithRoot"),1)
        end})
    end
    local fields=signatures[path:match(":([^:]+)$")]
    assert(fields,"Unexpected function requested: "..path)
    return object("function",{}, {ForEachProperty=function(_,fn)
        for i,f in ipairs(fields) do
            fn({GetFName=function() return FName(f[1]) end,
                GetClass=function() return {GetFName=function() return FName(f[2]) end} end,
                GetStruct=function()
                    local types={SpawnTransform="Transform",Location="Vector",Rotation="Rotator",Scale="Vector",ReturnValue="Transform"}
                    return object("struct",{fullname="ScriptStruct /Script/CoreUObject."..(H.wrong_struct or types[f[1]])})
                end,
                GetOffset_Internal=function() return i*16 end})
        end
    end})
end
function H.spawn_ready() H.files["mock/spawn-ready.txt"]="stamp" end
