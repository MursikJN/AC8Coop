// Private two-peer diagnostic channel. No game objects, Strix, saves or flight data.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>
#include <cstdio>
#include <cwchar>
#include <cstddef>
#include <share.h>
#include "isteamnetworkingsockets.h"
#include "connection_protocol.h"

using namespace ac8test;
using Accessor = void*(__cdecl*)();
struct Api {
    void* sockets{};
    void (__cdecl* run_callbacks)(void*){};
    HSteamListenSocket (__cdecl* listen)(void*,int,int,const SteamNetworkingConfigValue_t*){};
    HSteamNetConnection (__cdecl* connect)(void*,const SteamNetworkingIdentity*,int,int,const SteamNetworkingConfigValue_t*){};
    EResult (__cdecl* accept)(void*,HSteamNetConnection){};
    bool (__cdecl* close)(void*,HSteamNetConnection,int,const char*,bool){};
    bool (__cdecl* close_listen)(void*,HSteamListenSocket){};
    bool (__cdecl* info)(void*,HSteamNetConnection,SteamNetConnectionInfo_t*){};
    EResult (__cdecl* send)(void*,HSteamNetConnection,const void*,uint32,int,int64*){};
    int (__cdecl* receive)(void*,HSteamNetConnection,SteamNetworkingMessage_t**,int){};
} api;

constexpr int virtual_port=382;
static bool initialized=false, faulted=false, connected=false, reported_ready=false;
static Role role;
static uint64_t local_id=0, peer_id=0, tag=0;
static HSteamListenSocket listener=0;
static HSteamNetConnection connection=0;
static Session session;
static FILE* event_log=nullptr;
static wchar_t output_dir[32768];
static uint64_t started_at=0, last_receive=0, last_ping=0, pending_ping=0, last_status=0;
static unsigned received=0, pongs=0, reconnects=0;
static uint64_t rtt=0;
static const char* state="IDLE";
static DWORD action_thread=0;
static const char* reason="none";
static int steam_state=0, steam_end=0;
static char steam_detail[160]{};
static uint64_t pump_ticks=0, callbacks_received=0, ignored_events=0, dispatch_calls=0;

static void reset_diagnostics() {
    reason="none";steam_state=steam_end=0;steam_detail[0]=0;
}
static void observe_info(const SteamNetConnectionInfo_t& info) {
    steam_state=static_cast<int>(info.m_eState);steam_end=info.m_eEndReason;
    // Bounded single-line printable diagnostic; never treat remote text as a format string.
    size_t i=0;
    for(;i+1<sizeof(steam_detail) && i<sizeof(info.m_szEndDebug) && info.m_szEndDebug[i];++i) {
        const unsigned char ch=static_cast<unsigned char>(info.m_szEndDebug[i]);
        steam_detail[i]=(ch>=32 && ch<=126 && ch!='|')?static_cast<char>(ch):' ';
    }
    steam_detail[i]=0;
}
static bool open_event_log(const wchar_t* path) {
    // Allow readers while the game runs; still prevent a second writer.
    event_log=_wfsopen(path,L"a",_SH_DENYWR);return event_log!=nullptr;
}

// Steam may deliver callbacks on a different thread. They only copy bounded data.
static SRWLOCK queue_lock=SRWLOCK_INIT;
static SteamNetConnectionStatusChangedCallback_t queue[128];
static size_t queue_size=0;
static bool queue_overflow=false;
static void on_status(SteamNetConnectionStatusChangedCallback_t* event) {
    if(!event) return;
    AcquireSRWLockExclusive(&queue_lock);
    if(queue_size < 128) queue[queue_size++]=*event; else queue_overflow=true;
    ReleaseSRWLockExclusive(&queue_lock);
}
static void log(const char* event, unsigned long long value=0) {
    if(event_log) { fprintf(event_log,"%llu\t%s\t%llu\n",GetTickCount64(),event,value);fflush(event_log); }
}
static void status(const char* next=nullptr) {
    if(next) { state=next;log(next); }
    if(!output_dir[0]) return;
    wchar_t target[32768], temp[32768];
    if(swprintf_s(target,L"%ls\\status.txt",output_dir)<0 || swprintf_s(temp,L"%ls\\status.tmp",output_dir)<0) return;
    FILE* file=nullptr;
    if(!_wfopen_s(&file,temp,L"w") && file) {
        fprintf(file,"%s | version=0.1.2 | role=%s | received=%u | pong=%u | rtt_ms=%llu | accepted_connections=%u"
            " | self=%llu | peer=%llu | reason=%s | steam_state=%d | steam_end=%d | detail=%s"
            " | pump=%llu | callbacks=%llu | ignored_events=%llu | dispatch=%llu\n",
            state,role==Role::host?"host":"guest",received,pongs,rtt,reconnects,
            local_id,peer_id,reason,steam_state,steam_end,steam_detail,pump_ticks,callbacks_received,ignored_events,dispatch_calls);
        fclose(file);MoveFileExW(temp,target,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);
    }
    last_status=GetTickCount64();
}
static bool read_env(const wchar_t* key,wchar_t* out,DWORD count) {
    DWORD n=GetEnvironmentVariableW(key,out,count);return n>0 && n<count;
}
static bool id_from_text(const wchar_t* text,uint64_t& id) {
    if(wcslen(text)!=17) return false;
    for(size_t i=0;i<17;++i) if(text[i]<L'0'||text[i]>L'9') return false;
    id=_wcstoui64(text,nullptr,10);
    return (id>>56)==1 && ((id>>52)&15)==1 && ((id>>32)&0xfffff)==1 && uint32_t(id)!=0;
}
static uint64_t fresh_nonce() {
    uint64_t n=0;
    if(BCryptGenRandom(nullptr,reinterpret_cast<PUCHAR>(&n),sizeof(n),BCRYPT_USE_SYSTEM_PREFERRED_RNG)!=0) return 0;
    return n & 0x7fffffffffffffffULL;
}
template<class T> static T get(HMODULE module,const char* name) {
    return reinterpret_cast<T>(GetProcAddress(module,name));
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_connection_start(void*);

static bool initialize() {
    if(initialized) return true;
    wchar_t marker[32], role_text[32], peer_text[32], expected[32768], actual[32768], exe[32768];
    if(!read_env(L"AC8_CONNECTION_TEST",marker,32) || wcscmp(marker,L"25201480") ||
       !read_env(L"AC8_CONNECTION_OUTPUT",output_dir,32768)) return false;
    DWORD n=GetModuleFileNameW(nullptr,exe,32768);
    const wchar_t* base=wcsrchr(exe,L'\\');
    if(!n || n>=32768 || !base || _wcsicmp(base+1,L"AceCombat8.exe")) return false;
    if(!read_env(L"AC8_CONNECTION_ROLE",role_text,32) ||
       (wcscmp(role_text,L"host") && wcscmp(role_text,L"guest"))) {status("ERROR_ROLE");return false;}
    role=wcscmp(role_text,L"host")==0?Role::host:Role::guest;
    if(!read_env(L"AC8_CONNECTION_PEER",peer_text,32) || !id_from_text(peer_text,peer_id)) {status("ERROR_PEER_ID");return false;}
    if(!event_log) {
        wchar_t path[32768];if(swprintf_s(path,L"%ls\\connection-events.tsv",output_dir)<0) return false;
        if(!open_event_log(path)) {status("ERROR_LOG");return false;}
    }
    HMODULE steam=GetModuleHandleW(L"steam_api64.dll");
    if(!steam || !read_env(L"AC8_CONNECTION_STEAM_DLL",expected,32768)) {status("ERROR_STEAM_MODULE");return false;}
    n=GetModuleFileNameW(steam,actual,32768);
    if(!n || n>=32768 || _wcsicmp(actual,expected)) {status("ERROR_STEAM_PATH");return false;}
    auto user_handle=get<int(__cdecl*)()>(steam,"SteamAPI_GetHSteamUser");
    auto pipe_handle=get<int(__cdecl*)()>(steam,"SteamAPI_GetHSteamPipe");
    auto user_get=get<Accessor>(steam,"SteamAPI_SteamUser_v021");
    auto utils_get=get<Accessor>(steam,"SteamAPI_SteamUtils_v010");
    auto sockets_get=get<Accessor>(steam,"SteamAPI_SteamNetworkingSockets_SteamAPI_v012");
    auto app=get<uint32(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUtils_GetAppID");
    auto online=get<bool(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUser_BLoggedOn");
    auto steam_id=get<uint64(__cdecl*)(void*)>(steam,"SteamAPI_ISteamUser_GetSteamID");
    if(!user_handle||!pipe_handle||!user_get||!utils_get||!sockets_get||!app||!online||!steam_id) {status("ERROR_EXPORTS");return false;}
    if(user_handle()<=0 || pipe_handle()<=0) {status("STEAM_NOT_READY");return false;}
    void* utils=utils_get();void* user=user_get();
    if(!utils||!user||app(utils)!=2288340||!online(user)) {status("STEAM_NOT_READY");return false;}
    local_id=steam_id(user);if(!local_id || local_id==peer_id) {status("ERROR_SAME_OR_EMPTY_ACCOUNT");return false;}
    api.sockets=sockets_get();if(!api.sockets) {status("ERROR_SOCKETS_UNAVAILABLE");return false;}
#define RESOLVE(field, suffix) api.field=get<decltype(api.field)>(steam,"SteamAPI_ISteamNetworkingSockets_" suffix)
    RESOLVE(listen,"CreateListenSocketP2P"); RESOLVE(connect,"ConnectP2P"); RESOLVE(accept,"AcceptConnection");
    RESOLVE(close,"CloseConnection");RESOLVE(close_listen,"CloseListenSocket");RESOLVE(info,"GetConnectionInfo");
    RESOLVE(send,"SendMessageToConnection");RESOLVE(receive,"ReceiveMessagesOnConnection");
    RESOLVE(run_callbacks,"RunCallbacks");
#undef RESOLVE
    if(!api.listen||!api.connect||!api.accept||!api.close||!api.close_listen||!api.info||!api.send||!api.receive) {status("ERROR_NETWORK_EXPORTS");return false;}
    if(!api.run_callbacks) {status("ERROR_CALLBACK_DISPATCH_EXPORT");return false;}
    // Callback pointers remain valid even if the Lua state goes away at engine shutdown.
    HMODULE pinned=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(&luaopen_ac8_connection_start),&pinned)) {status("ERROR_MODULE_PIN");return false;}
    initialized=true;action_thread=GetCurrentThreadId();log("local_id",local_id);log("peer_id",peer_id);
    log("protocol_version",1);log("game_build",build);status("READY_PRESS_F8");return true;
}
static void clear_connection(const char* why,bool notify=false) {
    const auto old=connection;connection=0;connected=false;reported_ready=false;pending_ping=0;
    session={};
    if(old) api.close(api.sockets,old,1000,why,notify);
}
static bool send_packet(Kind kind,uint64_t stamp=0) {
    if(!connection||!connected) return false;
    auto data=encode(session.make(kind,stamp));
    EResult result=api.send(api.sockets,connection,data.data(),static_cast<uint32>(data.size()),k_nSteamNetworkingSend_Reliable,nullptr);
    if(result!=k_EResultOK) {log("send_error",result);return false;} return true;
}
static void stop() {
    if(!initialized) return;
    if(session.ready()) send_packet(Kind::bye);
    clear_connection("local_disconnect",true);
    const auto old=listener;listener=0;tag=0;
    if(old) api.close_listen(api.sockets,old);
    reason="local_f9";log(reason);status("DISCONNECTED_BY_F9_PRESS_F8");
}
static bool new_session() {
    const uint64_t nonce=fresh_nonce();if(!nonce) return false;
    reset_diagnostics();session.reset(role,local_id,peer_id,nonce);received=0;pongs=0;rtt=0;pending_ping=0;
    started_at=GetTickCount64();last_receive=started_at;last_ping=0;
    connected=false;reported_ready=false;return true;
}
static void start() {
    if(!initialize()) return;
    if(connection||listener) {status();return;}
    reset_diagnostics();log("start_requested");
    tag=fresh_nonce();if(!tag) {status("ERROR_RANDOM");return;}
    SteamNetworkingConfigValue_t options[2];
    options[0].SetPtr(k_ESteamNetworkingConfig_Callback_ConnectionStatusChanged,reinterpret_cast<void*>(&on_status));
    options[1].SetInt64(k_ESteamNetworkingConfig_ConnectionUserData,static_cast<int64>(tag));
    if(role==Role::host) {
        listener=api.listen(api.sockets,virtual_port,2,options);
        status(listener?"HOST_WAITING_FOR_FRIEND":"ERROR_LISTEN");
    } else {
        if(!new_session()) {status("ERROR_RANDOM");return;}
        SteamNetworkingIdentity target;target.Clear();target.SetSteamID64(peer_id);
        connection=api.connect(api.sockets,&target,virtual_port,2,options);
        status(connection?"CONNECTING":"ERROR_CONNECT");
    }
}
static void connection_ended(const char* why) {
    reason=why;log(why);
    if(event_log) {fprintf(event_log,"%llu\tend_detail\t%d\t%d\t%s\n",GetTickCount64(),steam_state,steam_end,steam_detail);fflush(event_log);}
    clear_connection(why);
    status(listener?"HOST_WAITING_FOR_REJOIN":"DISCONNECTED_PRESS_F8");
}
static void handle_event(const SteamNetConnectionStatusChangedCallback_t& event) {
    // Never close or accept connections from the game's own networking.
    if(!tag || event.m_info.m_nUserData!=static_cast<int64>(tag)) {++ignored_events;return;}
    const bool incoming=role==Role::host && listener && event.m_info.m_hListenSocket==listener;
    if(!incoming && event.m_hConn!=connection) return;
    SteamNetConnectionInfo_t info{};
    if(!api.info(api.sockets,event.m_hConn,&info)) return;
    if(info.m_nUserData!=static_cast<int64>(tag)) {++ignored_events;return;}
    if(incoming && event.m_hConn!=connection) {
        if(info.m_eState==k_ESteamNetworkingConnectionState_Connecting) {
            if(info.m_identityRemote.GetSteamID64()!=peer_id || connection) {
                api.close(api.sockets,event.m_hConn,1001,"not_expected_peer_or_busy",false);log("rejected_incoming");return;
            }
            if(!new_session()) {api.close(api.sockets,event.m_hConn,1002,"random_failed",false);return;}
            connection=event.m_hConn;
            const EResult accepted=api.accept(api.sockets,connection);
            if(accepted!=k_EResultOK) {log("accept_failed",accepted);connection_ended("accept_failed");return;}
            status("HANDSHAKING");
        } else if(info.m_eState==k_ESteamNetworkingConnectionState_ClosedByPeer || info.m_eState==k_ESteamNetworkingConnectionState_ProblemDetectedLocally) {
            api.close(api.sockets,event.m_hConn,1000,"unused_closed",false);
        }
        return;
    }
    if(event.m_hConn!=connection) return;
    observe_info(info);
    // An early transport failure may not have a remote identity yet. Preserve its
    // actual Steam end reason before enforcing identity on active connections.
    if(info.m_eState==k_ESteamNetworkingConnectionState_ClosedByPeer || info.m_eState==k_ESteamNetworkingConnectionState_ProblemDetectedLocally) {
        log("transport_end_reason",info.m_eEndReason);connection_ended("transport_closed");return;
    }
    if(info.m_identityRemote.GetSteamID64()!=peer_id) {connection_ended("peer_identity_mismatch");return;}
    if(info.m_eState==k_ESteamNetworkingConnectionState_Connected && !connected) {
        connected=true;++reconnects;log("transport_connected",connection);
        if(!send_packet(Kind::hello)) {connection_ended("hello_send_failed");return;}
        status("HANDSHAKING");
    }
}
static void pump() {
    if(!initialized) return;
    ++pump_ticks;
    // Steam's regular callback pump is not guaranteed to deliver this interface's
    // events in the campaign menu. Dispatch its queue while our test is active.
    // This is interface-wide (not handle-scoped); never call SteamAPI_RunCallbacks.
    if(listener || connection) {
        if(!api.run_callbacks) {stop();reason="missing_dispatcher";status("ERROR_CALLBACK_DISPATCH_EXPORT");return;}
        ++dispatch_calls;api.run_callbacks(api.sockets);
    }
    SteamNetConnectionStatusChangedCallback_t events[128];size_t count=0;bool overflow=false;
    AcquireSRWLockExclusive(&queue_lock);
    count=queue_size;memcpy(events,queue,count*sizeof(events[0]));queue_size=0;
    overflow=queue_overflow;queue_overflow=false;
    ReleaseSRWLockExclusive(&queue_lock);
    callbacks_received+=count;
    if(overflow) {stop();status("ERROR_CALLBACK_OVERFLOW");return;}
    for(size_t i=0;i<count;++i) handle_event(events[i]);
    if(!connection) {if(GetTickCount64()-last_status>=1000) status();return;}
    // Poll own connection state too, in case an event was queued before handle assignment.
    SteamNetConnectionInfo_t info{};
    if(api.info(api.sockets,connection,&info)) {
        SteamNetConnectionStatusChangedCallback_t current{};current.m_hConn=connection;current.m_info=info;
        handle_event(current);
    } else {connection_ended("connection_handle_lost");return;}
    if(!connection) return;
    const auto now=GetTickCount64();
    if(now-started_at>30000 && !session.ready()) {connection_ended("handshake_timeout");return;}
    if(connected) {
        SteamNetworkingMessage_t* messages[16]{};
        const auto handle=connection;
        const int count_received=api.receive(api.sockets,handle,messages,16);
        if(count_received<0) {connection_ended("receive_failed");return;}
        for(int i=0;i<count_received;++i) {
            auto* message=messages[i];if(!message) continue;
            Packet packet{};
            const bool ok=connection==handle && message->m_conn==handle &&
                message->m_identityPeer.GetSteamID64()==peer_id && message->m_cbSize>=0 &&
                decode(message->m_pData,static_cast<size_t>(message->m_cbSize),packet) && session.accept(packet);
            message->Release();
            if(!ok) {if(connection==handle) connection_ended("invalid_test_packet");continue;}
            ++received;last_receive=now;
            if(packet.kind==Kind::hello) {if(!send_packet(Kind::ack)) connection_ended("ack_send_failed");}
            else if(packet.kind==Kind::ping) {if(!send_packet(Kind::pong,packet.timestamp)) connection_ended("pong_send_failed");}
            else if(packet.kind==Kind::pong) {
                if(pending_ping && packet.timestamp==pending_ping && now>=packet.timestamp) {
                    rtt=now-packet.timestamp;pending_ping=0;++pongs;log("pong",rtt);
                } else connection_ended("unexpected_pong");
            } else if(packet.kind==Kind::bye) connection_ended("peer_goodbye");
        }
    }
    if(!connection) return;
    if(session.ready() && !reported_ready) {reported_ready=true;log("handshake_confirmed");status("CONNECTED_WAITING_FOR_PONG");}
    if(session.ready() && now-last_receive>15000) {connection_ended("heartbeat_timeout");return;}
    if(session.ready() && !pending_ping && now-last_ping>=1000) {
        pending_ping=now;last_ping=now;
        if(!send_packet(Kind::ping,now)) {connection_ended("ping_send_failed");return;}
    }
    if(now-last_status>=1000) status(pongs?"CONNECTED_TEST_OK":nullptr);
}
static void dispatch(int action) {
    if(faulted) return;
    if(initialized && action_thread!=GetCurrentThreadId()) {faulted=true;status("ERROR_WRONG_THREAD");return;}
    if(action==1) start();else if(action==2) stop();else if(action==3) status();else pump();
}
// No Lua symbols or retained lua_State. Each call returns zero values.
static int boundary(int action) {
    __try {dispatch(action);} __except(EXCEPTION_EXECUTE_HANDLER) {
        faulted=true;log("native_exception",GetExceptionCode());status("ERROR_NATIVE_EXCEPTION_CLOSE_GAME");
    }
    return 0;
}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_connection_start(void*) {return boundary(1);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_connection_stop(void*) {return boundary(2);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_connection_pump(void*) {return boundary(0);}
extern "C" __declspec(dllexport) int __cdecl luaopen_ac8_connection_status(void*) {return boundary(3);}
