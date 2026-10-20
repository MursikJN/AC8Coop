-- Read-only state discovery. Reloaded only on F8. Never invokes game functions.
return function(output_dir, stamp)
    local function clean(value) return tostring(value):gsub("[\r\n\t]"," ") end
    local function label(object)
        local ok, value = pcall(function()
            if not object or not object:IsValid() then return "invalid" end
            return object:GetFullName()
        end)
        return ok and clean(value) or "unavailable"
    end
    local file = assert(io.open(output_dir .. "/ai-state-" .. stamp .. ".tsv","w"))
    local function row(owner, class, field, kind, status, value)
        file:write(clean(owner),"\t",clean(class),"\t",clean(field),"\t",clean(kind),"\t",clean(status),"\t",clean(value),"\n")
    end
    local ok, error_message = pcall(function()
        file:write("object\tdeclaring_class\tfield\ttype\tstatus\tvalue\n")
        local queue, queued, cursor = {}, {}, 1
        local function enqueue(object, depth)
            local name = label(object)
            if name == "invalid" or name == "unavailable" or queued[name] then return end
            if #queue >= 64 then row(name,"","","limit","object_cap",64); return end
            queued[name] = true
            queue[#queue+1] = {object=object,name=name,depth=depth}
        end
        local wingmen = FindAllOf("BP_WOP1007_f18c_C") or {}
        local addresses = assert(io.open(output_dir .. "/native-addresses-" .. stamp .. ".tsv","w"))
        addresses:write("kind\tname\taddress\n")
        local address_ok, address_error = pcall(function()
            local emitted = {}
            local selected = {SetAIStateActive=true,InputPitch=true,InputRoll=true,InputYaw=true,AIFlightEngineTick=true}
            for index, plane in ipairs(wingmen) do
                if index > 8 then break end
                addresses:write("object\t",label(plane),"\t",string.format("0x%X",plane:GetAddress()),"\n")
                local class, depth = plane:GetClass(), 0
                while class and class:IsValid() and depth < 12 do
                    depth = depth + 1
                    class:ForEachFunction(function(fn)
                        local name = fn:GetFName():ToString()
                        if selected[name] and not emitted[label(fn)] then
                            emitted[label(fn)] = true
                            addresses:write("ufunction\t",label(fn),"\t",string.format("0x%X",fn:GetAddress()),"\n")
                        end
                    end)
                    class = class:GetSuperStruct()
                end
                local component = plane.AIStateComponent
                addresses:write("object\t",label(component),"\t",string.format("0x%X",component:GetAddress()),"\n")
                local behavior = component.RootBehavior
                if behavior and behavior:IsValid() then addresses:write("object\t",label(behavior),"\t",string.format("0x%X",behavior:GetAddress()),"\n") end
            end
        end)
        addresses:close()
        if not address_ok then row("","","","error","address_metadata_error",address_error) end
        for index, plane in ipairs(wingmen) do
            if index > 8 then row("","","","limit","wingman_cap",8); break end
            local owner = label(plane)
            for _, key in ipairs({"CallsignId","ObjNameID"}) do
                local read_ok, value = pcall(function() return plane[key]:ToString() end)
                row(owner,"",key,"string",read_ok and "ok" or "read_error",value)
            end
            for _, key in ipairs({"AIStateComponent","AIWingmanStateComponent","WingmanSystemComponent"}) do
                local read_ok, value = pcall(function() return plane[key] end)
                row(owner,"",key,"ObjectProperty",read_ok and "reference" or "read_error",read_ok and label(value) or value)
                if read_ok then enqueue(value,0) end
            end
        end
        local scalar_types = {BoolProperty=true,IntProperty=true,Int8Property=true,Int16Property=true,Int64Property=true,UInt16Property=true,UInt32Property=true,UInt64Property=true,FloatProperty=true,DoubleProperty=true,ByteProperty=true,EnumProperty=true}
        while cursor <= #queue do
            local entry = queue[cursor]
            cursor = cursor + 1
            local object_ok, object_error = pcall(function()
                local class = entry.object:GetClass()
                local depth, visited = 0, {}
                while class and class:IsValid() and depth < 12 do
                    depth = depth + 1
                    local class_name = label(class)
                    if visited[class_name] then break end
                    visited[class_name] = true
                    row(entry.name,class_name,"super","class","reference",label(class:GetSuperStruct()))
                    local count = 0
                    class:ForEachProperty(function(field)
                        count = count + 1
                        if count > 128 then return true end
                        local name = field:GetFName():ToString()
                        local kind = field:GetClass():GetFName():ToString()
                        local should_read = scalar_types[kind] or kind == "StrProperty" or kind == "NameProperty" or kind == "ObjectProperty"
                        if not should_read then row(entry.name,class_name,name,kind,"not_read",""); return end
                        local value_ok, value = pcall(function() return entry.object[name] end)
                        if not value_ok then row(entry.name,class_name,name,kind,"read_error",value); return end
                        if kind == "ObjectProperty" then
                            row(entry.name,class_name,name,kind,"reference",label(value))
                            local lower = name:lower()
                            local follow = lower:find("behavior",1,true) or lower:find("blackboard",1,true) or lower:find("state",1,true) or lower:find("brain",1,true) or lower:find("node",1,true) or lower:find("task",1,true)
                            if follow and entry.depth < 3 then enqueue(value,entry.depth+1) end
                        elseif kind == "StrProperty" or kind == "NameProperty" then
                            local text_ok, rendered = pcall(function()
                                if type(value) == "string" then return value end
                                return value:ToString()
                            end)
                            row(entry.name,class_name,name,kind,text_ok and "ok" or "read_error",rendered)
                        else
                            local t = type(value)
                            row(entry.name,class_name,name,kind,(t=="boolean" or t=="number" or t=="string") and "ok" or "unsupported",value)
                        end
                    end)
                    if count > 128 then row(entry.name,class_name,"","limit","property_cap",128) end
                    local functions = 0
                    class:ForEachFunction(function(fn)
                        functions = functions + 1
                        if functions > 256 then return true end
                        local name = fn:GetFName():ToString()
                        row(entry.name,class_name,name,"function","metadata_only",fn:GetFunctionFlags())
                        -- Function fields describe possible arguments/returns; they are not invoked.
                        local fields = 0
                        fn:ForEachProperty(function(field)
                            fields = fields + 1
                            if fields > 32 then return true end
                            row(entry.name,class_name .. "::" .. name,field:GetFName():ToString(),field:GetClass():GetFName():ToString(),"function_field",field:GetOffset_Internal())
                        end)
                    end)
                    if functions > 256 then row(entry.name,class_name,"","limit","function_cap",256) end
                    class = class:GetSuperStruct()
                end
                if depth >= 12 then row(entry.name,"","","limit","inheritance_cap",12) end
            end)
            if not object_ok then row(entry.name,"","","error","object_error",object_error) end
        end
        file:write("# objects=",tostring(#queue)," max=64 max_reference_depth=3; no game functions called\n")
    end)
    file:close()
    if not ok then error(error_message) end
    print("[AC8CoopRecon] AI state graph saved: " .. stamp .. "\n")
end
