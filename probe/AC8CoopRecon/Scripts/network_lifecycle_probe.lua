-- Standalone metadata/instance inventory, called by main.lua on the game thread.
-- No cached experiment state, property writes, gameplay calls, hooks or timers.
return function(output_dir, stamp)
    local files = {}
    local function clean(v) return tostring(v):gsub("[\r\n\t]", " ") end
    local function open(name)
        local file = assert(io.open(output_dir .. "/" .. name .. "-" .. stamp .. ".tsv", "w"))
        files[#files + 1] = file
        return file
    end
    local report, addresses
    local function row(kind, owner, name, value)
        report:write(clean(kind), "\t", clean(owner), "\t", clean(name), "\t", clean(value), "\n")
    end
    local function attempt(owner, operation, fn)
        local ok, result = pcall(fn)
        if not ok then row("error", owner, operation, result) end
        return ok, result
    end
    local function valid(obj)
        if obj == nil then return false end
        local ok, result = pcall(function() return obj:IsValid() end)
        return ok and result == true
    end
    local function label(obj) return valid(obj) and obj:GetFullName() or "invalid" end
    local function hex(obj) return string.format("0x%X", obj:GetAddress()) end
    local roots = {
        LivePlayerPlane=true, LiveGameObject=true, LiveGameInstance=true,
        LiveGameMode=true, LiveOnlineGameMode=true, LiveTeamDeathMatchGameMode=true,
        LivePlayerController=true,
    }
    -- Exact native names observed in this build's EXE; lookup does not load assets.
    -- FindAllOf is an instance search and returned nil for Class in the live run.
    local native_network_names = {
        "LiveNetworkAIAlicorn", "LiveNetworkAIAlicornHatch", "LiveNetworkAIArrangement",
        "LiveNetworkAIChandelier", "LiveNetworkAICity", "LiveNetworkAICruiseMissile",
        "LiveNetworkAICruiseMissileImpactPoint", "LiveNetworkAIGameObject", "LiveNetworkAIGroundVehicle",
        "LiveNetworkAIHeli", "LiveNetworkAIHelios", "LiveNetworkAIPlane", "LiveNetworkAIRailgun",
        "LiveNetworkAIStauros", "LiveNetworkAircraftSelector", "LiveNetworkAvatarObject",
        "LiveNetworkBaseObject", "LiveNetworkCenturionObject", "LiveNetworkCheatManager",
        "LiveNetworkCompetitiveCoopGameMode", "LiveNetworkCoopGameMode", "LiveNetworkDebugCommand",
        "LiveNetworkDummyController", "LiveNetworkEmergencyCallAceBattleGameMode",
        "LiveNetworkEmergencyCallGameMode", "LiveNetworkGameMode", "LiveNetworkGameObject",
        "LiveNetworkGuildObject", "LiveNetworkManager", "LiveNetworkP2P", "LiveNetworkPVPVEGameMode",
        "LiveNetworkPlayerPlane", "LiveNetworkResultManager", "LiveNetworkResultObject",
        "LiveNetworkSessionErrorDialog", "LiveNetworkSimplePlayerResponseObject",
        "LiveNetworkSubmarineBase", "LiveNetworkSystemObject", "LiveNetworkTrafficLog", "LiveNetworkUnit",
    }
    local function root_kind(class)
        local name = label(class):match("^Class /Script/Live%.([^ ]+)$")
        if not name then return nil end
        if name:find("LiveNetwork", 1, true) == 1 then return "network" end
        if roots[name] then return name end
    end
    local scalar_types = {
        BoolProperty=true, ByteProperty=true, IntProperty=true, Int8Property=true,
        Int16Property=true, Int64Property=true, UInt16Property=true, UInt32Property=true,
        UInt64Property=true, FloatProperty=true, DoubleProperty=true, EnumProperty=true,
        NameProperty=true, StrProperty=true,
    }
    local reference_types = {ObjectProperty=true, ClassProperty=true}
    local references = {
        NetworkObject=true, NetworkManager_=true, NetworkP2P_=true,
        Controller=true, Pawn=true, PlayerState=true,
    }
    local function selected_scalar(name)
        local lower = name:lower()
        for _, word in ipairs({"identity", "id", "state", "ready", "owner", "local", "remote",
            "network", "online", "session", "activated", "connected", "authority", "role", "callsign"}) do
            if lower:find(word, 1, true) then return true end
        end
        return false
    end
    local schemas, function_seen, instance_seen = {}, {}, {}
    local instance_count = 0
    local function fields(struct, owner, kind, cap, keep)
        local count = 0
        struct:ForEachProperty(function(field)
            count = count + 1
            if count > cap then return true end
            attempt(owner, kind .. "_field", function()
                local name = field:GetFName():ToString()
                local typ = field:GetClass():GetFName():ToString()
                row(kind, owner, name, typ .. " offset=" .. field:GetOffset_Internal())
                if keep then keep[#keep + 1] = {name=name, typ=typ} end
            end)
        end)
        if count > cap then row("limit", owner, kind, cap) end
    end
    local function schema(class)
        local owner = label(class)
        if schemas[owner] then return schemas[owner] end
        local properties = {}
        schemas[owner] = properties
        row("class", owner, "address", hex(class))
        attempt(owner, "parent", function() row("parent", owner, "super", label(class:GetSuperStruct())) end)
        attempt(owner, "properties", function() fields(class, owner, "property", 256, properties) end)
        attempt(owner, "functions", function()
            local count = 0
            class:ForEachFunction(function(fn)
                count = count + 1
                if count > 256 then return true end
                attempt(owner, "function", function()
                    local name = label(fn)
                    row("function", owner, name, "flags=" .. fn:GetFunctionFlags() .. " address=" .. hex(fn))
                    if not function_seen[name] then
                        function_seen[name] = true
                        addresses:write("ufunction\t", clean(name), "\t", hex(fn), "\n")
                    end
                    attempt(name, "arguments", function() fields(fn, name, "argument", 32) end)
                end)
            end)
            if count > 256 then row("limit", owner, "functions", 256) end
        end)
        return properties
    end
    local function hierarchy(class, owner)
        local chain, seen = {}, {}
        while valid(class) do
            if #chain >= 16 then row("limit", owner, "hierarchy", 16); break end
            local key = hex(class)
            if seen[key] then row("error", owner, "hierarchy", "cycle"); break end
            seen[key] = true
            chain[#chain + 1] = class
            class = class:GetSuperStruct()
        end
        return chain
    end
    local function snapshot(obj)
        if not valid(obj) then row("instance", "invalid", "skipped", "invalid_handle"); return end
        local owner, key = label(obj), hex(obj)
        if instance_seen[key] then return end
        instance_seen[key] = true
        instance_count = instance_count + 1
        row("instance", owner, "address", key)
        local class = obj:GetClass()
        row("instance_class", owner, "class", label(class))
        local read = {}
        for _, ancestor in ipairs(hierarchy(class, owner)) do
            local network_declaring_class = root_kind(ancestor) == "network"
            for _, field in ipairs(schema(ancestor)) do
                local name, typ = field.name, field.typ
                if not read[name] then
                    read[name] = true
                    if scalar_types[typ] and selected_scalar(name) then
                        attempt(owner, "read:" .. name, function()
                            if not valid(obj) then error("instance_invalidated") end
                            local value = obj[name] -- Only after reflected schema confirms the field.
                            if typ == "NameProperty" or typ == "StrProperty" then value = value:ToString() end
                            row("value", owner, name, value)
                        end)
                    elseif reference_types[typ] and (network_declaring_class or references[name] or name:lower():find("network", 1, true)) then
                        attempt(owner, "read:" .. name, function()
                            if not valid(obj) then error("instance_invalidated") end
                            local value = obj[name]
                            row("reference", owner, name, label(value) .. (valid(value) and " address=" .. hex(value) or ""))
                        end)
                    end
                end
            end
        end
    end
    local ok, problem = pcall(function()
        report = open("network-lifecycle")
        addresses = open("network-native-addresses")
        report:write("kind\towner\tname\tvalue\n")
        addresses:write("kind\tname\taddress\n")
        row("meta", "probe", "mode", "read_only; fresh_capture; loaded_metadata_only; no_native_calls")
        row("meta", "probe", "address_kind", "UFunction object addresses, not native function pointers; current process only")
        local query_ok, classes = attempt("Class", "query", function() return FindAllOf("Class") or {} end)
        if not query_ok then return end
        row("query", "Class", "count", #classes)
        if #classes == 0 then
            row("meta", "probe", "discovery", "exact_native_paths; bounded_build_specific_seeds; not_all_loaded_classes")
            local names = {}
            for name in pairs(roots) do names[#names + 1] = name end
            for _, name in ipairs(native_network_names) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local path = "/Script/Live." .. name
                local found, class = attempt(path, "static_lookup", function() return StaticFindObject(path) end)
                if found and valid(class) then
                    -- Reject an unexpected object before calling class-specific APIs.
                    if label(class) == "Class " .. path then classes[#classes + 1] = class
                    else row("error", path, "static_lookup_type", label(class)) end
                else row("lookup", path, "status", "not_loaded_or_unavailable") end
            end
            row("query", "StaticFindObject", "found", #classes)
        end
        local selected, seen, matched = {}, {}, 0
        local function before(a,b)
            if a.priority == b.priority then return a.name < b.name end
            return a.priority < b.priority
        end
        for i, class in ipairs(classes) do
            if i > 50000 then row("limit", "Class", "visited", 50000); break end
            attempt("Class", "select", function()
                if not valid(class) then return end
                local name = label(class)
                if seen[name] then return end
                seen[name] = true
                local match, priority = root_kind(class), 2
                if match == "network" then priority = 0 end
                if not match then
                    local candidate_name = class:GetFName():ToString():lower()
                    if not (candidate_name:find("playerplane", 1, true) or candidate_name:find("gamemode", 1, true)
                        or candidate_name:find("gameinstance", 1, true) or candidate_name:find("network", 1, true)) then return end
                    -- Every actor derives from LiveGameObject: that alone is not relevant.
                    for _, ancestor in ipairs(hierarchy(class, name)) do
                        local kind = root_kind(ancestor)
                        if kind and kind ~= "LiveGameObject" then match = kind; break end
                    end
                else priority = math.min(priority, 1) end
                if match then
                    matched = matched + 1
                    selected[#selected + 1] = {class=class, name=name, priority=priority}
                    -- Retain at most 128 handles, prioritizing native network and root classes.
                    if #selected > 128 then table.sort(selected, before); selected[129] = nil end
                end
            end)
        end
        table.sort(selected, before)
        row("query", "Class", "matched", matched)
        if matched == 0 then
            row("error", "probe", "discovery", "no_selected_classes")
            row("meta", "probe", "complete", false)
            return
        end
        if matched > 128 then row("limit", "Class", "matched", 128) end
        for i, entry in ipairs(selected) do
            if i > 128 then break end
            attempt(entry.name, "selected_class", function()
                for _, ancestor in ipairs(hierarchy(entry.class, entry.name)) do schema(ancestor) end
                if instance_count >= 128 then row("limit", entry.name, "instances_total", 128); return end
                local short = entry.class:GetFName():ToString()
                local found_ok, found = attempt(entry.name, "instances_query", function() return FindAllOf(short) or {} end)
                if not found_ok then return end
                row("query", entry.name, "instances", #found)
                for j, obj in ipairs(found) do
                    if j > 8 then row("limit", entry.name, "instances_per_class", 8); break end
                    if instance_count >= 128 then row("limit", entry.name, "instances_total", 128); break end
                    attempt(entry.name, "instance", function() snapshot(obj) end)
                end
            end)
        end
        row("meta", "probe", "instances", instance_count)
        row("meta", "probe", "complete", true)
    end)
    if not ok and report then pcall(function() row("error", "probe", "capture", problem) end) end
    local close_problem
    for _, file in ipairs(files) do
        local closed, err = pcall(function() assert(file:close()) end)
        if not closed then close_problem = close_problem or err end
    end
    if not ok then error(problem) end
    if close_problem then error(close_problem) end
    print("[AC8NetworkLifecycle] Saved read-only network inventory " .. stamp .. "\n")
end
