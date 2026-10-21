#pragma once
#include "connection_protocol.h"
#include "plane_initial_state.h"
#include <algorithm>
namespace ac8flight {
constexpr size_t packet_size=414;
constexpr uint32_t ready_flag=1,armed_flag=2,stop_flag=4,started_flag=8;
struct Config {
 int32_t model=23,row=0;uint32_t parts_count=0,model_flags=0;
 std::array<int32_t,10> values{};std::array<uint8_t,4> switches{};
 std::array<int32_t,16> parts{};std::array<int32_t,8> slots{};
};
inline bool same(const Config& a,const Config& b){return a.model==b.model&&a.row==b.row&&a.parts_count==b.parts_count&&a.model_flags==b.model_flags&&a.values==b.values&&a.switches==b.switches&&a.parts==b.parts&&a.slots==b.slots;}
struct Frame {
 uint32_t flags=ready_flag;uint64_t sender=0,session=0,echo_session=0,epoch=0,generation=0,echo_generation=0,sequence=0,source_us=0;
 float scale=100;uint32_t mission=7;Config config{};plane_initial_state::Snapshot state{};
};
inline bool valid_state(const Frame& f){
 if(f.mission!=7||f.config.model!=23||f.config.row!=0||f.config.parts_count>16||!std::isfinite(f.scale)||f.scale!=100)return false;
 if(f.flags!=ready_flag&&f.flags!=(ready_flag|armed_flag)&&f.flags!=(ready_flag|armed_flag|started_flag)&&f.flags!=stop_flag)return false;
 if(!f.sender||!f.session||!f.echo_session||!f.generation||!f.sequence)return false;
 if((f.flags&armed_flag)&&(!f.epoch||!f.echo_generation))return false;
 for(unsigned i=0;i<16;++i)if(f.config.parts[i]<0||(i>=f.config.parts_count&&f.config.parts[i]))return false;
 for(auto v:f.config.slots)if(v)return false;
 for(unsigned i=0;i<3;++i){int32_t p=0;float angle=0;std::memcpy(&p,f.state.main.data()+0x2c+4*i,4);std::memcpy(&angle,f.state.main.data()+0x38+4*i,4);if(std::fabs(double(p))>1e9||!std::isfinite(angle)||std::fabs(angle)>3600)return false;}
 const uint8_t* blocks[]={f.state.main.data(),f.state.aux140.data(),f.state.aux150.data(),f.state.aux160.data(),f.state.aux170.data()};
 for(const auto& field:plane_initial_state::fields()){
  if(field.cache==5||field.size==8||field.size==1)continue;
  if(field.cache==0&&field.offset>=0x2c&&field.offset<=0x34)continue;
  if(field.cache==0&&field.offset==0x44)continue;
  float v=0;std::memcpy(&v,blocks[field.cache]+field.offset,4);
  if(!std::isfinite(v)||std::fabs(v)>1e9f)return false;
 }
 double norm=0;for(unsigned i=0;i<3;++i){float d=0;std::memcpy(&d,f.state.main.data()+0x20+4*i,4);norm+=double(d)*d;}
 float speed=0;uint32_t flags=0;std::memcpy(&speed,f.state.main.data()+0x48,4);std::memcpy(&flags,f.state.main.data()+0x44,4);
 if(norm<.98||norm>1.02||speed<0||speed>1e6f||flags!=f.config.model_flags||(f.state.aux170[0x20]&~31u))return false;
 for(unsigned i=0;i<6;++i){float v=0;std::memcpy(&v,f.state.aux170.data()+8+i*4,4);if(v<(i<3?-1.f:0.f)||v>1.f)return false;}
 return true;
}
inline std::array<uint8_t,packet_size> encode(const Frame& f){
 std::array<uint8_t,packet_size> out{};size_t n=0;
 auto put=[&](uint64_t v,size_t count){ac8test::put(out.data()+n,v,count);n+=count;};
 std::memcpy(out.data(),"AC8F",4);n=4;put(1,2);put(packet_size,2);put(ac8test::build,4);put(f.flags,4);
 for(uint64_t v:{f.sender,f.session,f.echo_session,f.epoch,f.generation,f.echo_generation,f.sequence,f.source_us})put(v,8);
 uint32_t scale=0;std::memcpy(&scale,&f.scale,4);put(scale,4);put(f.mission,4);
 put(static_cast<uint32_t>(f.config.model),4);put(static_cast<uint32_t>(f.config.row),4);put(f.config.parts_count,4);put(f.config.model_flags,4);
 for(auto v:f.config.values)put(static_cast<uint32_t>(v),4);for(auto v:f.config.switches)put(v,1);
 for(auto v:f.config.parts)put(static_cast<uint32_t>(v),4);for(auto v:f.config.slots)put(static_cast<uint32_t>(v),4);
 const uint8_t* blocks[]={f.state.main.data(),f.state.aux140.data(),f.state.aux150.data(),f.state.aux160.data(),f.state.aux170.data()};
 for(const auto& field:plane_initial_state::fields())if(field.cache!=5&&field.size!=8){if(n+field.size>out.size())return {};std::memcpy(out.data()+n,blocks[field.cache]+field.offset,field.size);n+=field.size;}
 return out;
}
inline bool decode(const void* data,size_t size,Frame& f){
 if(!data||size!=packet_size)return false;const auto* b=static_cast<const uint8_t*>(data);
 if(std::memcmp(b,"AC8F",4)||ac8test::get(b+4,2)!=1||ac8test::get(b+6,2)!=packet_size||ac8test::get(b+8,4)!=ac8test::build)return false;
 f={};size_t n=12;auto get=[&](size_t count){auto v=ac8test::get(b+n,count);n+=count;return v;};
 f.flags=static_cast<uint32_t>(get(4));uint64_t* ids[]={&f.sender,&f.session,&f.echo_session,&f.epoch,&f.generation,&f.echo_generation,&f.sequence,&f.source_us};for(auto* id:ids)*id=get(8);
 uint32_t scale=static_cast<uint32_t>(get(4));std::memcpy(&f.scale,&scale,4);f.mission=static_cast<uint32_t>(get(4));
 f.config.model=static_cast<int32_t>(get(4));f.config.row=static_cast<int32_t>(get(4));f.config.parts_count=static_cast<uint32_t>(get(4));f.config.model_flags=static_cast<uint32_t>(get(4));
 for(auto& v:f.config.values)v=static_cast<int32_t>(get(4));for(auto& v:f.config.switches)v=static_cast<uint8_t>(get(1));
 for(auto& v:f.config.parts)v=static_cast<int32_t>(get(4));for(auto& v:f.config.slots)v=static_cast<int32_t>(get(4));
 uint8_t* blocks[]={f.state.main.data(),f.state.aux140.data(),f.state.aux150.data(),f.state.aux160.data(),f.state.aux170.data()};
 for(const auto& field:plane_initial_state::fields())if(field.cache!=5&&field.size!=8){if(n+field.size>size)return false;std::memcpy(blocks[field.cache]+field.offset,b+n,field.size);n+=field.size;}
 if(n!=packet_size||!valid_state(f))return false;f.state.scale=f.scale;f.state.complete=true;return true;
}
// No actor operations. Readiness only admits a later explicitly armed game-thread transition.
struct PeerGate {
 uint64_t local_generation=0,epoch=0,peer_generation=0,last_sequence=0,last_source_us=0,received_ms=0;
 bool host=false,have_peer=false,terminal=false;Config config{};Frame peer{};
 void reset(bool is_host,uint64_t generation,const Config& c){*this={};host=is_host;local_generation=generation;epoch=is_host?generation:0;config=c;}
 bool accept(const Frame& f,uint64_t now){
  if(terminal||!valid_state(f)||f.sequence<=last_sequence)return false;
  if(!same(config,f.config)){terminal=true;return false;}
  if(have_peer&&(f.sender!=peer.sender||f.session!=peer.session||f.echo_session!=peer.echo_session||f.generation!=peer_generation||(f.epoch!=epoch&&(!host||f.epoch||peer.epoch))||f.source_us<last_source_us)){terminal=true;return false;}
  if(host){if(f.epoch&&f.epoch!=epoch){terminal=true;return false;}}
  else {if(!f.epoch||f.epoch!=f.generation)return false;epoch=f.epoch;}
  if(f.flags==stop_flag){terminal=true;return false;}
  peer=f;peer_generation=f.generation;last_sequence=f.sequence;last_source_us=f.source_us;received_ms=now;have_peer=true;return true;
 }
 bool ready(uint64_t now)const{return have_peer&&!terminal&&epoch&&peer.epoch==epoch&&peer.echo_generation==local_generation&&now>=received_ms&&now-received_ms<=1000;}
 bool armed(uint64_t now)const{return ready(now)&&(peer.flags&armed_flag);}
 bool stale(uint64_t now)const{return terminal||(have_peer&&(now<received_ms||now-received_ms>3000));}
};
}
