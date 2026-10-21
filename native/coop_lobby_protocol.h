#pragma once
#include "connection_protocol.h"
namespace ac8lobby {
constexpr size_t packet_size=80;
enum class Phase:uint32_t { room=0,prepare=1,ack=2,commit=3,loading=4,flight=5,abort=6 };
constexpr uint32_t ready_bit=1,route_bit=2;
struct Frame {
 uint64_t sender=0,session=0,echo=0,sequence=0;
 uint32_t revision=1,ready_revision=0,launch=0,mission=7,plane=23,flags=0;
 Phase phase=Phase::room;
};
inline bool valid(const Frame& f){
 if(!f.sender||!f.session||!f.echo||!f.sequence||!f.revision||f.mission!=7||f.plane!=23||f.flags>3||static_cast<uint32_t>(f.phase)>6)return false;
 if((f.flags&ready_bit)?f.ready_revision!=f.revision:f.ready_revision!=0)return false;
 if(f.phase!=Phase::room&&f.phase!=Phase::abort&&(!f.launch||(f.flags&3)!=3))return false;
 return true;
}
inline std::array<uint8_t,packet_size> encode(const Frame& f){
 std::array<uint8_t,packet_size>b{};memcpy(b.data(),"AC8L",4);ac8test::put(b.data()+4,1,2);ac8test::put(b.data()+6,packet_size,2);ac8test::put(b.data()+8,ac8test::build,4);
 size_t n=12;for(auto v:{f.sender,f.session,f.echo,f.sequence}){ac8test::put(b.data()+n,v,8);n+=8;}
 for(auto v:{f.revision,f.ready_revision,f.launch,f.mission,f.plane,f.flags,static_cast<uint32_t>(f.phase)}){ac8test::put(b.data()+n,v,4);n+=4;}
 return b;
}
inline bool decode(const void* data,size_t size,Frame& f){
 if(!data||size!=packet_size)return false;auto b=static_cast<const uint8_t*>(data);
 if(memcmp(b,"AC8L",4)||ac8test::get(b+4,2)!=1||ac8test::get(b+6,2)!=packet_size||ac8test::get(b+8,4)!=ac8test::build||ac8test::get(b+72,8))return false;
 f={};size_t n=12;for(auto p:{&f.sender,&f.session,&f.echo,&f.sequence}){*p=ac8test::get(b+n,8);n+=8;}
 for(auto p:{&f.revision,&f.ready_revision,&f.launch,&f.mission,&f.plane,&f.flags}){*p=static_cast<uint32_t>(ac8test::get(b+n,4));n+=4;}
 f.phase=static_cast<Phase>(ac8test::get(b+n,4));return valid(f);
}
}
