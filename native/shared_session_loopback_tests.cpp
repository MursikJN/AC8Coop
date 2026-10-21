#include "shared_session_loopback.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
using namespace ac8session;
static unsigned checks=0;
static void check(bool condition){++checks;if(!condition){fprintf(stderr,"loopback check %u failed\n",checks);exit(1);}}
static SOCKET raw_peer(Loopback&host){
 SOCKET s=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);check(s!=INVALID_SOCKET);
 sockaddr_in target{};target.sin_family=AF_INET;target.sin_addr.s_addr=htonl(INADDR_LOOPBACK);target.sin_port=htons(host.port);
 check(connect(s,reinterpret_cast<sockaddr*>(&target),sizeof(target))==0);
 check(host.poll([](const Frame&){return true;}));check(host.connected);return s;
}
static Frame intent(){Frame f;f.sender=2;f.session=f.echo=123;f.sequence=1;f.args[0]=1;return f;}
int main(){
 Loopback host;check(host.open(true,0,123));check(host.port!=0);
 Loopback collision;check(!collision.open(true,host.port,123));check(!strcmp(collision.error,"listen"));
 SOCKET peer=raw_peer(host);auto bytes=encode(intent());unsigned received=0;
 check(send(peer,reinterpret_cast<const char*>(bytes.data()),17,0)==17);
 check(host.poll([&](const Frame&){++received;return true;}));check(received==0);
 check(send(peer,reinterpret_cast<const char*>(bytes.data()+17),static_cast<int>(bytes.size()-17),0)==static_cast<int>(bytes.size()-17));
 for(unsigned i=0;i<100&&!received;++i){check(host.poll([&](const Frame&f){++received;return f.op==Op::ready;}));Sleep(1);}
 check(received==1);
 // A repeated sequence is a protocol failure, not a second readiness operation.
 check(send(peer,reinterpret_cast<const char*>(bytes.data()),static_cast<int>(bytes.size()),0)==static_cast<int>(bytes.size()));
 bool ok=true;for(unsigned i=0;i<100&&ok;++i){ok=host.poll([](const Frame&){return true;});Sleep(1);}
 check(!ok&&!strcmp(host.error,"invalid_frame"));closesocket(peer);
 check(host.open(true,0,123));peer=raw_peer(host);auto bad=intent();bad.session=999;bytes=encode(bad);
 check(send(peer,reinterpret_cast<const char*>(bytes.data()),static_cast<int>(bytes.size()),0)==static_cast<int>(bytes.size()));
 ok=true;for(unsigned i=0;i<100&&ok;++i){ok=host.poll([](const Frame&){return true;});Sleep(1);}
 check(!ok&&!strcmp(host.error,"invalid_frame"));closesocket(peer);
 check(host.open(true,0,123));peer=raw_peer(host);closesocket(peer);
 ok=true;for(unsigned i=0;i<100&&ok;++i){ok=host.poll([](const Frame&){return true;});Sleep(1);}
 check(!ok&&!host.connected&&(!strcmp(host.error,"peer_closed")||!strcmp(host.error,"send")||!strcmp(host.error,"receive")));
 check(!host.open(false,0,123));check(!host.open(true,0,0));
 printf("%u loopback checks passed: fragments, replay, token, exclusive bind, disconnect\n",checks);
}
