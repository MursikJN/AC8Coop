// Explicit main-menu Steam listen-host experiment. No Steam init/shutdown or packet injection.
// Callback ABI/order: ValveSoftware/source-sdk-2013/src/public/steam/steam_api_common.h.
// A request is accepted only after callback 1202 and only for the configured friend.
#include "steam_legacy_state_probe.cpp"
#include <share.h>
#include <cstring>
struct CallbackABI {
 virtual void Run(void*)=0;
 virtual void Run(void*,bool,uint64_t)=0;
 virtual int GetCallbackSizeBytes()=0;
 uint8_t flags=0;
 int callback_id=0;
};
static_assert(sizeof(CallbackABI)==16,"Valve callback ABI changed");
struct Event {uint64_t peer;uint8_t kind,error;};
static SRWLOCK event_lock=SRWLOCK_INIT;
static Event events[128]{};static size_t event_count=0;static bool overflow=false;
static void enqueue(Event e){AcquireSRWLockExclusive(&event_lock);if(event_count<128)events[event_count++]=e;else overflow=true;ReleaseSRWLockExclusive(&event_lock);}
struct Request final:CallbackABI {
 void Run(void*p)override{if(p){uint64_t id=0;memcpy(&id,p,8);enqueue({id,1,0});}}
 void Run(void*p,bool failed,uint64_t)override{if(!failed)Run(p);}
 int GetCallbackSizeBytes()override{return 8;}
} request_callback;
struct Failure final:CallbackABI {
 void Run(void*p)override{if(p){uint64_t id=0;uint8_t error=0;memcpy(&id,p,8);memcpy(&error,static_cast<char*>(p)+8,1);enqueue({id,2,error});}}
 void Run(void*p,bool failed,uint64_t)override{if(!failed)Run(p);}
 int GetCallbackSizeBytes()override{return 16;}
} failure_callback;
using RegisterFn=void(__cdecl*)(CallbackABI*,int);
using UnregisterFn=void(__cdecl*)(CallbackABI*);
static bool enabled=false;static DWORD game_thread=0;static uint64_t allowed_peer=0;
static void* networking_interface=nullptr;
static bool(__cdecl* accept_peer)(void*,uint64_t)=nullptr;
static void(__cdecl* pump_callbacks)()=nullptr;
static UnregisterFn unregister_callback=nullptr;
static FILE* host_log=nullptr;
static void event_log(const char*n,uint64_t value){if(host_log){fprintf(host_log,"%llu\t%s\t%llu\n",GetTickCount64(),n,static_cast<unsigned long long>(value));fflush(host_log);}}
static void drain(){
 Event copy[128]{};size_t count=0;bool full=false;
 AcquireSRWLockExclusive(&event_lock);count=event_count;memcpy(copy,events,count*sizeof(Event));event_count=0;full=overflow;overflow=false;ReleaseSRWLockExclusive(&event_lock);
 if(full){event_log("callback_queue_overflow",1);return;}
 for(size_t i=0;i<count;++i){
  const auto&e=copy[i];if(e.peer!=allowed_peer){event_log("unrelated_request_ignored",1);continue;}
  if(e.kind==2){event_log("peer_p2p_failure",e.error);continue;}
  event_log("peer_session_request",e.peer);
  const bool accepted=enabled&&accept_peer&&accept_peer(networking_interface,e.peer);
  event_log("peer_session_accept_returned",accepted?1:0);
 }
}
static bool configure(){
 wchar_t marker[8]{},directory[32768]{},path[32768]{},exe[32768]{};
 if(!env(L"AC8_COOP_RECON",marker,8)||wcscmp(marker,L"1")||!env(L"AC8_COOP_RECON_OUTPUT",directory,32768))return false;
 auto length=GetModuleFileNameW(nullptr,exe,32768);auto base=wcsrchr(exe,L'\\');if(!length||length>=32768||!base||_wcsicmp(base+1,L"AceCombat8.exe"))return false;
 if(swprintf_s(path,L"%ls\\native-steam-host-enable.txt",directory)<0)return false;
 FILE*f=nullptr;if(_wfopen_s(&f,path,L"rb")||!f)return false;
 char approval[40]{};size_t count=fread(approval,1,sizeof(approval),f);fclose(f);
 constexpr char expected[]="accept-known-peer-25201480";
 if(count!=sizeof(expected)-1||memcmp(approval,expected,count))return false;
 if(swprintf_s(path,L"%ls\\native-steam-peer.txt",directory)<0)return false;
 if(_wfopen_s(&f,path,L"rb")||!f)return false;char peer[20]{};count=fread(peer,1,sizeof(peer),f);fclose(f);
 if(count!=17||memcmp(peer,"7656119",7))return false;
 uint64_t id=0;for(size_t i=0;i<count;++i){if(peer[i]<'0'||peer[i]>'9')return false;id=id*10+static_cast<unsigned>(peer[i]-'0');}
 HMODULE steam=GetModuleHandleW(L"steam_api64.dll");if(!steam)return false;
 auto user_handle=api<int(__cdecl*)()>(steam,"SteamAPI_GetHSteamUser");
 auto get_user=api<void*(__cdecl*)()>(steam,"SteamAPI_SteamUser_v021");
 auto get_utils=api<void*(__cdecl*)()>(steam,"SteamAPI_SteamUtils_v010");
 auto get_app=api<uint32_t(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUtils_GetAppID");
 auto get_id=api<uint64_t(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUser_GetSteamID");
 auto online=api<bool(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUser_BLoggedOn");
 auto get_net=api<void*(__cdecl*)()>(steam,"SteamAPI_SteamNetworking_v006");
 auto register_callback=api<RegisterFn>(steam,"SteamAPI_RegisterCallback");
 unregister_callback=api<UnregisterFn>(steam,"SteamAPI_UnregisterCallback");
 accept_peer=api<bool(__cdecl*)(void*,uint64_t)>(steam,"SteamAPI_ISteamNetworking_AcceptP2PSessionWithUser");
 pump_callbacks=api<void(__cdecl*)()>(steam,"SteamAPI_RunCallbacks");
 if(!user_handle||!get_user||!get_utils||!get_app||!get_id||!online||!get_net||!register_callback||!unregister_callback||!accept_peer||!pump_callbacks||user_handle()<=0)return false;
 auto user=get_user();auto utils=get_utils();if(!user||!utils||get_app(utils)!=2288340||!online(user)||get_id(user)==id)return false;
 networking_interface=get_net();if(!networking_interface)return false;
 if(swprintf_s(path,L"%ls\\native-steam-host-events.tsv",directory)<0)return false;
 host_log=_wfsopen(path,L"a",_SH_DENYWR);if(!host_log)return false;
 HMODULE pinned=nullptr;
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&configure),&pinned)){fclose(host_log);host_log=nullptr;return false;}
 allowed_peer=id;game_thread=GetCurrentThreadId();enabled=true;
 register_callback(&request_callback,1202);register_callback(&failure_callback,1203);
 event_log("registered_known_peer",allowed_peer);return true;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_legacy_host_start(void*){if(!enabled)configure();return 0;}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_legacy_host_tick(void*){
 if(!enabled||GetCurrentThreadId()!=game_thread)return 0;
 // The stock Steam subsystem's callbacks need dispatch even though EOS is the frontend default.
 // All registered client callbacks may run here; this experiment runs only on the game thread.
 pump_callbacks();drain();return 0;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_legacy_host_stop(void*){
 if(!enabled||GetCurrentThreadId()!=game_thread)return 0;
 enabled=false;unregister_callback(&request_callback);unregister_callback(&failure_callback);
 event_log("observer_stopped_no_session_closed",1);fclose(host_log);host_log=nullptr;return 0;
}
