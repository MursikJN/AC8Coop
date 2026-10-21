#pragma once
#include "plane_flight_observations.h"
// R5.1 contract: one native SetVisibility(main, true, 0), never a raw flag write.
namespace plane_main_visibility {
namespace obs=plane_flight_observations;
constexpr uintptr_t setter_rva=0x42ce610,main_vtable_rva=0xbc9b428;
struct Snapshot {
 obs::Identity source{},owned{};
 obs::Scene source_main{},source_secondary{},main{},secondary{};
 uintptr_t gate=0;uint8_t gate_byte=0,active=0;bool barriers=false;
};
struct Report {
 Snapshot before{},after{};bool before_valid=false,after_valid=false,called=false,verified=false;
 const char* error="not_started";
};
inline bool identity_ok(const obs::Identity& i){return i.pointer&&i.index>=0&&i.serial>=0&&!(i.flags&(0x10|0x20|0x40000000));}
inline bool scene_ok(const obs::Scene& s,const obs::Identity& actor){
 return s.identity_valid&&identity_ok(s.identity)&&s.scene_verified&&s.owner_matches&&s.flags_valid&&
  s.owner==actor.pointer&&s.identity.outer==actor.pointer;
}
inline bool valid(const Snapshot& s,uintptr_t image){
 if(!identity_ok(s.source)||!identity_ok(s.owned)||s.source.pointer==s.owned.pointer||s.active||!s.barriers||
    !scene_ok(s.source_main,s.source)||!scene_ok(s.source_secondary,s.source)||
    !scene_ok(s.main,s.owned)||!scene_ok(s.secondary,s.owned))return false;
 const uintptr_t ptrs[]={s.source.pointer,s.owned.pointer,s.source_main.identity.pointer,s.source_secondary.identity.pointer,s.main.identity.pointer,s.secondary.identity.pointer};
 for(unsigned i=0;i<6;++i)for(unsigned j=0;j<i;++j)if(ptrs[i]==ptrs[j])return false;
 return s.main.identity.vtable==image+main_vtable_rva&&s.source_main.identity.vtable==s.main.identity.vtable&&
  s.main.identity.klass==s.source_main.identity.klass&&s.secondary.identity.klass==s.source_secondary.identity.klass&&
  s.secondary.identity.vtable==s.source_secondary.identity.vtable;
}
inline bool stable_scene(const obs::Scene& a,const obs::Scene& b){return obs::same_identity(a.identity,b.identity)&&a.raw_flags==b.raw_flags;}
inline const char* precondition_error(const Snapshot& s,uintptr_t image){
 if(!valid(s,image))return "visibility_identity_owner_class_or_barrier_unverified";
 // Independent R4/R5 bytes at +188..190: 41 00 08 02 00 00 00 00 00.
 // 08 is at +18A (index 2); +190 (index 8) is 00. Never infer offsets from prose.
 constexpr std::array<unsigned char,9> expected_main={0x41,0,8,2,0,0,0,0,0};
 if(s.main.raw_flags!=expected_main)return "visibility_main_raw_flags_outside_contract";
 if(!(s.source_main.raw_flags[0]&0x20)||(s.source_main.raw_flags[1]&8))return "visibility_source_main_not_visible";
 if(s.secondary.raw_flags[0]!=0x43||s.source_secondary.raw_flags[0]!=0x43)return "visibility_secondary_raw_flags_outside_contract";
 return nullptr;
}
inline bool precondition(const Snapshot& s,uintptr_t image){return precondition_error(s,image)==nullptr;}
inline bool postcondition(const Snapshot& a,const Snapshot& b,uintptr_t image){
 auto expected=a.main.raw_flags;expected[0]|=0x20;
 return valid(b,image)&&obs::same_identity(a.source,b.source)&&obs::same_identity(a.owned,b.owned)&&
  obs::same_identity(a.main.identity,b.main.identity)&&b.main.raw_flags==expected&&
  stable_scene(a.source_main,b.source_main)&&stable_scene(a.source_secondary,b.source_secondary)&&
  stable_scene(a.secondary,b.secondary)&&(!b.gate||b.gate_byte!=0);
}
template<class B> bool enable(B& b,uintptr_t image,Report& r){
 // A consumed call cannot be retried even if a postcondition failed.
 if(r.called){r.error="visibility_attempt_consumed";return false;}
 r.before_valid=b.capture(r.before);
 if(!r.before_valid){r.error="visibility_snapshot_unreadable";return false;}
 if(const char* error=precondition_error(r.before,image)){r.error=error;return false;}
 r.error="visibility_precondition_verified";
 if(!b.setter_ready(r.before)){r.error="visibility_setter_guard_failed";return false;}
 r.called=true;b.set_main(r.before.main.identity.pointer);
 r.after_valid=b.capture(r.after);
 r.verified=r.after_valid&&postcondition(r.before,r.after,image);
 r.error=r.verified?"main_visibility_verified":"visibility_postcondition_failed";return r.verified;
}
}
