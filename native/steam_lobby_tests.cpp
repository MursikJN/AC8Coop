#define AC8_STEAM_LOBBY_R24
#define AC8_SESSION_TRANSPORT
#define main original_connection_regression
#include "connection_runtime_tests.cpp"
#undef main
#define AC8_R24_BASE_INCLUDED
#include "steam_lobby_bridge.cpp"
static unsigned checks24=0;
static void verify24(bool v){++checks24;if(!v){fprintf(stderr,"Steam lobby check %u failed\n",checks24);exit(1);}}
static int relation24=3;
static int relationship24(void*,uint64){return relation24;}
static std::vector<ac8session::Frame> frames24;
static EResult send24(void*s,HSteamNetConnection h,const void*p,uint32 n,int flags,int64*id){
 if(n==ac8session::packet_size){ac8session::Frame f;verify24(ac8session::decode(p,n,f));frames24.push_back(f);return k_EResultOK;}
 return fake_send(s,h,p,n,flags,id);
}
struct Message24:SteamNetworkingMessage_t {
 std::array<uint8_t,ac8session::packet_size> bytes;
 explicit Message24(const ac8session::Frame&f){bytes=ac8session::encode(f);m_pData=bytes.data();m_cbSize=static_cast<int>(bytes.size());m_conn=connection;m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);m_pfnRelease=[](SteamNetworkingMessage_t*p){++freed_messages;delete static_cast<Message24*>(p);};}
};
static void reset24(){
 reset_fake();open_host24=false;lobby_friends24={};lobby_friends24.handle=reinterpret_cast<void*>(1);lobby_friends24.relationship=relationship24;relation24=3;
 lobby24::authority={};lobby24::have_snapshot=lobby24::was_ready=false;lobby24::bound_nonce24=0;lobby24::guest_ack=lobby24::confirmed=lobby24::pending_wire=lobby24::pending_request=0;lobby24::guest_reject=lobby24::reject_code=0;session_v2_rx=session_v2_tx=0;frames24.clear();
}
static ac8session::Frame intent24(const Session&p,uint64_t seq,ac8session::Op op,uint32_t arg){
 ac8session::Frame f;f.sender=peer_id;f.session=p.nonce;f.echo=session.nonce;f.sequence=seq;f.op=op;f.epoch=lobby24::authority.epoch;f.revision=lobby24::authority.revision;f.args[0]=arg;return f;
}
int main(){
 original_connection_regression();uint64_t n=0;
 verify24(lobby24::decimal24("4294967295",n,UINT32_MAX)&&n==UINT32_MAX);
 verify24(!lobby24::decimal24("9",n,3));verify24(!lobby24::decimal24("4294967296",n,UINT32_MAX));
 reset24();open_host24=true;peer_id=0;const uint64_t first_friend=76561198000000002ULL;
 announce(801,first_friend);pump();verify24(connection==801&&peer_id==first_friend);
 clear_connection("test");verify24(peer_id==0&&listener==10);
 relation24=0;announce(802,first_friend);pump();verify24(connection==0&&peer_id==0&&closed_handles.back()==802);
 relation24=3;announce(803,local_id);pump();verify24(connection==0&&peer_id==0);
 announce(804,0);pump();verify24(connection==0&&peer_id==0);
 reset24();auto peer=complete_handshake(805);api.send=send24;
 ac8session::Args a{};a[0]=6;a[1]=1;verify24(lobby24::authority.apply(0,ac8session::Op::select_mission,a,1,1)==ac8session::Reject::none);
 auto f=intent24(peer,1,ac8session::Op::loadout,23);inbound.push_back(new Message24(f));pump();verify24(lobby24::authority.planes[1].aircraft==23&&lobby24::guest_ack==1&&lobby24::guest_reject==0);
 f=intent24(peer,2,ac8session::Op::ready,1);inbound.push_back(new Message24(f));pump();verify24(lobby24::authority.ready==2&&lobby24::guest_ack==2);
 auto changes=lobby24::authority.changes;inbound.push_back(new Message24(f));pump();verify24(lobby24::authority.changes==changes);
 f=intent24(peer,3,ac8session::Op::ready,0);--f.revision;inbound.push_back(new Message24(f));pump();verify24(lobby24::guest_reject==3&&lobby24::guest_ack==3&&lobby24::authority.ready==2);
 f=intent24(peer,4,ac8session::Op::select_mission,9);inbound.push_back(new Message24(f));pump();verify24(connection==0&&lobby24::authority.mission==6);
 reset24();peer=complete_handshake(806);role=Role::guest;api.send=send24;
 ac8session::State host;host.mission=6;host.difficulty=1;auto snap=ac8session::snapshot(host);snap.sender=peer_id;snap.session=peer.nonce;snap.echo=session.nonce;snap.sequence=1;
 lobby24::pending_wire=7;lobby24::pending_request=45;inbound.push_back(new Message24(snap));pump();verify24(lobby24::have_snapshot&&lobby24::confirmed==0&&lobby24::pending_wire==7);
 snap.sequence=2;snap.args[36]=6;inbound.push_back(new Message24(snap));pump();verify24(lobby24::confirmed==0);
 snap.sequence=3;snap.args[36]=7;snap.args[38]=3;inbound.push_back(new Message24(snap));pump();verify24(lobby24::confirmed==45&&lobby24::reject_code==3&&lobby24::pending_wire==0);
 auto raw=ac8session::encode(snap);ac8test::put(raw.data()+4,2,2);ac8session::Frame decoded;verify24(!ac8session::decode(raw.data(),raw.size(),decoded));
 snap.sequence=4;snap.revision=0;verify24(!ac8session::valid(snap));
 verify24(lobby24::caption("Nick\t\nnext")=="Nicknext");
 reset24();peer=complete_handshake(807);lobby24::update_binding();lobby24::authority.ready=3;lobby24::authority.planes[1].aircraft=23;lobby24::guest_ack=99;
 ++session.remote;lobby24::update_binding();verify24(lobby24::authority.ready==0&&lobby24::authority.planes[1].aircraft==0&&lobby24::guest_ack==0&&lobby24::authority.epoch==2);
 stop();printf("%u Steam lobby v3 checks passed plus connection regression\n",checks24);
}
