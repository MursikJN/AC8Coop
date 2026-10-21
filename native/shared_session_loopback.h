#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include "shared_session_protocol.h"
// Development transport only. Never listens on a LAN/WAN interface, never uses Steam.
// Both processes receive a fresh shared test token from their launcher.
namespace ac8session {
class Loopback {
 SOCKET listener_=INVALID_SOCKET, socket_=INVALID_SOCKET;
 bool startup_=false,host_=false,connecting_=false;
 uint64_t token_=0,tx_=0,rx_=0,last_rx_=0,last_tx_=0;
 std::array<uint8_t,packet_size> incoming_{},outgoing_{};
 size_t received_=0,sent_=0;bool pending_=false;
 static bool nonblocking(SOCKET s){u_long yes=1;return ioctlsocket(s,FIONBIO,&yes)==0;}
 bool fail(const char*why){
  error=why;
  if(host_&&listener_!=INVALID_SOCKET){
   if(socket_!=INVALID_SOCKET)closesocket(socket_);socket_=INVALID_SOCKET;
   connected=connecting_=pending_=false;
  }else close();
  return false;
 }
 public:
 const char*error="none";uint16_t port=0;bool connected=false;
 uint64_t last_sequence()const{return tx_;}
 void reset_peer(){received_=sent_=0;tx_=rx_=last_tx_=0;pending_=false;error="none";}
 Loopback()=default;Loopback(const Loopback&)=delete;Loopback&operator=(const Loopback&)=delete;
 ~Loopback(){close();}
 void close(){
  if(socket_!=INVALID_SOCKET)closesocket(socket_);
  if(listener_!=INVALID_SOCKET)closesocket(listener_);
  socket_=listener_=INVALID_SOCKET;connected=connecting_=pending_=false;
  if(startup_)WSACleanup();startup_=false;
 }
 bool open(bool host,uint16_t selected_port,uint64_t token){
  close();error="none";port=0;received_=sent_=0;tx_=rx_=last_tx_=0;token_=token;host_=host;
  if(!token||(!host&&!selected_port))return fail("configuration");
  WSADATA data{};if(WSAStartup(MAKEWORD(2,2),&data))return fail("startup");startup_=true;
  SOCKET s=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(s==INVALID_SOCKET)return fail("socket");
  if(host)listener_=s;else socket_=s;
  if(!nonblocking(s))return fail("nonblocking");
  sockaddr_in address{};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=htons(selected_port);
  if(host){
   BOOL exclusive=TRUE;if(setsockopt(s,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof(exclusive)))return fail("exclusive");
   if(bind(s,reinterpret_cast<sockaddr*>(&address),sizeof(address))||listen(s,1))return fail("listen");
   int size=sizeof(address);if(getsockname(s,reinterpret_cast<sockaddr*>(&address),&size))return fail("port");port=ntohs(address.sin_port);
  }else{
   port=selected_port;int result=connect(s,reinterpret_cast<sockaddr*>(&address),sizeof(address));
   if(result==SOCKET_ERROR&&WSAGetLastError()!=WSAEWOULDBLOCK)return fail("connect");
   connecting_=result!=0;connected=!connecting_;last_rx_=GetTickCount64();
  }
  return true;
 }
 bool send_frame(Frame f){
  if(!connected||pending_||tx_==UINT64_MAX)return false;
  f.sender=host_?1:2;f.session=f.echo=token_;f.sequence=tx_+1;
  if(!valid(f))return false;outgoing_=encode(f);++tx_;sent_=0;pending_=true;last_tx_=GetTickCount64();return true;
 }
 template<class Consume> bool poll(Consume consume){
  if(listener_!=INVALID_SOCKET&&socket_==INVALID_SOCKET){
   sockaddr_in remote{};int size=sizeof(remote);SOCKET s=accept(listener_,reinterpret_cast<sockaddr*>(&remote),&size);
   if(s!=INVALID_SOCKET){
    if(remote.sin_addr.s_addr!=htonl(INADDR_LOOPBACK)){closesocket(s);return fail("nonlocal_peer");}
    socket_=s;if(!nonblocking(s))return fail("nonblocking_peer");
    connected=true;last_rx_=GetTickCount64();
   }else if(WSAGetLastError()!=WSAEWOULDBLOCK)return fail("accept");
  }
  if(connecting_){
   fd_set writes,errors;FD_ZERO(&writes);FD_ZERO(&errors);FD_SET(socket_,&writes);FD_SET(socket_,&errors);timeval wait{};
   if(select(0,nullptr,&writes,&errors,&wait)==SOCKET_ERROR)return fail("select");
   if(FD_ISSET(socket_,&errors))return fail("connect_refused");
   if(FD_ISSET(socket_,&writes)){
    int result=0,size=sizeof(result);if(getsockopt(socket_,SOL_SOCKET,SO_ERROR,reinterpret_cast<char*>(&result),&size)||result)return fail("connect_error");
    connected=true;connecting_=false;last_rx_=GetTickCount64();
   }
  }
  if(!connected)return true;
  if(!pending_&&GetTickCount64()-last_tx_>=1000){Frame ping;ping.kind=Kind::keepalive;ping.op=static_cast<Op>(0);send_frame(ping);}
  if(pending_){
   int n=send(socket_,reinterpret_cast<const char*>(outgoing_.data()+sent_),static_cast<int>(packet_size-sent_),0);
   if(n>0){sent_+=static_cast<size_t>(n);if(sent_==packet_size)pending_=false;}
   else if(n==0||WSAGetLastError()!=WSAEWOULDBLOCK)return fail("send");
  }
  // Fixed-size frames, bounded work per tick, including fragmented TCP reads.
  for(unsigned work=0;work<16;++work){
   int n=recv(socket_,reinterpret_cast<char*>(incoming_.data()+received_),static_cast<int>(packet_size-received_),0);
   if(n==0)return fail("peer_closed");
   if(n<0){if(WSAGetLastError()==WSAEWOULDBLOCK)break;return fail("receive");}
   received_+=static_cast<size_t>(n);
   if(received_==packet_size){
    Frame f;if(!decode(incoming_.data(),packet_size,f)||f.sender!=(host_?2u:1u)||f.session!=token_||f.echo!=token_)return fail("invalid_frame");
#ifdef AC8_MISSION_SYNC_R26
    if(f.sequence<=rx_){received_=0;continue;} // Authenticated replay is inert and must not start a second transition.
#else
    if(f.sequence<=rx_)return fail("invalid_frame");
#endif
    rx_=f.sequence;received_=0;last_rx_=GetTickCount64();if(f.kind!=Kind::keepalive&&!consume(f))return fail("authority");
   }
  }
  if(GetTickCount64()-last_rx_>15000)return fail("receive_timeout");
  return true;
 }
};
}
