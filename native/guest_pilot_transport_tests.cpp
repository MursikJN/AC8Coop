#define AC8_GUEST_PILOT_TRANSPORT
#define main original_connection_regression
#include "connection_runtime_tests.cpp"
#undef main
static unsigned checks=0;
static void verify(bool ok){++checks;if(!ok){printf("pilot transport FAIL %u\n",checks);exit(1);}}
struct PilotMessage:SteamNetworkingMessage_t{
 std::array<uint8_t,ac8pilot::packet_size>bytes;
 explicit PilotMessage(const ac8pilot::Frame&f){bytes=ac8pilot::encode(f);m_pData=bytes.data();m_cbSize=int(bytes.size());m_conn=connection;m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);m_pfnRelease=[](SteamNetworkingMessage_t*p){++freed_messages;delete static_cast<PilotMessage*>(p);};}
};
static ac8pilot::Frame remote(const Session&p,uint64_t seq,ac8pilot::Kind kind){ac8pilot::Frame f;f.kind=kind;f.sender=peer_id;f.session=p.nonce;f.echo=session.nonce;f.sequence=seq;f.generation=1;return f;}
int main(){
 original_connection_regression();reset_fake();pilot_pending.clear();pilot_rx=pilot_tx=0;auto p=complete_handshake(701);action_thread=GetCurrentThreadId();
 auto f=remote(p,1,ac8pilot::Kind::loaded);inbound.push_back(new PilotMessage(f));f.kind=ac8pilot::Kind::input;f.sequence=2;inbound.push_back(new PilotMessage(f));pump();
 ac8pilot::Frame got;uint64_t at=0;verify(ac8pilot_transport::take(got,at)&&got.kind==ac8pilot::Kind::loaded);verify(ac8pilot_transport::take(got,at)&&got.kind==ac8pilot::Kind::input);verify(!ac8pilot_transport::take(got,at));
 inbound.push_back(new PilotMessage(f));pump();verify(!ac8pilot_transport::take(got,at));
 auto ctx=ac8pilot_transport::context();verify(ctx.local==local_id&&ctx.peer==peer_id&&ctx.nonce==session.nonce&&ctx.remote==p.nonce&&ctx.host);
 ++f.sequence;auto*m=new PilotMessage(f);m->m_identityPeer.SetSteamID64(peer_id+1);inbound.push_back(m);pump();verify(!connection&&pilot_pending.empty());
 reset_fake();p=complete_handshake(702);action_thread=GetCurrentThreadId();f=remote(p,1,ac8pilot::Kind::loaded);++f.echo;inbound.push_back(new PilotMessage(f));pump();verify(!connection);
 reset_fake();p=complete_handshake(703);action_thread=GetCurrentThreadId();role=Role::guest;f=remote(p,1,ac8pilot::Kind::input);inbound.push_back(new PilotMessage(f));pump();verify(!connection);
 printf("%u pilot transport checks and existing connection regression passed\n",checks);
}
