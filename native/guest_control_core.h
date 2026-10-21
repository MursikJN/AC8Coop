#pragma once
#include "connection_protocol.h"
#include <array>
#include <cstdint>
#include <cstring>
#include <limits>
// Guest intent only: never an actor pointer, position, damage or mission command.
namespace ac8input {
constexpr size_t packet_size=96;
constexpr uint64_t input_timeout_ms=300;
struct Frame {
 uint64_t sender=0,session=0,echo=0,sequence=0,generation=0;
 uint32_t revision=0,slot=0,aircraft=0,buttons=0;
 // pitch, roll, yaw [-32767,32767]; throttle, brake [0,32767].
 std::array<int16_t,5> axes{};
};
inline bool valid(const Frame& f){
 if(!f.sender||!f.session||!f.echo||!f.sequence||!f.generation||!f.revision||f.slot<1||f.slot>3||f.aircraft!=23)return false;
 // Flight-only milestone: weapon/target/flare buttons have no verified engine adapter.
 if(f.buttons)return false;
 for(size_t i=0;i<f.axes.size();++i)if(f.axes[i]==std::numeric_limits<int16_t>::min()||(i>=3&&f.axes[i]<0))return false;
 return true;
}
inline std::array<uint8_t,packet_size> encode(const Frame& f){
 std::array<uint8_t,packet_size>b{};memcpy(b.data(),"AC8I",4);
 ac8test::put(b.data()+4,1,2);ac8test::put(b.data()+6,packet_size,2);ac8test::put(b.data()+8,ac8test::build,4);
 size_t n=16;for(auto x:{f.sender,f.session,f.echo,f.sequence,f.generation}){ac8test::put(b.data()+n,x,8);n+=8;}
 for(auto x:{f.revision,f.slot,f.aircraft,f.buttons}){ac8test::put(b.data()+n,x,4);n+=4;}
 for(auto x:f.axes){ac8test::put(b.data()+n,static_cast<uint16_t>(x),2);n+=2;}
 return b;
}
inline bool decode(const void* p,size_t n,Frame& f){
 if(!p||n!=packet_size)return false;const auto*b=static_cast<const uint8_t*>(p);
 if(memcmp(b,"AC8I",4)||ac8test::get(b+4,2)!=1||ac8test::get(b+6,2)!=packet_size||ac8test::get(b+8,4)!=ac8test::build||ac8test::get(b+12,4))return false;
 for(size_t i=82;i<packet_size;++i)if(b[i])return false;
 f={};size_t at=16;for(auto x:{&f.sender,&f.session,&f.echo,&f.sequence,&f.generation}){*x=ac8test::get(b+at,8);at+=8;}
 for(auto x:{&f.revision,&f.slot,&f.aircraft,&f.buttons}){*x=static_cast<uint32_t>(ac8test::get(b+at,4));at+=4;}
 for(auto&x:f.axes){auto raw=static_cast<uint16_t>(ac8test::get(b+at,2));memcpy(&x,&raw,2);at+=2;}
 return valid(f);
}
struct Assignment {
 uint64_t peer=0,remote_nonce=0,local_nonce=0,generation=0;
 uint32_t revision=0,slot=0,aircraft=0;
 bool host=false,world_loaded=false,guest_loaded=false,player_flight_engine=false,npc_detached=false,host_pawn_unchanged=false;
};
inline bool usable(const Assignment&a){return a.peer&&a.remote_nonce&&a.local_nonce&&a.generation&&a.revision&&a.slot>=1&&a.slot<=3&&a.aircraft==23&&a.host&&a.world_loaded&&a.guest_loaded&&a.player_flight_engine&&a.npc_detached&&a.host_pawn_unchanged;}
// Called by the future game adapter only after verifying the replacement/role graph.
// Network input alone cannot turn AI off or take over an aircraft.
struct Lease {
 Assignment assignment{};Frame latest{};uint64_t received_ms=0,last_sequence=0;bool assigned=false,have_input=false;
 bool bind(const Assignment&a){revoke();if(!usable(a))return false;assignment=a;assigned=true;return true;}
 void revoke(){assignment={};latest={};received_ms=last_sequence=0;assigned=have_input=false;}
 bool accept(const Frame&f,uint64_t now){
  if(!assigned||!valid(f)||f.sender!=assignment.peer||f.session!=assignment.remote_nonce||f.echo!=assignment.local_nonce||f.generation!=assignment.generation||f.revision!=assignment.revision||f.slot!=assignment.slot||f.aircraft!=assignment.aircraft||f.sequence<=last_sequence||(have_input&&now<received_ms))return false;
  latest=f;last_sequence=f.sequence;received_ms=now;have_input=true;return true;
 }
 bool sample(uint64_t now,Frame&out){
  out={};
  if(!assigned||!have_input)return false;
  if(now<received_ms||now-received_ms>input_timeout_ms){have_input=false;latest={};return false;}
  out=latest;return true;
 }
};
}
