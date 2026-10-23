#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include "guest_pilot_protocol.h"
namespace ac8pilot {
// Local proof uses exactly the same AC8P payload as Steam, with a fresh local
// token. This never listens on LAN/WAN and never claims to be a Steam peer.
class Loopback{
 SOCKET listener_=INVALID_SOCKET,socket_=INVALID_SOCKET;bool startup_=false,host_=false,connecting_=false;
 uint64_t token_=0,tx_=0,rx_=0,last_rx_=0;std::array<uint8_t,packet_size>in_{},out_{};
 size_t have_=0,sent_=0;bool pending_=false;
 static bool nonblock(SOCKET s){u_long yes=1;return ioctlsocket(s,FIONBIO,&yes)==0;}
 bool fail(const char*s){error=s;close();return false;}
 public:
 uint16_t port=0;bool connected=false;const char*error="none";
 Loopback()=default;Loopback(const Loopback&)=delete;Loopback&operator=(const Loopback&)=delete;
 ~Loopback(){close();}
 void close(){if(socket_!=INVALID_SOCKET)closesocket(socket_);if(listener_!=INVALID_SOCKET)closesocket(listener_);socket_=listener_=INVALID_SOCKET;connected=connecting_=pending_=false;if(startup_)WSACleanup();startup_=false;}
 bool open(bool host,uint16_t requested,uint64_t token){
  close();host_=host;token_=token;tx_=rx_=0;have_=sent_=0;error="none";if(!token||(!host&&!requested))return fail("configuration");
  WSADATA data{};if(WSAStartup(MAKEWORD(2,2),&data))return fail("startup");startup_=true;
  auto s=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(s==INVALID_SOCKET)return fail("socket");if(host)listener_=s;else socket_=s;
  if(!nonblock(s))return fail("nonblocking");sockaddr_in a{};a.sin_family=AF_INET;a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);a.sin_port=htons(requested);
  if(host){BOOL exclusive=TRUE;if(setsockopt(s,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof exclusive)||bind(s,reinterpret_cast<sockaddr*>(&a),sizeof a)||listen(s,1))return fail("listen");int n=sizeof a;if(getsockname(s,reinterpret_cast<sockaddr*>(&a),&n))return fail("port");port=ntohs(a.sin_port);}
  else{port=requested;int result=connect(s,reinterpret_cast<sockaddr*>(&a),sizeof a);if(result==SOCKET_ERROR&&WSAGetLastError()!=WSAEWOULDBLOCK)return fail("connect");connecting_=result!=0;connected=!connecting_;last_rx_=GetTickCount64();}
  return true;
 }
 Context context()const{return connected?Context{host_?1u:2u,host_?2u:1u,token_,token_,host_}:Context{};}
 bool send_frame(Frame f){
  if(!connected||pending_||tx_==UINT64_MAX)return false;
  f.sender=host_?1:2;f.session=f.echo=token_;f.sequence=tx_+1;if(!valid(f))return false;
  out_=encode(f);++tx_;sent_=0;pending_=true;return true;
 }
 template<class Consume>bool poll(Consume consume,uint64_t receive_timeout_ms=15000){
  if(receive_timeout_ms<15000||receive_timeout_ms>60000)return fail("timeout_configuration");
  if(listener_!=INVALID_SOCKET&&socket_==INVALID_SOCKET){sockaddr_in peer{};int n=sizeof peer;auto s=accept(listener_,reinterpret_cast<sockaddr*>(&peer),&n);
   if(s!=INVALID_SOCKET){if(peer.sin_addr.s_addr!=htonl(INADDR_LOOPBACK)){closesocket(s);return fail("nonlocal");}socket_=s;if(!nonblock(s))return fail("peer_nonblocking");connected=true;last_rx_=GetTickCount64();}
   else if(WSAGetLastError()!=WSAEWOULDBLOCK)return fail("accept");
  }
  if(connecting_){fd_set writes,errors;FD_ZERO(&writes);FD_ZERO(&errors);FD_SET(socket_,&writes);FD_SET(socket_,&errors);timeval wait{};
   if(select(0,nullptr,&writes,&errors,&wait)==SOCKET_ERROR||FD_ISSET(socket_,&errors))return fail("select_connect");
   if(FD_ISSET(socket_,&writes)){int result=0,n=sizeof result;if(getsockopt(socket_,SOL_SOCKET,SO_ERROR,reinterpret_cast<char*>(&result),&n)||result)return fail("connect_error");connecting_=false;connected=true;last_rx_=GetTickCount64();}
  }
  if(!connected)return true;
  if(pending_){int n=send(socket_,reinterpret_cast<const char*>(out_.data()+sent_),int(packet_size-sent_),0);if(n>0){sent_+=size_t(n);if(sent_==packet_size)pending_=false;}else if(!n||WSAGetLastError()!=WSAEWOULDBLOCK)return fail("send");}
  for(unsigned work=0;work<16;++work){int n=recv(socket_,reinterpret_cast<char*>(in_.data()+have_),int(packet_size-have_),0);
   if(!n)return fail("peer_closed");if(n<0){if(WSAGetLastError()==WSAEWOULDBLOCK)break;return fail("receive");}have_+=size_t(n);
   if(have_==packet_size){Frame f;if(!decode(in_.data(),packet_size,f)||!matches(f,context())||f.sequence<=rx_)return fail("invalid_frame");rx_=f.sequence;have_=0;last_rx_=GetTickCount64();consume(f,last_rx_);}
  }
  if(GetTickCount64()-last_rx_>receive_timeout_ms)return fail("timeout");return true;
 }
};
}
