-- Read-only player-flight ownership discovery. No Spawn/Possess/FrameUpdate calls.
return function(output_dir,stamp)
    local s=assert(_G.AC8ManualControl,"Manual state absent")
    assert(s.restore("player_flight_discovery"),"Restore incomplete")
    s.busy=true -- Retire the rejected AI-axis experiment; F6/F7 handlers stay inert.
    local function valid(o) return o and o:IsValid() end
    local function label(o) return valid(o) and o:GetFullName() or "invalid" end
    local function clean(v) return tostring(v):gsub("[\r\n\t]"," ") end
    assert(valid(s.player) and s.player:GetWorld():GetAddress()==s.world_id,"Player/world changed")
    local f=assert(io.open(output_dir.."/player-flight-"..stamp..".tsv","w"))
    local a=assert(io.open(output_dir.."/player-native-addresses-"..stamp..".tsv","w"))
    a:write("kind\tname\taddress\n")
    local function row(kind,owner,name,value)
        f:write(clean(kind),"\t",clean(owner),"\t",clean(name),"\t",clean(value),"\n")
    end
    local scalars={BoolProperty=true,ByteProperty=true,IntProperty=true,FloatProperty=true,
        DoubleProperty=true,EnumProperty=true,Int64Property=true,UInt32Property=true}
    local address_seen,classes_seen,objects_seen={},{},{}
    local queue={}
    local function enqueue(o,depth)
        if not valid(o) or objects_seen[o:GetAddress()] then return end
        if #queue>=32 then row("limit",label(o),"objects",32); return end
        objects_seen[o:GetAddress()]=true; queue[#queue+1]={obj=o,depth=depth or 0}
    end
    local function selected(n)
        n=n:lower()
        for _,word in ipairs({"flight","input","frameupdate","felocation","directionmove","spawn","player","possess","initialize","setup"}) do
            if n:find(word,1,true) then return true end
        end
        return false
    end
    local function functions(class)
        local cname=label(class)
        if classes_seen[cname] then return end
        classes_seen[cname]=true
        local count=0
        class:ForEachFunction(function(fn)
            count=count+1; if count>512 then return true end
            local n=fn:GetFName():ToString()
            if not selected(n) then return end
            row("function",cname,n,"flags="..fn:GetFunctionFlags().." address="..string.format("0x%X",fn:GetAddress()))
            local fn_name=label(fn)
            if cname:find("/Script/Live.",1,true) and not address_seen[fn_name] then
                address_seen[fn_name]=true
                a:write("ufunction\t",clean(fn_name),"\t",string.format("0x%X",fn:GetAddress()),"\n")
            end
            local args=0
            fn:ForEachProperty(function(p)
                args=args+1; if args>32 then return true end
                row("argument",fn_name,p:GetFName():ToString(),p:GetClass():GetFName():ToString().." offset="..p:GetOffset_Internal())
            end)
        end)
        if count>512 then row("limit",cname,"functions",512) end
    end
    local function struct_values(value,owner,depth)
        if depth>2 then row("limit",owner,"struct_depth",2); return end
        assert(value:IsMappedToObject(),"Struct has no instance data")
        row("struct",owner,"address",string.format("0x%X",value:GetStructAddress()))
        local count=0
        value:ForEachProperty(function(p)
            count=count+1; if count>128 then return true end
            local n=p:GetFName():ToString(); local t=p:GetClass():GetFName():ToString()
            row("struct_schema",owner,n,t.." offset="..p:GetOffset_Internal())
            local read_ok,read_error=pcall(function()
                if scalars[t] then row("struct_value",owner,n,value[n])
                elseif t=="StructProperty" then struct_values(value[n],owner.."."..n,depth+1) end
            end)
            if not read_ok then row("read_error",owner,n,read_error) end
        end)
        if count>128 then row("limit",owner,"struct_fields",128) end
    end
    local ok,err=pcall(function()
        row("meta","probe","mode","read_only; manual AI-axis experiment retired")
        enqueue(s.player); enqueue(s.pc); enqueue(s.pc.PlayerInput)
        enqueue(s.player.InputComponent); enqueue(s.player.LocalUserSettings); enqueue(s.player.UpgradeParts)
        for _,slot in ipairs(s.slots) do enqueue(slot.plane) end
        for _,kind in ipairs({"GameModeBase","GameInstance","BP_DefaultUnitSpawner_C"}) do
            local found=FindAllOf(kind) or {}
            row("query",kind,"count",#found)
            for i,obj in ipairs(found) do if i>4 then row("limit",kind,"instances",4); break end; enqueue(obj) end
        end
        local cursor=1
        while cursor<=#queue do
            local entry=queue[cursor]; cursor=cursor+1
            local obj,owner=entry.obj,label(entry.obj)
            row("object",owner,"address",string.format("0x%X",obj:GetAddress()))
            local class,depth=obj:GetClass(),0
            while valid(class) and depth<14 do
                depth=depth+1
                local count=0
                class:ForEachProperty(function(p)
                    count=count+1; if count>384 then return true end
                    local n=p:GetFName():ToString(); local t=p:GetClass():GetFName():ToString()
                    row("schema",label(class),n,t.." offset="..p:GetOffset_Internal())
                    local read_ok,read_error=pcall(function()
                        if scalars[t] and selected(n) then row("value",owner,n,obj[n]) end
                        if t=="ObjectProperty" or t=="ClassProperty" then
                            local v=obj[n]; row("reference",owner,n,label(v))
                            if t=="ObjectProperty" and entry.depth<1 and
                                (n=="MissionConfig" or n=="PlugHolder" or n:find("Player",1,true) or n:find("Flight",1,true)) then enqueue(v,entry.depth+1) end
                        elseif t=="StructProperty" and (n=="FlightSystemData" or n=="FlightStickData") then
                            struct_values(obj[n],owner.."."..n,0)
                        elseif t=="ArrayProperty" and n=="LoadedPlayerPawnAssets" then
                            local array=obj[n]; local total=array:GetArrayNum()
                            row("array_count",owner,n,total)
                            for i=1,math.min(total,16) do
                                local value=array[i]
                                local name_ok,name=pcall(label,value)
                                row("array_item",owner,n.."["..i.."]",name_ok and name or "unsupported_element_type")
                            end
                            if total>16 then row("limit",owner,n,16) end
                        end
                    end)
                    if not read_ok then row("read_error",owner,n,read_error) end
                end)
                if count>384 then row("limit",owner,"properties",384) end
                functions(class); class=class:GetSuperStruct()
            end
        end
        -- Inventory loaded metadata only; do not load assets or create instances.
        for _,kind in ipairs({"Class","ScriptStruct"}) do
            local found=FindAllOf(kind) or {}; local matched=0
            row("query",kind,"count",#found)
            for i,obj in ipairs(found) do
                if i>50000 then row("limit",kind,"visited",50000); break end
                local n=label(obj); local lower=n:lower()
                if n:find("/Script/Live.",1,true) and
                    (lower:find("flight",1,true) or lower:find("playerplane",1,true) or lower:find("aibot",1,true)
                    or lower:find("playerspawn",1,true) or lower:find("unitspawner",1,true)) then
                    matched=matched+1; if matched>128 then row("limit",kind,"matched",128); break end
                    row("loaded_type",kind,n,string.format("0x%X",obj:GetAddress()))
                    if kind=="Class" then functions(obj) end
                    local fields=0
                    obj:ForEachProperty(function(p)
                        fields=fields+1; if fields>256 then return true end
                        row("type_schema",n,p:GetFName():ToString(),p:GetClass():GetFName():ToString().." offset="..p:GetOffset_Internal())
                    end)
                    if fields>256 then row("limit",n,"fields",256) end
                end
            end
            row("query",kind,"matched",matched)
        end
        row("meta","probe","objects",#queue)
    end)
    f:close(); a:close()
    if not ok then error(err) end
    print("[AC8PlayerFlight] Saved read-only player-flight discovery "..stamp.."; F6/F7 retired.\n")
end
