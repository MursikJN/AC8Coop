// Invitation observer lives for this process, even before a room is created.
// The game dispatches Steam callbacks; this module never drains its global queue.
#include "steam_invite_core.h"
#include "steam_invite_abi.h"
namespace invites25 {
struct Api {
 void* friends=nullptr;void* utils=nullptr;uint64_t self=0;
 int(__cdecl*relationship)(void*,uint64)=nullptr;
 bool(__cdecl*overlay_enabled)(void*)=nullptr;
 void(__cdecl*open_dialog)(void*,const char*)=nullptr;
 void(__cdecl*register_callback)(ac8invite::Callback*,int)=nullptr;
 void(__cdecl*unregister_callback)(ac8invite::Callback*)=nullptr;
} api25;
static SRWLOCK inbox_lock=SRWLOCK_INIT;
static ac8invite::JoinRequested inbox[8]{};
static unsigned inbox_size=0,overflow_count=0;
static bool overlay_active=false;
static uint64_t overlay_activations=0;
class JoinCallback final:public ac8invite::Callback {
public:
 void Run(void*p)override{if(!p)return;AcquireSRWLockExclusive(&inbox_lock);if(inbox_size<8)std::memcpy(&inbox[inbox_size++],p,sizeof(inbox[0]));else ++overflow_count;ReleaseSRWLockExclusive(&inbox_lock);}
 void Run(void*p,bool failed,uint64_t)override{if(!failed)Run(p);}
 int GetCallbackSizeBytes()override{return sizeof(ac8invite::JoinRequested);}
};
class OverlayCallback final:public ac8invite::Callback {
public:
 void Run(void*p)override{if(!p)return;ac8invite::OverlayActivated v;std::memcpy(&v,p,sizeof(v));if(v.app!=2288340)return;AcquireSRWLockExclusive(&inbox_lock);overlay_active=v.active!=0;if(v.active)++overlay_activations;ReleaseSRWLockExclusive(&inbox_lock);}
 void Run(void*p,bool failed,uint64_t)override{if(!failed)Run(p);}
 int GetCallbackSizeBytes()override{return sizeof(ac8invite::OverlayActivated);}
};
static JoinCallback join_callback;
static OverlayCallback overlay_callback;
static bool registered=false,failed=false,overlay_available=false;
static bool retired=false;
static DWORD owner_thread=0;
static uint64_t instance=0,join_sequence=0,join_host=0,open_seen=0,open_requested=0,last_accept=0,retry_at=0;
static unsigned ignored=0;
static const char*invite_state="WAITING_FOR_STEAM";
static wchar_t folder[32768]{};
static FILE*events=nullptr;
static void record(const char*event,uint64_t value=0){if(events){fprintf(events,"%llu\t%s\t%llu\n",GetTickCount64(),event,value);fflush(events);}}
static void subscribe(){api25.register_callback(&join_callback,337);api25.register_callback(&overlay_callback,331);registered=true;}
static bool initialize(){
 wchar_t marker[32]{},expected[32768]{},actual[32768]{},exe[32768]{};
 if(!read_env(L"AC8_STEAM_INVITES",marker,32)||wcscmp(marker,L"25201480")||!read_env(L"AC8_COOP_RECON_OUTPUT",folder,32768))return false;
 if(!events){wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\steam-invite-events.tsv",folder)<0)return false;events=_wfsopen(path,L"a",_SH_DENYWR);}
 const DWORD n=GetModuleFileNameW(nullptr,exe,32768);const wchar_t*base=wcsrchr(exe,L'\\');
 if(!n||n>=32768||!base||_wcsicmp(base+1,L"AceCombat8.exe")){invite_state="ERROR_PROCESS";return false;}
 HMODULE steam=GetModuleHandleW(L"steam_api64.dll");if(!steam)return false;
 const DWORD length=GetModuleFileNameW(steam,actual,32768);
 if(!read_env(L"AC8_SHARED_STEAM_DLL",expected,32768)||!length||length>=32768||_wcsicmp(actual,expected)){invite_state="ERROR_STEAM_PATH";return false;}
 auto user_handle=get<int(__cdecl*)()>(steam,"SteamAPI_GetHSteamUser");auto pipe_handle=get<int(__cdecl*)()>(steam,"SteamAPI_GetHSteamPipe");
 auto user_get=get<Accessor>(steam,"SteamAPI_SteamUser_v021");auto utils_get=get<Accessor>(steam,"SteamAPI_SteamUtils_v010");auto friends_get=get<Accessor>(steam,"SteamAPI_SteamFriends_v017");
 auto app=get<uint32(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUtils_GetAppID");auto online=get<bool(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUser_BLoggedOn");auto identity=get<uint64(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUser_GetSteamID");
 if(!user_handle||!pipe_handle||!user_get||!utils_get||!friends_get||!app||!online||!identity){invite_state="ERROR_EXPORTS";return false;}
 if(user_handle()<=0||pipe_handle()<=0)return false;
 void*utils=utils_get();void*user=user_get();if(!utils||!user||app(utils)!=2288340||!online(user))return false;
 Api candidate;candidate.self=identity(user);candidate.friends=friends_get();candidate.utils=utils;
 candidate.relationship=get<decltype(candidate.relationship)>(steam,"SteamAPI_ISteamFriends_GetFriendRelationship");candidate.overlay_enabled=get<decltype(candidate.overlay_enabled)>(steam,"SteamAPI_ISteamUtils_IsOverlayEnabled");
 candidate.open_dialog=get<decltype(candidate.open_dialog)>(steam,"SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialogConnectString");candidate.register_callback=get<decltype(candidate.register_callback)>(steam,"SteamAPI_RegisterCallback");
 candidate.unregister_callback=get<decltype(candidate.unregister_callback)>(steam,"SteamAPI_UnregisterCallback");
 if(!ac8invite::individual(candidate.self)||!candidate.friends||!candidate.relationship||!candidate.overlay_enabled||!candidate.open_dialog||!candidate.register_callback||!candidate.unregister_callback){invite_state="ERROR_INVITE_EXPORTS";return false;}
 instance=fresh_nonce();if(!instance){invite_state="ERROR_RANDOM";return false;}
 HMODULE pinned=nullptr;
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&initialize),&pinned)){invite_state="ERROR_MODULE_PIN";return false;}
 api25=candidate;subscribe();invite_state="READY";record("callbacks_registered",instance);return true;
}
static void consume_invites(){
 ac8invite::JoinRequested batch[8]{};unsigned count=0;
 AcquireSRWLockExclusive(&inbox_lock);count=inbox_size;std::memcpy(batch,inbox,count*sizeof(batch[0]));inbox_size=0;ReleaseSRWLockExclusive(&inbox_lock);
 for(unsigned i=0;i<count;++i){
  uint64_t target=0;
  if(!ac8invite::decode(batch[i].connect,sizeof(batch[i].connect),target)||target!=batch[i].sender||target==api25.self||api25.relationship(api25.friends,target)!=3){++ignored;record("join_ignored");continue;}
  const auto now=GetTickCount64();if(target==join_host&&now-last_accept<3000){record("join_duplicate",target);continue;}
  if(join_sequence>=0x1fffffffffffffull){invite_state="ERROR_SEQUENCE";continue;}
  join_host=target;++join_sequence;last_accept=now;record("invite_accepted",target);
 }
}
static void read_open_request(){
 wchar_t path[32768]{};if(swprintf_s(path,L"%ls\\steam-invite-command.tsv",folder)<0)return;FILE*f=_wfsopen(path,L"rb",_SH_DENYNO);if(!f)return;
 char bytes[257]{};const auto n=fread(bytes,1,sizeof(bytes),f);fclose(f);if(!n||n>256)return;std::string text(bytes,n);if(text.find('\0')!=std::string::npos)return;
 const char*keys[]={"request","config_token"};uint64_t values[2]{};size_t position=0;
 for(unsigned i=0;i<2;++i){auto end=text.find('\n',position);if(end==std::string::npos)return;auto line=text.substr(position,end-position);position=end+1;if(!line.empty()&&line.back()=='\r')line.pop_back();auto tab=line.find('\t');if(tab==std::string::npos||line.substr(0,tab)!=keys[i]||!lobby24::decimal24(line.substr(tab+1),values[i],0x1fffffffffffffull))return;}
 if(position!=text.size()||!values[0]||values[0]<=open_seen)return;open_seen=values[0];
 if(!lobby24::worker||WaitForSingleObject(lobby24::worker,0)==WAIT_OBJECT_0||!lobby24::configured_host||values[1]!=lobby24::config_token){invite_state="ERROR_NOT_HOST_ROOM";record("open_rejected");return;}
 overlay_available=api25.overlay_enabled(api25.utils);if(!overlay_available){invite_state="OVERLAY_UNAVAILABLE";record("overlay_unavailable");return;}
 const auto connect=ac8invite::encode(api25.self);api25.open_dialog(api25.friends,connect.c_str());++open_requested;invite_state="DIALOG_REQUESTED";record("invite_dialog_requested",open_requested);
}
static void publish(){
 if(!folder[0])return;wchar_t path[32768]{},temp[32768]{};if(swprintf_s(path,L"%ls\\steam-invite-status.tsv",folder)<0||swprintf_s(temp,L"%ls\\steam-invite-status.tmp",folder)<0)return;
 bool active=false;uint64_t activations=0;unsigned overflow=0;AcquireSRWLockShared(&inbox_lock);active=overlay_active;activations=overlay_activations;overflow=overflow_count;ReleaseSRWLockShared(&inbox_lock);
 FILE*f=_wfsopen(temp,L"w",_SH_DENYWR);if(!f)return;
 fprintf(f,"format\tac8-invite-status-v1\ninstance\t%llu\nready\t%d\nstate\t%s\noverlay_enabled\t%d\noverlay_active\t%d\noverlay_activations\t%llu\nopen_seen\t%llu\nopen_requested\t%llu\njoin_sequence\t%llu\njoin_host\t%llu\nignored\t%u\noverflow\t%u\nheartbeat\t%llu\n",instance,registered&&!failed?1:0,invite_state,overlay_available?1:0,active?1:0,activations,open_seen,open_requested,join_sequence,join_host,ignored,overflow,GetTickCount64());
 fclose(f);MoveFileExW(temp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
}
static void tick(bool open){
 if(retired)return;
 if(!owner_thread)owner_thread=GetCurrentThreadId();if(owner_thread!=GetCurrentThreadId()){failed=true;invite_state="ERROR_THREAD";return;}
 const auto now=GetTickCount64();if(!registered&&!failed&&now-retry_at>=1000){retry_at=now;initialize();}
 if(registered&&!failed){overlay_available=api25.overlay_enabled(api25.utils);consume_invites();if(open)read_open_request();}
 publish();
}
static void shutdown(){
 if(retired)return;
 if(owner_thread&&owner_thread!=GetCurrentThreadId()){failed=true;invite_state="ERROR_SHUTDOWN_THREAD";return;}
 retired=true;
 if(registered){api25.unregister_callback(&join_callback);api25.unregister_callback(&overlay_callback);registered=false;}
 AcquireSRWLockExclusive(&inbox_lock);inbox_size=0;overlay_active=false;ReleaseSRWLockExclusive(&inbox_lock);
 invite_state="STOPPED";record("callbacks_unregistered");publish();
 if(events){fclose(events);events=nullptr;}
}
static int boundary25(bool open){
 __try{tick(open);}__except(EXCEPTION_EXECUTE_HANDLER){failed=true;invite_state="ERROR_NATIVE_EXCEPTION";record("native_exception",GetExceptionCode());publish();}return 0;
}
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_invites25_tick(void*){return invites25::boundary25(false);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_invites25_open(void*){return invites25::boundary25(true);}
