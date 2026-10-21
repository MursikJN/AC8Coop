#pragma once
#include "guest_control_core.h"
#include <algorithm>
#include <cmath>
namespace ac8pilot {
constexpr size_t packet_size=368;
enum class Kind:uint32_t{state=1,loaded=2,input=3,stop=4};
constexpr uint32_t paused=1,dead=2,flight_only=4;
#ifdef AC8_STEAM_COOP_R27
constexpr unsigned pilot_version=2;constexpr uint32_t loaded_ack=8,allowed_flags=15;
#else
constexpr unsigned pilot_version=1;constexpr uint32_t allowed_flags=7;
#endif
struct Pose{
 uint32_t role=0,aircraft=0;std::array<double,3> position{};std::array<float,4> rotation{};
 float speed=0,health=0,max_health=0;uint32_t flags=0;
};
struct Frame{
 Kind kind=Kind::state;uint64_t sender=0,session=0,echo=0,sequence=0,generation=0,source_us=0;
 uint32_t revision=1,mission=7,slot=1,aircraft=23,flags=0,count=0;
 std::array<int16_t,5> axes{};std::array<Pose,4> poses{};
};
inline bool finite(const Pose&p){
 if(p.role>3||!p.aircraft||p.aircraft>65535||p.flags>1)return false;
 for(double v:p.position)if(!std::isfinite(v)||std::fabs(v)>1e9)return false;
 double norm=0;for(float v:p.rotation){if(!std::isfinite(v))return false;norm+=double(v)*v;}if(std::fabs(norm-1)>.002)return false;
 return std::isfinite(p.speed)&&p.speed>=0&&p.speed<=1e6&&std::isfinite(p.health)&&std::isfinite(p.max_health)&&p.health>=0&&p.max_health>0&&p.health<=p.max_health;
}
inline ac8input::Frame input(const Frame&f){
 ac8input::Frame i;i.sender=f.sender;i.session=f.session;i.echo=f.echo;i.sequence=f.sequence;i.generation=f.generation;
 i.revision=f.revision;i.slot=f.slot;i.aircraft=f.aircraft;i.axes=f.axes;return i;
}
inline bool valid(const Frame&f){
 if(!f.sender||!f.session||!f.echo||!f.sequence||!f.generation||!f.revision||f.mission!=7||f.slot!=1||f.aircraft!=23)return false;
 if(f.kind==Kind::state){
  if(f.count!=4||!f.source_us||(f.flags&~allowed_flags)||!(f.flags&flight_only))return false;
  for(unsigned i=0;i<4;++i)if(!finite(f.poses[i])||f.poses[i].role!=i)return false;
  for(auto x:f.axes)if(x)return false;
  return f.poses[1].aircraft==23;
 }
 if(f.kind!=Kind::loaded&&f.kind!=Kind::input&&f.kind!=Kind::stop)return false;
 if(f.count||f.source_us||f.flags)return false;
 for(const auto&p:f.poses){if(p.role||p.aircraft||p.speed||p.health||p.max_health||p.flags)return false;for(auto x:p.position)if(x)return false;for(auto x:p.rotation)if(x)return false;}
 if(f.kind==Kind::input)return ac8input::valid(input(f));
 for(auto x:f.axes)if(x)return false;return true;
}
inline std::array<uint8_t,packet_size> encode(const Frame&f){
 std::array<uint8_t,packet_size>b{};memcpy(b.data(),"AC8P",4);size_t at=4;
 auto put=[&](uint64_t v,size_t n){ac8test::put(b.data()+at,v,n);at+=n;};
 auto scalar=[&](const auto&v){memcpy(b.data()+at,&v,sizeof v);at+=sizeof v;};
 put(pilot_version,2);put(packet_size,2);put(ac8test::build,4);put(uint32_t(f.kind),4);
 for(auto x:{f.sender,f.session,f.echo,f.sequence,f.generation,f.source_us})put(x,8);
 for(auto x:{f.revision,f.mission,f.slot,f.aircraft,f.flags,f.count})put(x,4);
 for(auto x:f.axes)put(uint16_t(x),2);at=104;
 for(const auto&p:f.poses){put(p.role,4);put(p.aircraft,4);for(auto x:p.position)scalar(x);for(auto x:p.rotation)scalar(x);scalar(p.speed);scalar(p.health);scalar(p.max_health);put(p.flags,4);}
 return b;
}
inline bool decode(const void*raw,size_t size,Frame&f){
 if(!raw||size!=packet_size)return false;const auto*b=static_cast<const uint8_t*>(raw);
 if(memcmp(b,"AC8P",4)||ac8test::get(b+4,2)!=pilot_version||ac8test::get(b+6,2)!=packet_size||ac8test::get(b+8,4)!=ac8test::build)return false;
 f={};size_t at=12;auto get=[&](size_t n){auto v=ac8test::get(b+at,n);at+=n;return v;};
 auto scalar=[&](auto&v){memcpy(&v,b+at,sizeof v);at+=sizeof v;};
 f.kind=Kind(get(4));for(auto*p:{&f.sender,&f.session,&f.echo,&f.sequence,&f.generation,&f.source_us})*p=get(8);
 for(auto*p:{&f.revision,&f.mission,&f.slot,&f.aircraft,&f.flags,&f.count})*p=uint32_t(get(4));for(auto&x:f.axes)x=int16_t(get(2));at=104;
 for(auto&p:f.poses){p.role=uint32_t(get(4));p.aircraft=uint32_t(get(4));for(auto&x:p.position)scalar(x);for(auto&x:p.rotation)scalar(x);scalar(p.speed);scalar(p.health);scalar(p.max_health);p.flags=uint32_t(get(4));}
 if(!valid(f))return false;const auto canonical=encode(f);return memcmp(canonical.data(),b,packet_size)==0;
}
struct Context{uint64_t local=0,peer=0,nonce=0,remote=0;bool host=false;};
inline bool matches(const Frame&f,const Context&c){return f.sender==c.peer&&f.session==c.remote&&f.echo==c.nonce;}
struct Gate{
 Context context{};uint64_t generation=0,last_sequence=0,loaded_ms=0;uint32_t revision=0;bool loaded=false,spectating=false;
 ac8input::Lease lease;
 void bind(const Context&c,uint64_t gen,uint32_t rev){*this={};context=c;generation=gen;revision=rev;}
 bool accept(const Frame&f,uint64_t now,const ac8input::Assignment&a){
  if(!context.host||!valid(f)||!matches(f,context)||f.generation!=generation||f.revision!=revision||f.sequence<=last_sequence)return false;
  if(f.kind==Kind::loaded){if(spectating)return false;loaded=true;loaded_ms=now;last_sequence=f.sequence;return true;}
  if(f.kind==Kind::stop){loaded=false;lease.revoke();last_sequence=f.sequence;return true;}
  if(f.kind!=Kind::input||!loaded||spectating||!ac8input::usable(a))return false;
  if(a.peer!=context.peer||a.remote_nonce!=context.remote||a.local_nonce!=context.nonce||a.generation!=generation||a.revision!=revision)return false;
  if(!lease.assigned&&!lease.bind(a))return false;
  if(!lease.accept(input(f),now))return false;last_sequence=f.sequence;return true;
 }
 void died(){spectating=true;loaded=false;lease.revoke();}
};
struct Cadence{
 uint64_t previous_us=0;double debt=0;
 unsigned advance(uint64_t now,bool held){
  if(!previous_us||now<=previous_us){previous_us=now;debt=0;return 0;}
  auto elapsed=now-previous_us;previous_us=now;if(held){debt=0;return 0;}
  debt+=std::min(0.1,double(elapsed)*1e-6);unsigned n=std::min(6u,unsigned((debt+1e-9)*60));debt-=double(n)/60;return n;
 }
};
}
