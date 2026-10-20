-- Explicit F8 on the game thread. The native module only checks Steam availability.
return function(output_dir, stamp)
    assert(os.getenv("AC8_COOP_STEAM_PROBE") == "25201480", "Steam probe is not armed")
    local path = assert(os.getenv("AC8_COOP_STEAM_PROBE_DLL"), "Missing probe DLL path")
    assert(type(package) == "table" and type(package.loadlib) == "function", "Lua native module loading unavailable")
    local inspect, problem = package.loadlib(path, "luaopen_ac8_steam_probe")
    assert(inspect, tostring(problem))
    inspect()
    print("[AC8SteamProbe] Availability check returned; inspect steam-interface TSV. No connection attempted.\n")
end
