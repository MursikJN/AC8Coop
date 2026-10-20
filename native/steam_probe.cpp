// Availability probe only. No Steam init/shutdown, callbacks, sockets or gameplay calls.
// Lua calls the exported function on the game thread; no Lua ABI symbols are needed.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <cstdio>
#include <cwchar>
#include <cstdint>

using HandleFn = int(__cdecl*)();
using InterfaceFn = void*(__cdecl*)();
using AppFn = uint32_t(__cdecl*)(void*);
using LoggedOnFn = bool(__cdecl*)(void*);
using IdFn = uint64_t(__cdecl*)(void*);

struct Api {
    HandleFn user_handle, pipe_handle;
    InterfaceFn user, utils, sockets, messages;
    AppFn app_id;
    LoggedOnFn logged_on;
    IdFn steam_id;
};

// Pure gate ordering is shared with the native harness. It must not call interface
// accessors before the game's existing Steam context is initialized.
static const char* inspect(FILE* log, const Api& a) {
    if (!a.user_handle || !a.pipe_handle || !a.user || !a.utils || !a.app_id ||
        !a.logged_on || !a.steam_id) return "required_export_missing";
    const int user_handle = a.user_handle(), pipe_handle = a.pipe_handle();
    fprintf(log, "user_handle\t%d\npipe_handle\t%d\n", user_handle, pipe_handle);
    fflush(log);
    if (user_handle <= 0 || pipe_handle <= 0) return "game_steam_context_not_initialized";
    void* utils = a.utils();
    if (!utils) return "utils_interface_unavailable";
    const auto app = a.app_id(utils);
    fprintf(log, "app_id\t%u\n", app);
    fflush(log);
    if (app != 2288340) return "unexpected_app_id";
    void* user = a.user();
    if (!user) return "user_interface_unavailable";
    const bool online = a.logged_on(user);
    const auto id = a.steam_id(user);
    fprintf(log, "logged_on\t%d\nsteam_id\t%llu\n", online ? 1 : 0,
            static_cast<unsigned long long>(id));
    fflush(log);
    if (!online || !id) return "steam_user_not_ready";
    void* sockets = a.sockets ? a.sockets() : nullptr;
    void* messages = a.messages ? a.messages() : nullptr;
    fprintf(log, "sockets_v012_available\t%d\nmessages_v002_available\t%d\n",
            sockets ? 1 : 0, messages ? 1 : 0);
    return sockets ? "interfaces_available_connection_untested" : "sockets_unavailable";
}

template<class T> static T resolve(HMODULE module, const char* name) {
    return reinterpret_cast<T>(GetProcAddress(module, name));
}

static bool env(const wchar_t* name, wchar_t* buffer, DWORD count) {
    const DWORD length = GetEnvironmentVariableW(name, buffer, count);
    return length > 0 && length < count;
}

static const char* inspect_loaded(FILE* log) {
    // GetModuleHandle never loads or initializes a replacement Steam library.
    HMODULE steam = GetModuleHandleW(L"steam_api64.dll");
    if (!steam) return "steam_module_not_loaded";
    wchar_t expected[32768], actual[32768];
    if (!env(L"AC8_COOP_STEAM_DLL", expected, 32768)) return "expected_steam_path_missing";
    const DWORD length = GetModuleFileNameW(steam, actual, 32768);
    if (!length || length >= 32768 || _wcsicmp(expected, actual)) return "steam_module_path_mismatch";
    const Api a {
        resolve<HandleFn>(steam, "SteamAPI_GetHSteamUser"),
        resolve<HandleFn>(steam, "SteamAPI_GetHSteamPipe"),
        resolve<InterfaceFn>(steam, "SteamAPI_SteamUser_v021"),
        resolve<InterfaceFn>(steam, "SteamAPI_SteamUtils_v010"),
        resolve<InterfaceFn>(steam, "SteamAPI_SteamNetworkingSockets_SteamAPI_v012"),
        resolve<InterfaceFn>(steam, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002"),
        resolve<AppFn>(steam, "SteamAPI_ISteamUtils_GetAppID"),
        resolve<LoggedOnFn>(steam, "SteamAPI_ISteamUser_BLoggedOn"),
        resolve<IdFn>(steam, "SteamAPI_ISteamUser_GetSteamID")
    };
    return inspect(log, a);
}

extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_steam_probe(void*) {
    wchar_t marker[32], directory[32768], executable[32768];
    if (!env(L"AC8_COOP_STEAM_PROBE", marker, 32) || wcscmp(marker, L"25201480") ||
        !env(L"AC8_COOP_RECON_OUTPUT", directory, 32768)) return 0;
    const DWORD exe_length = GetModuleFileNameW(nullptr, executable, 32768);
    if (!exe_length || exe_length >= 32768) return 0;
    const wchar_t* basename = wcsrchr(executable, L'\\');
    if (!basename || _wcsicmp(basename + 1, L"AceCombat8.exe")) return 0;
    SYSTEMTIME t; GetSystemTime(&t);
    wchar_t path[32768];
    if (swprintf_s(path, L"%ls\\steam-interface-%04u%02u%02u-%02u%02u%02u-%03u-%llu.tsv",
            directory, t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond,
            t.wMilliseconds, GetTickCount64()) < 0) return 0;
    FILE* log = nullptr;
    if (_wfopen_s(&log, path, L"wx") || !log) return 0;
    fprintf(log, "probe_version\t0.1.0\npid\t%lu\nthread\t%lu\nnetwork_test\tnot_started\n",
            GetCurrentProcessId(), GetCurrentThreadId());
    fflush(log);
    // Record a native fault and stop this probe; this is not a guarantee against
    // arbitrary engine faults and must never be used to retry native mutations.
    __try {
        fprintf(log, "status\t%s\n", inspect_loaded(log));
    } __except(EXCEPTION_EXECUTE_HANDLER) {
        fprintf(log, "status\tnative_probe_exception\nexception_code\t0x%08lx\n", GetExceptionCode());
    }
    fclose(log);
    return 0; // zero Lua return values; never touch lua_State
}
