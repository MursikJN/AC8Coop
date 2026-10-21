#include "plane_coop_runtime.h"
#include <cstdio>
#include <cstdlib>
#include <limits>
namespace f=ac8flight;
unsigned checks=0;
void check(bool ok,const char* message){++checks;if(!ok){std::printf("FAIL %s\n",message);std::exit(1);}}
f::Frame sample(uint64_t sender=1,uint64_t generation=10){
 f::Frame p;p.sender=sender;p.session=100+sender;p.echo_session=103-sender;p.generation=generation;p.epoch=generation;p.sequence=1;p.source_us=1000;
 plane_initial_state::put(p.state.main,0x20,1.f);plane_initial_state::put(p.state.main,0x2c,int32_t{50000});p.state.complete=true;return p;
}
int main(){
 auto p=sample();check(f::valid_state(p),"minimal F14 state admitted");auto bytes=f::encode(p);f::Frame decoded;
 check(bytes.size()==414&&f::decode(bytes.data(),bytes.size(),decoded),"explicit 414-byte full-state round trip");
 check(decoded.state.main==p.state.main,"numeric payload survives");
 p.state.source=0xdeadbeef;p.state.image=0x12345678;p.state.token=33;p.state.timestamp=UINT64_MAX;plane_initial_state::put(p.state.main,8,UINT64_MAX);plane_initial_state::put(p.state.main,0,uint64_t{0xcafebabe});
 bytes=f::encode(p);check(f::decode(bytes.data(),bytes.size(),decoded)&&!decoded.state.source&&!decoded.state.image&&!decoded.state.token&&!decoded.state.timestamp,"native identities and timestamps never cross wire");
 check(!std::memcmp(decoded.state.main.data(),std::array<uint8_t,8>{}.data(),8),"cache vtable not transmitted");
 check(!f::decode(bytes.data(),bytes.size()-1,decoded),"truncated message rejected");
 for(unsigned off:{0u,4u,6u,8u}){auto bad=bytes;bad[off]^=0xff;check(!f::decode(bad.data(),bad.size(),decoded),"wrong magic/version/size/build rejected");}
 {auto bad=sample();bad.state.aux170[0x20]=0x80;check(!f::valid_state(bad),"unknown input bits rejected");}
 {auto bad=sample();plane_initial_state::put(bad.state.main,0x48,std::numeric_limits<float>::quiet_NaN());check(!f::valid_state(bad),"NaN rejected");}
 {auto bad=sample();plane_initial_state::put(bad.state.aux170,8,1.1f);check(!f::valid_state(bad),"input bounds enforced");}
 {auto bad=sample();bad.config.parts_count=17;check(!f::valid_state(bad),"parts count bounded");}
 {auto bad=sample();bad.config.model=24;check(!f::valid_state(bad),"unvalidated aircraft rejected");}
 {auto bad=sample();bad.config.slots[2]=2;check(!f::valid_state(bad),"unsupported selection slots rejected");}
 {auto bad=sample();plane_initial_state::put(bad.state.main,0x2c,INT32_MAX);check(!f::valid_state(bad),"coordinates outside native pose admission bound rejected");}
 {auto bad=sample();plane_initial_state::put(bad.state.main,0x38,4000.f);check(!f::valid_state(bad),"unbounded angle rejected before model conversion");}
 {auto bad=sample();bad.config.model_flags=1;check(!f::valid_state(bad),"model flags must match negotiated configuration");}
 {auto bad=sample();bad.flags=f::ready_flag|f::armed_flag;check(!f::valid_state(bad),"arming without reciprocal generation rejected");}
 f::PeerGate host,guest;host.reset(true,10,{});guest.reset(false,20,{});
 auto h=sample(1,10),g=sample(2,20);g.epoch=0;
 check(host.accept(g,100)&&!host.ready(100),"host receives unbound guest but cannot spawn");
 ++g.sequence;check(host.accept(g,101)&&!host.terminal,"repeated guest announcements before epoch adoption are legal");
 h.echo_generation=20;check(guest.accept(h,102)&&guest.ready(102),"guest adopts host epoch");
 g.epoch=guest.epoch;g.echo_generation=10;++g.sequence;check(host.accept(g,103)&&host.ready(103),"reciprocal epoch/generation readiness");
 check(!host.armed(103)&&!guest.armed(103),"readiness is not creation authorization");
 h.flags|=f::armed_flag;++h.sequence;check(guest.accept(h,104)&&guest.armed(104),"guest observes independently armed host");
 check(!host.armed(104),"one armed participant does not imply both armed");
 g.flags|=f::armed_flag;++g.sequence;check(host.accept(g,105)&&host.armed(105),"both arming decisions admitted");
 check(!host.accept(g,106),"duplicate sequence ignored");
 auto stale=g;--stale.sequence;check(!host.accept(stale,106)&&!host.terminal,"out-of-order datagram does not kill valid binding");
 check(!host.ready(1106)&&host.stale(3106),"stale pose blocks creation then requests cleanup");
 {auto gate=host;auto changed=g;++changed.sequence;++changed.generation;check(!gate.accept(changed,106)&&gate.terminal,"new plane generation terminates old binding");}
 {auto gate=host;auto changed=g;++changed.sequence;++changed.epoch;check(!gate.accept(changed,106)&&gate.terminal,"mission epoch change terminates binding");}
 {auto gate=host;auto changed=g;++changed.sequence;++changed.session;check(!gate.accept(changed,106)&&gate.terminal,"reconnected session cannot reuse old actor binding");}
 {auto gate=host;auto changed=g;++changed.sequence;changed.config.values[0]=5;check(!gate.accept(changed,106)&&gate.terminal,"loadout mismatch terminates readiness");}
 {auto gate=host;auto stop=g;++stop.sequence;stop.flags=f::stop_flag;check(!gate.accept(stop,106)&&gate.terminal,"peer stop is terminal");++g.sequence;check(!gate.accept(g,107),"late state cannot resurrect stopped binding");}
 f::Runtime runtime;runtime.gate=guest;runtime.gate.peer=h;
 plane_initial_state::Snapshot local;local.source=0x10000;local.image=0x140000000;local.token=1;local.timestamp=9000;local.scale=100;local.complete=true;plane_initial_state::put(local.main,0x2c,int32_t{123});
 plane_initial_state::Snapshot applied;
 check(f::materialize_remote(runtime,local,applied),"remote snapshot materialized on receiver");int32_t x=0;std::memcpy(&x,applied.main.data()+0x2c,4);
 check(x==50000&&applied.source==local.source&&applied.image==local.image&&applied.timestamp==9000,"remote values with local ownership and clock; no self-mirroring");
 local.timestamp=9100;check(f::materialize_remote(runtime,local,applied)&&applied.timestamp==9000,"same remote sample retains arrival clock for prediction");
 ++runtime.gate.peer.sequence;runtime.gate.peer.source_us=UINT64_MAX;check(f::materialize_remote(runtime,local,applied)&&applied.timestamp==9100,"sender clock is not trusted as receiver native time");
 runtime.stopped=true;check(!f::materialize_remote(runtime,local,applied),"stopped runtime cannot stage state");
 std::printf("%u coop protocol/runtime checks passed\n",checks);return 0;
}
