#pragma once
#include <cstdint>
// Exact native virtual pairs from the captured F14 owned component graph.
// This is a dispatch/readback policy, not a proof that native async work drained.
namespace plane_component_ticks {
enum class Kind { unknown,base,mesh,live };
struct Pair {uintptr_t setter=0,getter=0;};
inline Kind classify(Pair p) {
 if(p.getter==0x41df3e0){if(p.setter==0x41df200)return Kind::base;if(p.setter==0x42dfa90)return Kind::mesh;}
 if(p.setter==0x7d2c180&&p.getter==0x7d2c120)return Kind::live;
 return Kind::unknown;
}
struct State {uint8_t base_tick=0,custom_enabled=0,aux_flags=0;uintptr_t aux_registration=0;};
struct Result {const char* error="not_started";Kind kind=Kind::unknown;State state{};unsigned setter_calls=0;bool verified=false;};
template<class B> bool apply(B& b,Pair pair,bool disable,Result& result) {
 result={};result.kind=classify(pair);
 if(result.kind==Kind::unknown){result.error="component_virtual_pair_unsupported";return false;}
 result.error="component_identity_unverified";if(!b.guard())return false;
 if(disable){
  // Call the actual owned virtual override; never substitute the base setter.
  result.error="component_setter_dispatch_refused";if(!b.set_false(pair.setter))return false;++result.setter_calls;
  result.error="component_identity_changed_after_setter";if(!b.guard())return false;
 }
 result.error="component_tick_readback_unreadable";if(!b.read_state(result.kind,result.state))return false;
 result.error="component_identity_changed_after_readback";if(!b.guard())return false;
 if(result.kind==Kind::live&&result.state.custom_enabled){result.error="component_custom_d3_still_enabled";return false;}
 if(result.state.base_tick){result.error=result.kind==Kind::live?"component_custom_base_tick_active":"component_base_tick_still_active";return false;}
 if(result.kind==Kind::mesh&&result.state.aux_registration&&(result.state.aux_flags&1)){
  result.error="component_mesh_aux_registration_active";return false;
 }
 result.verified=true;result.error="component_tick_domains_disabled";return true;
}
}
