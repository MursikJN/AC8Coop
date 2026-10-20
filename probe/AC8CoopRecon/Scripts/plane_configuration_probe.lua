-- Read-only configuration ticket. No spawn, native DLL, setters or key bindings.
local function valid(o) return o and o:IsValid() end
local function address(o)
    assert(valid(o), "invalid object")
    return string.format("0x%x", o:GetAddress())
end
local function property_offset(object, name)
    local class = object:GetClass()
    for _ = 1, 20 do
        if not valid(class) then break end
        local found, count = nil, 0
        class:ForEachProperty(function(field)
            count = count + 1
            assert(count <= 512, "property enumeration limit")
            if field:GetFName():ToString() == name then
                assert(field:GetClass():GetFName():ToString() == "ObjectProperty", "unexpected pointer property type")
                found = field:GetOffset_Internal()
                return true
            end
        end)
        if found then
            assert(found >= 0x28 and found <= 0x2000 and found % 8 == 0, "invalid property offset")
            return string.format("0x%x", found)
        end
        class = class:GetSuperStruct()
    end
    error("missing pointer property: " .. name)
end

return function(output_dir, stamp)
    local candidates = {}
    local controllers = FindAllOf("LivePlayerController") or {}
    assert(#controllers <= 8, "controller count limit")
    for _, pc in ipairs(controllers) do
        if valid(pc) then
            local pawn = pc.Pawn
            if valid(pawn) and pawn:IsA("/Script/Live.LivePlayerPlane") then
                candidates[#candidates+1] = {pc=pc, pawn=pawn}
            end
        end
    end
    assert(#candidates == 1, "need exactly one local player plane")
    local pc, pawn = candidates[1].pc, candidates[1].pawn
    local world = pc:GetWorld()
    assert(address(world) == address(pawn:GetWorld()), "world mismatch")
    assert(address(pawn.Controller) == address(pc), "controller backlink mismatch")
    local world_name = world:GetFullName()
    assert(world_name:find("Mission007", 1, true), "only the observed mission 6 / Mission007 is supported")
    assert(pawn.bIsActivated == true, "plane is inactive")
    -- bIsAnimationPlane belongs to LiveAIWingmanPlane, not LivePlayerPlane.
    -- Live player schema 20261020-073801-1 confirms only the common IGC flag here.
    assert(pawn.bIsIGCActor == false, "cinematic player plane")
    -- The external reader additionally verifies the exact F-14D native vtable.
    local rows = {
        {"format", "ac8-flight-ticket-v1"}, {"created_unix", tostring(os.time())},
        {"controller", address(pc)}, {"pawn", address(pawn)},
        {"pawn_class", address(pawn:GetClass())}, {"world", address(world)},
        {"world_name", world_name}, {"plane_class", pawn:GetClass():GetFullName()},
        {"pc_pawn_offset", property_offset(pc, "Pawn")},
        {"plane_controller_offset", property_offset(pawn, "Controller")}
    }
    local path = output_dir .. "/configuration-ticket-" .. stamp .. ".tsv"
    local existing = io.open(path, "r")
    if existing then existing:close(); error("ticket already exists") end
    local file = assert(io.open(path .. ".tmp", "w"))
    for _, row in ipairs(rows) do
        assert(not row[2]:find("[\r\n\t]"), "invalid ticket text")
        file:write(row[1], "\t", row[2], "\n")
    end
    file:close()
    assert(os.rename(path .. ".tmp", path))
    print("[AC8CoopRecon] Configuration ticket ready. Keep the mission paused; one bounded read-only capture.\n")
end
