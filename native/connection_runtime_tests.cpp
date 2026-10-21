// Runs the real lifecycle code against an in-memory SDK, not Steam or the game.
#include "connection_test.cpp"
#include <cassert>
#include <map>
#include <vector>
static std::map<HSteamNetConnection,SteamNetConnectionInfo_t> fake_infos;
static std::vector<HSteamNetConnection> closed_handles;
static std::vector<Packet> sent_packets;
static std::vector<SteamNetworkingMessage_t*> inbound;
static unsigned freed_messages=0;
static bool defer_callbacks=false;
static unsigned sdk_dispatch_calls=0;
static std::vector<SteamNetConnectionStatusChangedCallback_t> sdk_pending;
static void fake_run_callbacks(void*) {
    ++sdk_dispatch_calls;
    auto pending=sdk_pending;sdk_pending.clear();
    for(auto& event:pending) on_status(&event);
}
struct FakeMessage : SteamNetworkingMessage_t {
    std::array<uint8_t,packet_size> bytes;
    explicit FakeMessage(const Packet& packet) {
        bytes=encode(packet);m_pData=bytes.data();m_cbSize=static_cast<int>(bytes.size());m_conn=connection;
        m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);
        m_pfnRelease=[](SteamNetworkingMessage_t* p) {++freed_messages;delete static_cast<FakeMessage*>(p);};
    }
};
static bool fake_info(void*,HSteamNetConnection h,SteamNetConnectionInfo_t* info) {
    auto it=fake_infos.find(h);if(it==fake_infos.end())return false;*info=it->second;return true;
}
static EResult fake_accept(void*,HSteamNetConnection h) {fake_infos[h].m_eState=k_ESteamNetworkingConnectionState_Connected;return k_EResultOK;}
static bool fake_close(void*,HSteamNetConnection h,int,const char*,bool) {closed_handles.push_back(h);fake_infos.erase(h);return true;}
static bool fake_close_listen(void*,HSteamListenSocket) {return true;}
static EResult fake_send(void*,HSteamNetConnection,const void* data,uint32 size,int,int64*) {
    Packet packet{};assert(decode(data,size,packet));sent_packets.push_back(packet);return k_EResultOK;
}
static int fake_receive(void*,HSteamNetConnection,SteamNetworkingMessage_t** out,int max) {
    const size_t count=(std::min)(inbound.size(),static_cast<size_t>(max));
    for(size_t i=0;i<count;++i)out[i]=inbound[i];inbound.erase(inbound.begin(),inbound.begin()+count);return static_cast<int>(count);
}
static void reset_fake() {
    assert(inbound.empty());fake_infos.clear();closed_handles.clear();sent_packets.clear();
    initialized=true;faulted=false;connected=false;reported_ready=false;role=Role::host;
    local_id=76561198000000001ULL;peer_id=76561198000000002ULL;tag=77;listener=10;connection=0;
    queue_size=0;queue_overflow=false;session={};output_dir[0]=0;event_log=nullptr;
    reset_diagnostics();pump_ticks=callbacks_received=ignored_events=dispatch_calls=0;
    defer_callbacks=false;sdk_dispatch_calls=0;sdk_pending.clear();api.run_callbacks=fake_run_callbacks;
    received=pongs=reconnects=0;freed_messages=0;pending_ping=0;
    api.info=fake_info;api.accept=fake_accept;api.close=fake_close;api.close_listen=fake_close_listen;
    api.send=fake_send;api.receive=fake_receive;
}
static void announce(HSteamNetConnection h,uint64_t id,uint64_t event_tag=77) {
    SteamNetConnectionInfo_t info{};info.m_nUserData=static_cast<int64>(event_tag);
    info.m_hListenSocket=10;info.m_eState=k_ESteamNetworkingConnectionState_Connecting;
    info.m_identityRemote.Clear();info.m_identityRemote.SetSteamID64(id);fake_infos[h]=info;
    SteamNetConnectionStatusChangedCallback_t event{};event.m_hConn=h;event.m_info=info;
    if(defer_callbacks) sdk_pending.push_back(event);else on_status(&event);
}
static Session complete_handshake(HSteamNetConnection h) {
    announce(h,peer_id);pump();assert(connection==h && connected);
    Session peer;peer.reset(Role::guest,peer_id,local_id,9000+h);
    assert(!sent_packets.empty());assert(peer.accept(sent_packets[0]));
    inbound.push_back(new FakeMessage(peer.make(Kind::hello)));
    inbound.push_back(new FakeMessage(peer.make(Kind::ack)));
    pump();assert(session.ready());
    for(const auto& p:sent_packets) if(p.kind==Kind::ack) assert(peer.accept(p));
    assert(peer.ready());return peer;
}
int main() {
    reset_fake();announce(20,peer_id+1);pump();assert(connection==0 && closed_handles.size()==1);
    reset_fake();announce(21,peer_id,66);pump();assert(connection==0 && closed_handles.empty()); // foreign generation
    reset_fake();Session peer=complete_handshake(22);assert(freed_messages==2);
    Packet ping{};bool found=false;for(const auto& p:sent_packets)if(p.kind==Kind::ping){ping=p;found=true;}
    assert(found && peer.accept(ping));inbound.push_back(new FakeMessage(peer.make(Kind::pong,ping.timestamp)));
    pump();assert(pongs==1 && pending_ping==0);
    announce(23,peer_id);pump();assert(connection==22);assert(closed_handles.back()==23); // busy must not replace
    inbound.push_back(new FakeMessage(peer.make(Kind::bye)));pump();assert(connection==0 && listener==10);
    sent_packets.clear();peer=complete_handshake(24);assert(connection==24 && reconnects==2);
    // Stale callback from previous connection cannot close the new one.
    SteamNetConnectionStatusChangedCallback_t stale{};stale.m_hConn=22;stale.m_info.m_nUserData=77;
    stale.m_info.m_hListenSocket=10;stale.m_info.m_eState=k_ESteamNetworkingConnectionState_ClosedByPeer;
    on_status(&stale);pump();assert(connection==24);
    stop();assert(connection==0 && listener==0 && tag==0 && !session.ready());
    reset_fake();peer=complete_handshake(25);
    auto invalid=peer.make(Kind::ping);invalid.sender=local_id;
    inbound.push_back(new FakeMessage(invalid));inbound.push_back(new FakeMessage(peer.make(Kind::ping)));
    const auto before=freed_messages;pump();assert(connection==0 && freed_messages==before+2);
    reset_fake();peer=complete_handshake(26);last_receive=GetTickCount64()-16000;pump();assert(connection==0);
    reset_fake();announce(27,peer_id);pump();started_at=GetTickCount64()-31000;pump();assert(connection==0);
    reset_fake();queue_overflow=true;pump();assert(listener==0 && connection==0);
    // Regression: a manual F9 must be distinguishable from a failed connection.
    reset_fake();stop();assert(strcmp(state,"DISCONNECTED_BY_F9_PRESS_F8")==0);
    assert(strcmp(reason,"local_f9")==0);
    reset_fake();announce(28,peer_id);pump();started_at=GetTickCount64()-31000;pump();
    assert(strcmp(reason,"handshake_timeout")==0);
    // Steam failed before identity was known: retain Steam's reason, not an ID error.
    reset_fake();peer=complete_handshake(29);listener=0;role=Role::guest;
    fake_infos[29].m_eState=k_ESteamNetworkingConnectionState_ProblemDetectedLocally;
    fake_infos[29].m_identityRemote.Clear();fake_infos[29].m_eEndReason=5003;
    strcpy_s(fake_infos[29].m_szEndDebug,"Test timeout\nnext|field");pump();
    assert(strcmp(reason,"transport_closed")==0 && steam_end==5003 && steam_state==5);
    assert(strcmp(steam_detail,"Test timeout next field")==0);
    assert(strcmp(state,"DISCONNECTED_PRESS_F8")==0);
    // The real status file must expose the reason, and event logging must allow live reads.
    wchar_t temp_root[MAX_PATH], folder[MAX_PATH], path[MAX_PATH];
    assert(GetTempPathW(MAX_PATH,temp_root));assert(GetTempFileNameW(temp_root,L"ac8",0,folder));
    assert(DeleteFileW(folder));assert(CreateDirectoryW(folder,nullptr));wcscpy_s(output_dir,folder);
    swprintf_s(path,L"%ls\\events.tsv",folder);assert(open_event_log(path));log("test_live_read");
    HANDLE reader=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,0,nullptr);
    assert(reader!=INVALID_HANDLE_VALUE);CloseHandle(reader);fclose(event_log);event_log=nullptr;
    assert(DeleteFileW(path));status();
#ifdef AC8_LOBBY_TRANSPORT
    swprintf_s(path,L"%ls\\lobby-connection-status.txt",folder);
#else
    swprintf_s(path,L"%ls\\status.txt",folder);
#endif
    FILE* status_file=nullptr;assert(_wfopen_s(&status_file,path,L"r")==0);char text[2048]{};
    assert(fgets(text,sizeof(text),status_file));fclose(status_file);
    assert(strstr(text,"reason=transport_closed") && strstr(text,"steam_end=5003") && strstr(text,"version=0.1.2"));
    assert(DeleteFileW(path));assert(RemoveDirectoryW(folder));output_dir[0]=0;
    reset_fake();pump();assert(pump_ticks==1);
    // Model SDK notification delivery being absent until its dispatcher is run.
    // A host cannot discover/accept this connection by polling its current handle (zero).
    reset_fake();defer_callbacks=true;announce(30,peer_id);pump();
    assert(connection==30 && connected && sdk_dispatch_calls==1 && callbacks_received==1);
    assert(dispatch_calls==1);
    stop();const auto dispatches=sdk_dispatch_calls;pump();assert(sdk_dispatch_calls==dispatches);
    reset_fake();api.run_callbacks=nullptr;pump();assert(listener==0 && strcmp(state,"ERROR_CALLBACK_DISPATCH_EXPORT")==0);
    puts("Runtime tests passed: expected peer, stale events, handshake/pong, busy slot, leave/rejoin, release, timeouts, overflow.");
    return 0;
}
