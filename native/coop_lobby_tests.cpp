#define AC8_LOBBY_TRANSPORT
#define main connection_regression_main
#include "connection_runtime_tests.cpp"
#undef main
static unsigned checks=0;
static void check(bool b){++checks;if(!b){fprintf(stderr,"Lobby check failed %u\n",checks);exit(1);}}
struct LobbyMessage:SteamNetworkingMessage_t{
 std::array<uint8_t,ac8lobby::packet_size> data;
 explicit LobbyMessage(const ac8lobby::Frame&f){data=ac8lobby::encode(f);m_pData=data.data();m_cbSize=static_cast<int>(data.size());m_conn=connection;m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);m_pfnRelease=[](SteamNetworkingMessage_t*p){++freed_messages;delete static_cast<LobbyMessage*>(p);};}
};
static ac8lobby::Frame frame(const Session&p){ac8lobby::Frame f;f.sender=peer_id;f.session=p.nonce;f.echo=session.nonce;f.sequence=1;return f;}
int main(){
 connection_regression_main();
 reset_fake();auto peer=complete_handshake(91);auto f=frame(peer);ac8lobby::Frame out;
 auto bytes=ac8lobby::encode(f);check(ac8lobby::decode(bytes.data(),bytes.size(),out));check(out.mission==7&&out.plane==23);
 for(size_t n=0;n<bytes.size();++n)check(!ac8lobby::decode(bytes.data(),n,out));
 bytes[72]=1;check(!ac8lobby::decode(bytes.data(),bytes.size(),out));
 f.flags=1;check(!ac8lobby::valid(f));f.ready_revision=f.revision;check(ac8lobby::valid(f));
 f.phase=ac8lobby::Phase::prepare;check(!ac8lobby::valid(f));f.launch=1;check(!ac8lobby::valid(f));f.flags=3;check(ac8lobby::valid(f));
 f.plane=22;check(!ac8lobby::valid(f));f.plane=23;f.mission=6;check(!ac8lobby::valid(f));f.mission=7;
 lobby_rx=0;lobby_pending=false;inbound.push_back(new LobbyMessage(f));pump();check(lobby_pending&&lobby_rx==1&&lobby_mailbox.launch==1);
 lobby_pending=false;inbound.push_back(new LobbyMessage(f));pump();check(!lobby_pending&&connection==91);
 f.sequence=2;f.echo++;inbound.push_back(new LobbyMessage(f));pump();check(!connection&&!strcmp(reason,"invalid_lobby_packet"));check(!lobby_rx&&!lobby_pending);
 reset_fake();peer=complete_handshake(92);f=frame(peer);auto*m=new LobbyMessage(f);m->m_identityPeer.SetSteamID64(peer_id+1);inbound.push_back(m);pump();check(!connection);
 reset_fake();peer=complete_handshake(93);f=frame(peer);m=new LobbyMessage(f);m->m_conn=94;inbound.push_back(m);pump();check(!connection);
 printf("%u lobby protocol/transport checks passed plus original connection regression\n",checks);
}
