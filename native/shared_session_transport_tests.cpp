#define AC8_SESSION_TRANSPORT
#define main original_connection_regression
#include "connection_runtime_tests.cpp"
#undef main
#define AC8_SESSION_BASE_INCLUDED
#include "shared_session_bridge.cpp"
static unsigned session_checks=0;
static std::vector<ac8session::Frame> session_sent;
static void verify(bool v){++session_checks;if(!v){fprintf(stderr,"Session transport check failed %u\n",session_checks);exit(1);}}
static EResult session_send(void*s,HSteamNetConnection h,const void*p,uint32 n,int flags,int64*msg){
 if(n==ac8session::packet_size){ac8session::Frame f;verify(ac8session::decode(p,n,f));session_sent.push_back(f);return k_EResultOK;}
 return fake_send(s,h,p,n,flags,msg);
}
struct SessionMessage:SteamNetworkingMessage_t {
 std::array<uint8_t,ac8session::packet_size> bytes;
 explicit SessionMessage(const ac8session::Frame&f){bytes=ac8session::encode(f);m_pData=bytes.data();m_cbSize=static_cast<int>(bytes.size());m_conn=connection;m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);m_pfnRelease=[](SteamNetworkingMessage_t*p){++freed_messages;delete static_cast<SessionMessage*>(p);};}
};
static Session connected_host(){reset_fake();authority={};have_snapshot=false;session_v2_rx=session_v2_tx=0;auto p=complete_handshake(501);api.send=session_send;session_sent.clear();return p;}
static ac8session::Frame intent(const Session&peer,uint64_t seq,ac8session::Op op,uint32_t arg=0){ac8session::Frame f;f.sender=peer_id;f.session=peer.nonce;f.echo=session.nonce;f.sequence=seq;f.epoch=authority.epoch;f.revision=authority.revision;f.op=op;f.args[0]=arg;return f;}
int main(){
 original_connection_regression();auto peer=connected_host();
 auto f=intent(peer,1,ac8session::Op::select_mission,2);f.args[1]=1;inbound.push_back(new SessionMessage(f));pump();verify(connection==501&&authority.mission==0&&reject_code==1);
 ac8session::Args a{};a[0]=1;a[1]=2;verify(authority.apply(0,ac8session::Op::select_mission,a,authority.epoch,authority.revision)==ac8session::Reject::none);
 a={};a[0]=1;verify(authority.apply(0,ac8session::Op::ready,a,authority.epoch,authority.revision)==ac8session::Reject::none);
 f=intent(peer,2,ac8session::Op::ready,1);inbound.push_back(new SessionMessage(f));pump();verify(authority.ready==3&&authority.stage==ac8session::Stage::lobby);
 auto changes=authority.changes;inbound.push_back(new SessionMessage(f));pump();verify(authority.changes==changes);
 verify(send_session(ac8session::snapshot(authority)));verify(session_sent.back().sender==local_id&&session_sent.back().echo==peer.nonce);
 f=intent(peer,3,ac8session::Op::ready,0);--f.revision;inbound.push_back(new SessionMessage(f));pump();verify(authority.ready==3&&connection==501&&reject_code==3);
 f=intent(peer,4,ac8session::Op::begin_intro,101);inbound.push_back(new SessionMessage(f));pump();verify(connection==0);
 peer=connected_host();f=intent(peer,1,ac8session::Op::ready,1);auto*m=new SessionMessage(f);m->m_identityPeer.SetSteamID64(peer_id+1);inbound.push_back(m);pump();verify(connection==0);
 peer=connected_host();f=intent(peer,1,ac8session::Op::ready,1);++f.echo;inbound.push_back(new SessionMessage(f));pump();verify(connection==0);
 peer=connected_host();role=Role::guest;ac8session::State host;host.mission=9;host.revision=2;auto snap=ac8session::snapshot(host);snap.sender=peer_id;snap.session=peer.nonce;snap.echo=session.nonce;snap.sequence=1;
 inbound.push_back(new SessionMessage(snap));pump();verify(have_snapshot&&authority.mission==9&&authority.revision==2);
 snap.sequence=2;snap.revision=1;inbound.push_back(new SessionMessage(snap));pump();verify(connection==0&&authority.revision==2);
 uint64_t value=0;verify(decimal("4294967295",value,UINT32_MAX)&&value==UINT32_MAX);verify(!decimal("4294967296",value,UINT32_MAX));verify(!decimal("1x",value,UINT32_MAX));
 printf("%u authenticated shared-session transport checks passed plus connection regression\n",session_checks);
}
