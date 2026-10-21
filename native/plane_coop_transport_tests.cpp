#define AC8_FLIGHT_TRANSPORT
#include "plane_coop_transport.h"
#define main connection_regression_main
#include "connection_runtime_tests.cpp"
#undef main
#include <limits>
static unsigned coop_checks=0;
static std::vector<ac8flight::Frame> flight_sent;
static int flight_send_flags=0;
static EResult flight_fake_send(void* s,HSteamNetConnection h,const void* p,uint32 n,int flags,int64* seq){
 if(n==ac8flight::packet_size){ac8flight::Frame f;assert(ac8flight::decode(p,n,f));flight_sent.push_back(f);flight_send_flags=flags;return k_EResultOK;}
 return fake_send(s,h,p,n,flags,seq);
}
struct FlightMessage:SteamNetworkingMessage_t {
 std::array<uint8_t,ac8flight::packet_size> payload;
 explicit FlightMessage(ac8flight::Frame frame){payload=ac8flight::encode(frame);m_pData=payload.data();m_cbSize=static_cast<int>(payload.size());m_conn=connection;m_identityPeer.Clear();m_identityPeer.SetSteamID64(peer_id);m_pfnRelease=[](SteamNetworkingMessage_t* p){++freed_messages;delete static_cast<FlightMessage*>(p);};}
};
static Session flight_handshake(){reset_fake();action_thread=GetCurrentThreadId();flight_rx=flight_tx=0;flight_pending=flight_terminal=false;flight_sent.clear();auto peer=complete_handshake(90);api.send=flight_fake_send;return peer;}
static ac8flight::Frame flight_frame(const Session& peer,uint64_t seq=1){
 ac8flight::Frame f;f.sender=peer_id;f.session=peer.nonce;f.echo_session=session.nonce;f.epoch=f.generation=500;f.sequence=seq;f.source_us=seq*50000;
 plane_initial_state::put(f.state.main,0x20,1.f);plane_initial_state::put(f.state.main,0x2c,int32_t{7654321});return f;
}
static void coop_check(bool ok){++coop_checks;if(!ok){std::fprintf(stderr,"FAIL coop transport check %u reason=%s\n",coop_checks,reason);std::exit(1);}}
int main(){
 connection_regression_main();
 {auto peer=flight_handshake();auto f=flight_frame(peer);inbound.push_back(new FlightMessage(f));pump();ac8flight::Frame out;
  coop_check(ac8flight_transport::take(out)&&out.sender==peer_id&&out.sequence==1);
  coop_check(!ac8flight_transport::take(out));
  inbound.push_back(new FlightMessage(f));pump();coop_check(!ac8flight_transport::take(out)&&connection==90);
  f.sequence=3;inbound.push_back(new FlightMessage(f));f.sequence=2;inbound.push_back(new FlightMessage(f));pump();coop_check(ac8flight_transport::take(out)&&out.sequence==3);
  coop_check(ac8flight_transport::send(f,true)&&flight_sent.back().sender==local_id&&flight_sent.back().session==session.nonce&&flight_sent.back().echo_session==peer.nonce);
  coop_check(flight_send_flags==k_nSteamNetworkingSend_ReliableNoNagle);
  coop_check(ac8flight_transport::send(f,false)&&flight_send_flags==k_nSteamNetworkingSend_UnreliableNoNagle);
 }
 {auto peer=flight_handshake();auto f=flight_frame(peer);f.echo_session++;inbound.push_back(new FlightMessage(f));pump();coop_check(!connection&&!std::strcmp(reason,"invalid_flight_packet"));}
 {auto peer=flight_handshake();auto* m=new FlightMessage(flight_frame(peer));m->m_identityPeer.SetSteamID64(peer_id+1);inbound.push_back(m);pump();coop_check(!connection);}
 {auto peer=flight_handshake();auto f=flight_frame(peer);f.flags=ac8flight::stop_flag;inbound.push_back(new FlightMessage(f));f.flags=ac8flight::ready_flag;f.sequence=2;inbound.push_back(new FlightMessage(f));pump();ac8flight::Frame out;coop_check(ac8flight_transport::take(out)&&out.flags==ac8flight::stop_flag);coop_check(!ac8flight_transport::take(out));}
 {auto peer=flight_handshake();auto f=flight_frame(peer);plane_initial_state::put(f.state.main,0x48,std::numeric_limits<float>::infinity());inbound.push_back(new FlightMessage(f));pump();coop_check(!connection);}
 std::printf("%u coop transport checks passed in addition to original runtime regression\n",coop_checks);return 0;
}
