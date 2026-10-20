-- Dedicated transport test: no recon, objects, saved addresses, UI edits or game calls.
if os.getenv("AC8_CONNECTION_TEST") ~= "25201480" then return end
local path = assert(os.getenv("AC8_CONNECTION_DLL"), "Missing native test DLL")
local function native(symbol)
    local fn, problem = package.loadlib(path, symbol)
    assert(fn, tostring(problem))
    return fn
end
local start = native("luaopen_ac8_connection_start")
local stop = native("luaopen_ac8_connection_stop")
local pump = native("luaopen_ac8_connection_pump")
local status = native("luaopen_ac8_connection_status")
local pending = false
local failed = false
local function schedule(fn)
    if failed then return end
    local ok, problem = pcall(ExecuteInGameThread, function()
        local worked, err = pcall(fn)
        if not worked then failed = true; print("[AC8ConnectionTest] Failed: " .. tostring(err) .. "\n") end
    end)
    if not ok then failed = true; print("[AC8ConnectionTest] Dispatch failed: " .. tostring(problem) .. "\n") end
end
RegisterKeyBind(Key.F8, function() schedule(start) end)
RegisterKeyBind(Key.F9, function() schedule(stop) end)
RegisterKeyBind(Key.F6, function() schedule(status) end)
LoopAsync(100, function()
    if failed then return true end
    if not pending then
        pending = true
        schedule(function() pump(); pending = false end)
    end
    return false
end)
print("[AC8ConnectionTest] Ready. Main menu only: F8 connect/listen, F9 disconnect, F6 status. See launcher status.\n")
