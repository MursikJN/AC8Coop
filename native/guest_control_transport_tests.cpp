#define AC8_GUEST_INPUT_TRANSPORT
#define main original_connection_regression
#include "connection_runtime_tests.cpp"
#undef main
static unsigned input_checks=0;
static void verify(bool x){++input_checks;if(!x){fprintf(stderr,"Input transport failed %u\n",input_checks);exit(1);}}
struct InputMessage:SteamNetworkingMessage_t {
 std::array<uint8_t,ac8input::packet_size> bytes;
 explicit InputMessage(const ac8input::Frame&f){bytes=ac8input::encode(f);m_pData=bytes.data();m_cbSize=static_cast<int>(bytes.size());m_conn=connection;m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);m_pfnRelease=[](SteamNetworkingMessage_t*p){++freed_messages;delete static_cast<InputMessage*>(p);};}
};
static ac8input::Frame remote_input(const Session&p,uint64_t seq){ac8input::Frame f;f.sender=peer_id;f.session=p.nonce;f.echo=session.nonce;f.sequence=seq;f.generation=7;f.revision=3;f.slot=1;f.aircraft=23;return f;}
static unsigned input_sends=0;
static EResult capture_input(void*s,HSteamNetConnection h,const void*p,uint32 n,int flags,int64*msg){
 if(n==ac8input::packet_size){ac8input::Frame f;verify(ac8input::decode(p,n,f));verify(flags==k_nSteamNetworkingSend_UnreliableNoNagle);++input_sends;return k_EResultOK;}return fake_send(s,h,p,n,flags,msg);
}
int main(){
 original_connection_regression();reset_fake();auto peer=complete_handshake(601);action_thread=GetCurrentThreadId();
 auto f=remote_input(peer,1);inbound.push_back(new InputMessage(f));pump();ac8input::Frame got;uint64_t time=0;
 verify(ac8input_transport::take(got,time)&&got.sequence==1);verify(!ac8input_transport::take(got,time));
 inbound.push_back(new InputMessage(f));pump();verify(!ac8input_transport::take(got,time));
 f.sequence=2;inbound.push_back(new InputMessage(f));pump();guest_input_received_ms=GetTickCount64()-301;verify(!ac8input_transport::take(got,time));
 f.sequence=3;auto*m=new InputMessage(f);m->m_identityPeer.SetSteamID64(peer_id+1);inbound.push_back(m);pump();verify(!connection&&!guest_input_pending);
 reset_fake();peer=complete_handshake(602);action_thread=GetCurrentThreadId();f=remote_input(peer,1);++f.echo;inbound.push_back(new InputMessage(f));pump();verify(!connection);
 reset_fake();peer=complete_handshake(603);action_thread=GetCurrentThreadId();role=Role::guest;f=remote_input(peer,1);inbound.push_back(new InputMessage(f));pump();verify(!connection);
 reset_fake();peer=complete_handshake(604);action_thread=GetCurrentThreadId();api.send=capture_input;f=remote_input(peer,1);
 verify(!ac8input_transport::send(f));role=Role::guest;verify(ac8input_transport::send(f));verify(input_sends==1);f.buttons=1;verify(!ac8input_transport::send(f));
 printf("%u authenticated guest input transport checks plus connection regression passed\n",input_checks);
}
