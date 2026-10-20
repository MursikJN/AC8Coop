-- Read-only reconnaissance probe v0.4 with an explicit reloadable diagnostic extension.
-- Activate only in an explicitly prepared offline research session.
if os.getenv("AC8_COOP_RECON") ~= "1" then
    print("[AC8CoopRecon] Inactive: research-session marker is absent.\n")
    return
end
local output_dir = os.getenv("AC8_COOP_RECON_OUTPUT")
if not output_dir or output_dir == "" then
    print("[AC8CoopRecon] Inactive: output directory is absent.\n")
    return
end

local busy = false
local serial = 0
local function clean(value)
    return tostring(value):gsub("[\r\n\t]", " ")
end
local function object_name(object)
    if object == nil then return "nil" end
    local ok, result = pcall(function()
        if not object:IsValid() then return "invalid" end
        return object:GetFullName()
    end)
    return ok and clean(result) or "unavailable"
end
local function property(object, key)
    local ok, result = pcall(function() return object[key] end)
    if not ok then return "unavailable" end
    local kind = type(result)
    if kind == "boolean" or kind == "number" or kind == "string" then
        return clean(result)
    end
    return object_name(result)
end

local function capture()
    serial = serial + 1
    local stamp = os.date("%Y%m%d-%H%M%S") .. "-" .. serial
    local filename = output_dir .. "/snapshot-" .. stamp .. ".tsv"
    local file, error_message = io.open(filename, "w")
    if not file then error("Cannot open snapshot: " .. tostring(error_message)) end
    local schema, schema_error = io.open(output_dir .. "/schema-" .. stamp .. ".tsv", "w")
    if not schema then file:close(); error(tostring(schema_error)) end
    local inventory, inventory_error = io.open(output_dir .. "/actor-classes-" .. stamp .. ".tsv", "w")
    if not inventory then schema:close(); file:close(); error(tostring(inventory_error)) end
    local links, links_error = io.open(output_dir .. "/links-" .. stamp .. ".tsv", "w")
    if not links then inventory:close(); schema:close(); file:close(); error(tostring(links_error)) end
    local ok, problem = pcall(function()
        file:write("# AC8CoopRecon v0.4; observations only; no possession or gameplay edits\n")
        file:write("kind\tobject\tclass\tController\tPawn\tPlayerState\tRole\tRemoteRole\tbReplicates\tbReplicateMovement\n")
        schema:write("kind\towner_class\tname\tdetail\n")
        inventory:write("class\tcount\n")
        links:write("object\tfield\tstatus\tvalue\n")
        local seen = {}
        local classes = {}
        local function register_class(object)
            local ok_class, class = pcall(function() return object:GetClass() end)
            if ok_class and class and class:IsValid() then classes[object_name(class)] = class end
        end
        local function link_row(owner, key, status, value)
            links:write(clean(owner),"\t",clean(key),"\t",clean(status),"\t",clean(value),"\n")
        end
        -- This allowlist comes from the v0.2 metadata. No guessed memory offsets.
        local function read_field(object, owner, key, expected)
            local read_ok, value = pcall(function() return object[key] end)
            if not read_ok then link_row(owner,key,"read_error",value); return end
            if value == nil then link_row(owner,key,"nil",""); return end
            if expected == "object" then
                local label = object_name(value)
                link_row(owner,key,label == "invalid" and "null_or_invalid" or "object",label)
                if label ~= "invalid" and label ~= "unavailable" then register_class(value) end
            elseif expected == "string" then
                local string_ok, rendered = pcall(function()
                    if type(value) == "string" then return value end
                    return value:ToString()
                end)
                link_row(owner,key,string_ok and "string" or "string_error",rendered)
            elseif expected == "array" then
                local array_ok, array_error = pcall(function()
                    local total = value:GetArrayNum()
                    link_row(owner,key,"array_count",total)
                    -- ForEach uses GetParam, unsupported for these WeakObjectProperty arrays.
                    -- Indexed access is 1-based; FWeakObjectPtr:Get is documented separately.
                    for index = 1, math.min(total,16) do
                        local weak = value[index]
                        local target = weak:Get()
                        link_row(owner,key .. "[" .. tostring(index) .. "]","weak_object",object_name(target))
                        register_class(target)
                    end
                    if total > 16 then link_row(owner,key,"array_capped",16) end
                end)
                if not array_ok then link_row(owner,key,"array_error",array_error) end
            else
                local kind = type(value)
                if kind == "number" or kind == "boolean" or kind == "string" then
                    link_row(owner,key,kind,value)
                else
                    link_row(owner,key,"unsupported_value_type",kind)
                end
            end
        end
        local function emit(kind, object)
            local name = object_name(object)
            if name == "nil" or name == "invalid" or name == "unavailable" then return end
            if seen[name] then return end
            seen[name] = true
            local class_ok, class = pcall(function() return object:GetClass() end)
            if class_ok and class and class:IsValid() then classes[object_name(class)] = class end
            local row = {kind, name, class_ok and object_name(class) or "unavailable"}
            for _, key in ipairs({"Controller", "Pawn", "PlayerState", "Role", "RemoteRole", "bReplicates", "bReplicateMovement"}) do
                row[#row + 1] = property(object, key)
            end
            file:write(table.concat(row, "\t"), "\n")
            local class_name = class_ok and object_name(class) or ""
            local is_plane = class_name:find("/AI/Wingman/",1,true)
                or class_name:find("/Player/Plane/",1,true)
                or class_name:find("/AI/Plane/OP1007_f18c/",1,true)
            if is_plane then
                for _, key in ipairs({"GameObjectId","GameObjectSubId","Faction","bIsActivated","bIsIGCActor","Speed","HealthInternal"}) do
                    read_field(object,name,key,"primitive")
                end
                read_field(object,name,"CallsignId","string")
                read_field(object,name,"ObjNameID","string")
                read_field(object,name,"NetworkObject","object")
                if class_name:find("/AI/Wingman/",1,true) then
                    for _, key in ipairs({"RoleCategory","bIsAnimationPlane","OverrideFlightEngineID"}) do read_field(object,name,key,"primitive") end
                    for _, key in ipairs({"AIWingmanStateComponent","WingmanSystemComponent","AIStateComponent","FireControlSystemComponent","AIPathTracker"}) do read_field(object,name,key,"object") end
                end
            elseif class_name:find("BP_WingmanUnit",1,true) then
                for _, key in ipairs({"RootAIGameObjects","ChildAIGameObjects","GroupLeadPlanes"}) do read_field(object,name,key,"array") end
                for _, key in ipairs({"UnitMovement","AIPathTracker","NetworkObject"}) do read_field(object,name,key,"object") end
            end
        end
        for _, kind in ipairs({"PlayerController", "AIController", "Controller", "Pawn", "GameModeBase", "GameStateBase"}) do
            local found_ok, objects = pcall(FindAllOf, kind)
            local visited = 0
            if found_ok and objects then
                for _, object in pairs(objects) do
                    visited = visited + 1
                    if visited > 128 then break end
                    emit(kind, object)
                end
            end
            file:write("# group=", kind, " visited=", tostring(math.min(visited,128)), " capped=", tostring(visited>128), " query_ok=", tostring(found_ok), "\n")
        end
        -- Match the class, never the mission path (which matches every actor).
        local actor_ok, actors = pcall(FindAllOf, "Actor")
        local visited, retained = 0, 0
        local class_counts = {}
        if actor_ok and actors then
            for _, object in pairs(actors) do
                visited = visited + 1
                if visited > 20000 then break end
                local class_ok, class = pcall(function() return object:GetClass() end)
                local name = class_ok and object_name(class) or "unavailable"
                class_counts[name] = (class_counts[name] or 0) + 1
                local short = name:match("[^%./]+$") or name
                short = short:lower()
                local candidate = false
                for _, token in ipairs({"plane", "aircraft", "fighter", "wingman", "squad", "pilot", "unit", "formation", "vehicle", "controller", "mission"}) do
                    if short:find(token, 1, true) then candidate = true; break end
                end
                if candidate and retained < 512 then
                    emit("ActorCandidate", object)
                    retained = retained + 1
                end
            end
        end
        file:write("# actor_scan visited=",tostring(math.min(visited,20000))," capped=",tostring(visited>20000)," retained=",tostring(retained)," candidate_cap_reached=",tostring(retained>=512)," query_ok=",tostring(actor_ok),"\n")
        local class_names = {}
        for name in pairs(class_counts) do class_names[#class_names+1] = name end
        table.sort(class_names)
        for _, name in ipairs(class_names) do inventory:write(clean(name),"\t",tostring(class_counts[name]),"\n") end
        inventory:write("# visited=",tostring(math.min(visited,20000))," capped=",tostring(visited>20000),"\n")

        -- Enumerate metadata only. No reflected game function is invoked.
        local dumped, count = {}, 0
        local schema_classes = {}
        for name in pairs(classes) do schema_classes[#schema_classes+1] = name end
        local function schema_priority(name)
            if name:find("Wingman",1,true) or name:find("AIState",1,true)
                or name:find("FireControl",1,true) or name:find("AIPath",1,true)
                or name:find("UnitMovement",1,true) then return 0 end
            if name:find("PlayerPlane",1,true) then return 1 end
            if name:find("Controller",1,true) then return 2 end
            if name:find("LiveGame",1,true) then return 3 end
            return 4
        end
        table.sort(schema_classes, function(a,b)
            local pa, pb = schema_priority(a), schema_priority(b)
            if pa == pb then return a < b end
            return pa < pb
        end)
        for _, class_name in ipairs(schema_classes) do
            local starting_class = classes[class_name]
            local class, depth = starting_class, 0
            while class and class:IsValid() and depth < 20 and count < 192 do
                local name = object_name(class)
                if dumped[name] then break end
                dumped[name] = true
                count = count + 1
                depth = depth + 1
                local metadata_ok, metadata_error = pcall(function()
                    local super = class:GetSuperStruct()
                    schema:write("parent\t",name,"\t",object_name(super),"\t\n")
                    local properties = 0
                    class:ForEachProperty(function(field)
                        properties = properties + 1
                        if properties > 512 then return true end
                        local field_name = clean(field:GetFName():ToString())
                        local field_type = clean(field:GetClass():GetFName():ToString())
                        schema:write("property\t",name,"\t",field_name,"\t",field_type," offset=",tostring(field:GetOffset_Internal()),"\n")
                    end)
                    local functions = 0
                    class:ForEachFunction(function(fn)
                        functions = functions + 1
                        if functions > 512 then return true end
                        local fn_name = clean(fn:GetFName():ToString())
                        schema:write("function\t",name,"\t",fn_name,"\t\n")
                        -- Enumerate fields, including possible return/local fields. Do not call fn.
                        if name:find("/Script/Live.",1,true) or name:find("/Game/Blueprints/AI/",1,true) then
                            local fields = 0
                            local fn_ok, fn_error = pcall(function()
                                schema:write("function_flags\t",name,"\t",fn_name,"\t",tostring(fn:GetFunctionFlags()),"\n")
                                fn:ForEachProperty(function(field)
                                    fields = fields + 1
                                    if fields > 32 then return true end
                                    schema:write("function_field\t",name,"::",fn_name,"\t",clean(field:GetFName():ToString()),"\t",clean(field:GetClass():GetFName():ToString())," offset=",tostring(field:GetOffset_Internal()),"\n")
                                end)
                                if fields > 32 then schema:write("# function_fields_capped class=",name," name=",fn_name,"\n") end
                            end)
                            if not fn_ok then schema:write("# function_metadata_error class=",name," name=",fn_name," error=",clean(fn_error),"\n") end
                        end
                    end)
                    schema:write("# class=",name," properties_capped=",tostring(properties>512)," functions_capped=",tostring(functions>512),"\n")
                end)
                if not metadata_ok then schema:write("# metadata_error class=",name," error=",clean(metadata_error),"\n"); break end
                class = class:GetSuperStruct()
            end
            if depth >= 20 then schema:write("# inheritance_depth_cap_reached\n") end
        end
        schema:write("# classes=",tostring(count)," class_cap_reached=",tostring(count>=192),"\n")
    end)
    links:close()
    inventory:close()
    schema:close()
    file:close()
    if not ok then error(problem) end
    print("[AC8CoopRecon] Saved " .. filename .. "\n")
    return stamp
end

RegisterKeyBind(Key.F8, function()
    if busy then return end
    busy = true
    local scheduled, schedule_error = pcall(ExecuteInGameThread, function()
        local ok, problem = pcall(capture)
        if ok then
            local stamp = problem
            local extension_path = os.getenv("AC8_COOP_RECON_EXTENSION")
            if extension_path and extension_path ~= "" then
                local extra_ok, extra_error = pcall(function()
                    -- Load only this configured local file, on an explicit F8 press.
                    local source_file = assert(io.open(extension_path,"r"))
                    local source = source_file:read("*a")
                    source_file:close()
                    local archive = assert(io.open(output_dir .. "/state-probe-" .. stamp .. ".lua","w"))
                    archive:write(source)
                    archive:close()
                    local chunk = assert(load(source,"@" .. extension_path,"t"))
                    local extension = chunk()
                    assert(type(extension) == "function", "Extension must return a function")
                    extension(output_dir,stamp)
                end)
                if not extra_ok then print("[AC8CoopRecon] State probe failed: " .. tostring(extra_error) .. "\n") end
            end
        end
        busy = false
        if not ok then print("[AC8CoopRecon] Capture failed: " .. tostring(problem) .. "\n") end
    end)
    if not scheduled then
        busy = false
        print("[AC8CoopRecon] Scheduling failed: " .. tostring(schedule_error) .. "\n")
    end
end)
print("[AC8CoopRecon] Ready: press F8 during an offline mission to record an object snapshot.\n")
