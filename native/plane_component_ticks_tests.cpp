#include "plane_component_ticks.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
using namespace plane_component_ticks;
struct Captured {Pair pair;uint8_t base_tick;};
// Actual 68 virtual pairs and base tick bytes from the R2 quarantine capture.
// Auxiliary registration/custom D3 values below are mock contract scenarios,
// not claims about fields absent from that live capture.
const Captured captured[]={
 {{0x41df200,0x41df3e0},0}, // captured component 0
 {{0x41df200,0x41df3e0},0}, // captured component 1
 {{0x42dfa90,0x41df3e0},0}, // captured component 2
 {{0x42dfa90,0x41df3e0},1}, // captured component 3
 {{0x41df200,0x41df3e0},0}, // captured component 4
 {{0x41df200,0x41df3e0},0}, // captured component 5
 {{0x41df200,0x41df3e0},0}, // captured component 6
 {{0x41df200,0x41df3e0},0}, // captured component 7
 {{0x41df200,0x41df3e0},0}, // captured component 8
 {{0x41df200,0x41df3e0},0}, // captured component 9
 {{0x41df200,0x41df3e0},0}, // captured component 10
 {{0x41df200,0x41df3e0},0}, // captured component 11
 {{0x41df200,0x41df3e0},0}, // captured component 12
 {{0x41df200,0x41df3e0},0}, // captured component 13
 {{0x7d2c180,0x7d2c120},0}, // captured component 14
 {{0x41df200,0x41df3e0},0}, // captured component 15
 {{0x41df200,0x41df3e0},0}, // captured component 16
 {{0x42dfa90,0x41df3e0},0}, // captured component 17
 {{0x41df200,0x41df3e0},0}, // captured component 18
 {{0x7d2c180,0x7d2c120},0}, // captured component 19
 {{0x7d2c180,0x7d2c120},0}, // captured component 20
 {{0x41df200,0x41df3e0},0}, // captured component 21
 {{0x41df200,0x41df3e0},0}, // captured component 22
 {{0x41df200,0x41df3e0},0}, // captured component 23
 {{0x41df200,0x41df3e0},0}, // captured component 24
 {{0x41df200,0x41df3e0},0}, // captured component 25
 {{0x41df200,0x41df3e0},0}, // captured component 26
 {{0x41df200,0x41df3e0},0}, // captured component 27
 {{0x41df200,0x41df3e0},0}, // captured component 28
 {{0x41df200,0x41df3e0},0}, // captured component 29
 {{0x41df200,0x41df3e0},0}, // captured component 30
 {{0x41df200,0x41df3e0},0}, // captured component 31
 {{0x41df200,0x41df3e0},0}, // captured component 32
 {{0x41df200,0x41df3e0},0}, // captured component 33
 {{0x41df200,0x41df3e0},0}, // captured component 34
 {{0x41df200,0x41df3e0},0}, // captured component 35
 {{0x41df200,0x41df3e0},0}, // captured component 36
 {{0x41df200,0x41df3e0},0}, // captured component 37
 {{0x41df200,0x41df3e0},0}, // captured component 38
 {{0x41df200,0x41df3e0},0}, // captured component 39
 {{0x41df200,0x41df3e0},0}, // captured component 40
 {{0x41df200,0x41df3e0},0}, // captured component 41
 {{0x41df200,0x41df3e0},0}, // captured component 42
 {{0x41df200,0x41df3e0},0}, // captured component 43
 {{0x41df200,0x41df3e0},0}, // captured component 44
 {{0x41df200,0x41df3e0},0}, // captured component 45
 {{0x41df200,0x41df3e0},0}, // captured component 46
 {{0x41df200,0x41df3e0},0}, // captured component 47
 {{0x41df200,0x41df3e0},0}, // captured component 48
 {{0x41df200,0x41df3e0},0}, // captured component 49
 {{0x41df200,0x41df3e0},0}, // captured component 50
 {{0x41df200,0x41df3e0},0}, // captured component 51
 {{0x41df200,0x41df3e0},0}, // captured component 52
 {{0x41df200,0x41df3e0},0}, // captured component 53
 {{0x41df200,0x41df3e0},0}, // captured component 54
 {{0x41df200,0x41df3e0},0}, // captured component 55
 {{0x41df200,0x41df3e0},0}, // captured component 56
 {{0x41df200,0x41df3e0},0}, // captured component 57
 {{0x41df200,0x41df3e0},0}, // captured component 58
 {{0x41df200,0x41df3e0},0}, // captured component 59
 {{0x41df200,0x41df3e0},0}, // captured component 60
 {{0x41df200,0x41df3e0},0}, // captured component 61
 {{0x41df200,0x41df3e0},0}, // captured component 62
 {{0x41df200,0x41df3e0},0}, // captured component 63
 {{0x41df200,0x41df3e0},0}, // captured component 64
 {{0x41df200,0x41df3e0},0}, // captured component 65
 {{0x41df200,0x41df3e0},0}, // captured component 66
 {{0x41df200,0x41df3e0},0}, // captured component 67
};
struct Mock {
 State state{};bool own=true,pair_same=true,readable=true,dispatch=true;
 bool stuck_base=false,stuck_custom=false,stuck_aux=false,change_owner=false,change_pair=false,change_after_read=false;
 unsigned calls=0;uintptr_t last_setter=0;
 bool guard(){return own&&pair_same;}
 bool set_false(uintptr_t setter){
  if(!dispatch)return false;++calls;last_setter=setter;
  if(setter==0x41df200||setter==0x42dfa90){if(!stuck_base)state.base_tick=0;}
  if(setter==0x42dfa90&&!stuck_aux)state.aux_flags&=uint8_t(0xfe);
  if(setter==0x7d2c180&&!stuck_custom)state.custom_enabled=0;
  if(change_owner)own=false;if(change_pair)pair_same=false;return true;
 }
 bool read_state(Kind,State& out){if(!readable)return false;out=state;if(change_after_read)own=false;return true;}
};
void check(bool value,const char* name){if(!value){std::printf("FAIL %s\n",name);std::exit(1);}}
bool error(const Result& r,const char* text){return !std::strcmp(r.error,text);}
int main(){unsigned tests=0;
 {unsigned rejected=0,verified=0;for(auto f:captured){
   if(f.pair.setter!=0x41df200||f.pair.getter!=0x41df3e0)++rejected;
   Mock b;b.state.base_tick=f.base_tick;
   if(classify(f.pair)==Kind::mesh){b.state.aux_registration=0x90000;b.state.aux_flags=3;}
   if(classify(f.pair)==Kind::live)b.state.custom_enabled=1;
   Result r;check(apply(b,f.pair,true,r)&&r.verified&&b.calls==1&&b.last_setter==f.pair.setter,"captured actual override dispatch");++verified;
  }check(rejected==6&&verified==68,"R2 legacy rejects six; R3 covers 68 captured pairs");++tests;}
 {Mock b;Result r;check(!apply(b,{0x41df200,0x7d2c120},true,r)&&!b.calls&&error(r,"component_virtual_pair_unsupported"),"mismatched known pair refuses");++tests;}
 {Mock b;Result r;check(!apply(b,{0x12345,0x41df3e0},true,r)&&!b.calls,"unknown override no call");++tests;}
 {Mock b;b.own=false;Result r;check(!apply(b,{0x41df200,0x41df3e0},true,r)&&!b.calls,"foreign ownership no call");++tests;}
 {Mock b;b.state.aux_registration=0x90000;b.state.aux_flags=1;b.stuck_aux=true;Result r;check(!apply(b,{0x42dfa90,0x41df3e0},true,r)&&error(r,"component_mesh_aux_registration_active"),"mesh auxiliary still registered");++tests;}
 {Mock b;b.state.base_tick=1;b.stuck_base=true;Result r;check(!apply(b,{0x42dfa90,0x41df3e0},true,r)&&error(r,"component_base_tick_still_active"),"mesh base still active");++tests;}
 {Mock b;b.state.custom_enabled=1;b.stuck_custom=true;Result r;check(!apply(b,{0x7d2c180,0x7d2c120},true,r)&&error(r,"component_custom_d3_still_enabled"),"custom D3 still enabled");++tests;}
 {Mock b;b.state.base_tick=1;b.state.custom_enabled=1;Result r;check(!apply(b,{0x7d2c180,0x7d2c120},true,r)&&error(r,"component_custom_base_tick_active")&&b.calls==1&&b.last_setter==0x7d2c180&&r.setter_calls==1&&b.state.custom_enabled==0,"custom base active refuses without base fallback");++tests;}
 {Mock b;b.change_owner=true;Result r;check(!apply(b,{0x42dfa90,0x41df3e0},true,r)&&error(r,"component_identity_changed_after_setter"),"changed owner after setter");++tests;}
 {Mock b;b.change_pair=true;Result r;check(!apply(b,{0x7d2c180,0x7d2c120},true,r)&&error(r,"component_identity_changed_after_setter"),"changed virtual pair after setter");++tests;}
 {Mock b;b.readable=false;Result r;check(!apply(b,{0x42dfa90,0x41df3e0},true,r)&&error(r,"component_tick_readback_unreadable"),"unreadable registration refuses");++tests;}
 {Mock b;b.change_after_read=true;Result r;check(!apply(b,{0x41df200,0x41df3e0},true,r)&&error(r,"component_identity_changed_after_readback"),"identity changes during readback");++tests;}
 {Mock b;Result r;check(apply(b,{0x7d2c180,0x7d2c120},false,r)&&!b.calls&&r.setter_calls==0,"verification pass does not mutate");++tests;}
 {Mock b;b.state.aux_registration=0x90000;b.state.aux_flags=1;Result r;check(!apply(b,{0x42dfa90,0x41df3e0},false,r)&&!b.calls,"verify only rejects active auxiliary");++tests;}
 {Mock b;b.dispatch=false;Result r;check(!apply(b,{0x41df200,0x41df3e0},true,r)&&!b.calls&&r.setter_calls==0&&error(r,"component_setter_dispatch_refused"),"checked dispatch refusal");++tests;}
 {Mock b;b.state.aux_registration=0x90000;b.state.aux_flags=0xfe;Result r;check(apply(b,{0x42dfa90,0x41df3e0},false,r),"unrelated auxiliary flags preserved");++tests;}
 std::printf("%u component tick policy tests passed (68 captured pairs; offline contracts only)\n",tests);return 0;
}
