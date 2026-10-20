-- Menu inventory on explicit F8, with fresh objects each time. No UI actions.
return function(output_dir, stamp)
    local file = assert(io.open(output_dir .. "/menus-" .. stamp .. ".tsv", "w"))
    local errors, limits, instances, class_count = 0, 0, 0, 0
    local seen, schemas = {}, {}
    local function clean(v) return tostring(v):gsub("[\r\n\t]", " "):sub(1, 1500) end
    local function row(kind, owner, name, value)
        file:write(clean(kind), "\t", clean(owner), "\t", clean(name), "\t", clean(value), "\n")
    end
    local function attempt(owner, name, fn)
        local ok, value = pcall(fn)
        if not ok then errors = errors + 1; row("error", owner, name, value) end
        return ok, value
    end
    local function valid(o)
        if o == nil then return false end
        local ok, value = pcall(function() return o:IsValid() end)
        return ok and value == true
    end
    local function label(o) return valid(o) and o:GetFullName() or "invalid" end
    local function cap(owner, name, value)
        limits = limits + 1; row("limit", owner, name, value)
    end
    local function selected(name)
        local n = name:lower()
        for _, secret in ipairs({"token", "password", "auth", "account", "chat", "friend", "userid", "steamid"}) do
            if n:find(secret, 1, true) then return false end
        end
        for _, word in ipairs({"menu", "widget", "screen", "current", "previous", "focus", "select", "state",
            "visible", "visibility", "enabled", "title", "text", "command", "campaign", "mission", "difficulty", "root", "slot"}) do
            if n:find(word, 1, true) then return true end
        end
        return false
    end
    local scalar = {BoolProperty=true, ByteProperty=true, EnumProperty=true, IntProperty=true,
        UInt32Property=true, FloatProperty=true, NameProperty=true, StrProperty=true, TextProperty=true}
    local function schema(class)
        local name = label(class)
        if schemas[name] then return schemas[name] end
        if class_count >= 192 then schemas[name] = {}; cap(name, "class_limit", 192); return schemas[name] end
        class_count = class_count + 1
        local fields = {}; schemas[name] = fields
        row("class", name, "parent", label(class:GetSuperStruct()))
        attempt(name, "properties", function()
            local count = 0
            class:ForEachProperty(function(p)
                count = count + 1
                if count > 256 then cap(name, "properties", 256); return true end
                local pn, pt = p:GetFName():ToString(), p:GetClass():GetFName():ToString()
                row("property", name, pn, pt .. " offset=" .. p:GetOffset_Internal())
                if selected(pn) then fields[#fields + 1] = {name=pn, typ=pt} end
            end)
        end)
        -- Only list declared callbacks/functions. Never execute a game menu function.
        if name:find("Live", 1, true) or name:find("/Game/", 1, true) then
            attempt(name, "functions", function()
                local count = 0
                class:ForEachFunction(function(fn)
                    count = count + 1
                    if count > 256 then cap(name, "functions", 256); return true end
                    row("function", name, fn:GetFName():ToString(), "metadata_only")
                end)
            end)
        end
        return fields
    end
    local function snapshot(obj, query)
        if not valid(obj) then return end
        local key, owner = tostring(obj:GetAddress()), label(obj)
        if seen[key] then return end
        if instances >= 768 then cap(query, "instance_limit", 768); return end
        seen[key] = true; instances = instances + 1
        local class = obj:GetClass()
        row("instance", owner, query, label(class))
        row("address", owner, "session_only", key)
        local read, chain = {}, {}
        for depth = 1, 16 do
            if not valid(class) then break end
            local ck = label(class)
            if chain[ck] then row("error", owner, "hierarchy", "cycle"); errors = errors + 1; break end
            chain[ck] = true
            for _, field in ipairs(schema(class)) do
                if not read[field.name] then
                    read[field.name] = true
                    local typ, fn = field.typ, field.name
                    if scalar[typ] or typ == "ObjectProperty" or typ == "ClassProperty" then
                        attempt(owner, fn, function()
                            local value = obj[fn]
                            if typ == "ObjectProperty" or typ == "ClassProperty" then
                                row("reference", owner, fn, label(value))
                            elseif type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
                                row("value", owner, fn, value)
                            elseif value ~= nil and (typ == "NameProperty" or typ == "TextProperty" or typ == "StrProperty") then
                                row("value", owner, fn, value:ToString())
                            else row("unread_value", owner, fn, type(value)) end
                        end)
                    end
                end
            end
            class = class:GetSuperStruct()
            if depth == 16 and valid(class) then cap(owner, "hierarchy", 16) end
        end
    end
    local ok, problem = pcall(function()
        file:write("kind\towner\tname\tvalue\n")
        row("probe", "menu", "version", "0.1.1")
        row("scope", "menu", "visibility", "Loaded widget inventory and reflected values; not proof a widget is on screen. No screenshot, IsInViewport call or UI action.")
        row("scope", "menu", "selection", "All queried menu roots; UserWidget shallow inventory, details only for campaign/hangar/briefing/main-list and root-manager classes. Other loaded widgets intentionally excluded from details.")
        -- Native menu names are observed in the current EXE. UserWidget includes subclasses.
        for _, name in ipairs({"LiveMenuBase", "LiveStackedMenu", "LiveGameInstance", "UserWidget"}) do
            attempt(name, "query", function()
                local values = FindAllOf(name) or {}
                row("query", name, "count", #values)
                for index, obj in ipairs(values) do
                    if index > 4096 then cap(name, "inventory_budget", 4096); break end
                    attempt(name, "instance", function()
                        local include = name ~= "UserWidget"
                        if name == "UserWidget" and valid(obj) then
                            local cn = label(obj:GetClass())
                            row("inventory", label(obj), "class", cn)
                            for _, word in ipairs({"Campaign", "Hangar", "Briefing", "WBP_MenuCommon_MainList",
                                "WBP_Menu_Text_Focus", "WBP_Menu_MainTop", "WBP_RootMenuWidget", "WBP_NUIManager"}) do
                                if cn:find(word, 1, true) then include = true; break end
                            end
                        end
                        if include then snapshot(obj, name) end
                    end)
                    if instances >= 768 then cap(name, "query_budget", 768); break end
                end
            end)
        end
        if instances == 0 then row("incomplete", "menu", "reason", "empty_inventory") end
    end)
    if not ok then errors = errors + 1; row("error", "menu", "fatal", problem) end
    row("summary", "menu", "instances", instances)
    row("summary", "menu", "classes", class_count)
    row("summary", "menu", "errors", errors)
    row("summary", "menu", "limits", limits)
    row("summary", "menu", "complete_within_queries", ok and instances > 0 and errors == 0 and limits == 0)
    file:close()
    print("[AC8MenuProbe] Saved menus-" .. stamp .. ".tsv; instances=" .. instances .. "; errors=" .. errors .. "; limits=" .. limits .. "\n")
end
