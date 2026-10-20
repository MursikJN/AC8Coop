#include "steam_probe.cpp"
#include <cassert>
#include <cstring>

static int handle_value, interface_calls, network_calls;
static bool online_value, null_utils, null_user;
static uint32_t app_value;
static uint64_t id_value;
static int handle() { return handle_value; }
static void* utils() { ++interface_calls; return null_utils ? nullptr : reinterpret_cast<void*>(1); }
static void* user() { ++interface_calls; return null_user ? nullptr : reinterpret_cast<void*>(1); }
static void* network() { ++network_calls; return reinterpret_cast<void*>(1); }
static uint32_t app(void*) { return app_value; }
static bool online(void*) { return online_value; }
static uint64_t id(void*) { return id_value; }
int main() {
    FILE* log = nullptr; tmpfile_s(&log); assert(log);
    Api a{handle, handle, user, utils, network, network, app, online, id};
    auto run = [&](const char* expected) { assert(strcmp(inspect(log, a), expected) == 0); };
    a.user_handle = nullptr; run("required_export_missing"); assert(interface_calls == 0);
    a.user_handle = handle; handle_value = 0; run("game_steam_context_not_initialized"); assert(interface_calls == 0);
    handle_value = 1; app_value = 123; run("unexpected_app_id"); assert(network_calls == 0);
    null_utils = true; run("utils_interface_unavailable"); null_utils = false;
    app_value = 2288340; null_user = true; run("user_interface_unavailable"); null_user = false;
    run("steam_user_not_ready"); assert(network_calls == 0);
    online_value = true; run("steam_user_not_ready"); assert(network_calls == 0);
    id_value = 76561198000000000ULL;
    a.sockets = nullptr; run("sockets_unavailable");
    a.sockets = network; run("interfaces_available_connection_untested");
    fclose(log);
    puts("9 native probe boundary cases passed; no Steam DLL loaded.");
}
