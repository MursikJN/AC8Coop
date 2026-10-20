#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <cmath>
namespace plane_flight_observations {
enum class Stage { none,seed,t1,t5,t10,before_destroy };
inline const char* name(Stage s){switch(s){case Stage::seed:return "seed";case Stage::t1:return "t1";case Stage::t5:return "t5";case Stage::t10:return "t10";case Stage::before_destroy:return "before_destroy";default:return "none";}}
struct Schedule {
 unsigned mask=0;
 Stage pose(uint64_t elapsed,bool seed){
  if(mask&16)return Stage::none;
  if(seed){if(mask&1)return Stage::none;mask|=1;return Stage::seed;}
  const uint64_t deadlines[]={1000,5000,10000};const Stage stages[]={Stage::t1,Stage::t5,Stage::t10};
  for(unsigned i=0;i<3;++i){unsigned bit=2u<<i;if(elapsed>=deadlines[i]&&!(mask&bit)){mask|=bit;return stages[i];}}
  return Stage::none;
 }
 Stage cleanup(){if(mask&16)return Stage::none;mask|=16;return Stage::before_destroy;}
};
template<class F> void best_effort(F&& fn,unsigned& failures) noexcept {try{if(!fn())++failures;}catch(...){++failures;}}
struct Identity {uintptr_t pointer=0,vtable=0,klass=0,outer=0;uint64_t name=0;int32_t index=-1,serial=0;uint32_t flags=0;};
using Vec=std::array<double,3>;
inline bool finite(const Vec& v){for(double x:v)if(!std::isfinite(x)||std::fabs(x)>1e12)return false;return true;}
inline bool same_identity(const Identity& a,const Identity& b){return a.pointer&&a.pointer==b.pointer&&a.index==b.index&&a.serial==b.serial&&a.vtable==b.vtable&&a.klass==b.klass&&a.outer==b.outer&&a.name==b.name;}
struct Scene {
 Identity identity{};bool identity_valid=false,scene_verified=false,owner_matches=false,raw_transform_valid=false,transform_valid=false,flags_valid=false;
 uintptr_t owner=0;Vec world{};std::array<unsigned char,96> raw_transform{};std::array<unsigned char,9> raw_flags{};
};
struct Reference {Identity identity{};bool valid=false;};
struct Actor {
 Identity identity{};bool identity_valid=false,flags_valid=false;uint8_t raw58=0,active3f4=0;
 uintptr_t root_pointer=0;Scene root{};Reference geometry15a0{},geometry1af8{};
};
template<class R> bool capture_scene(R& r,uintptr_t object,uintptr_t owner,Scene& out){
 out={};if(!r.identify(object,out.identity))return false;out.identity_valid=true;
 out.scene_verified=r.scene(object);if(!out.scene_verified)return false;
 out.owner_matches=r.read(object+0x90,&out.owner,8)&&out.owner==owner;
 if(!out.owner_matches)return false;
 out.flags_valid=r.read(object+0x188,out.raw_flags.data(),out.raw_flags.size());
 out.raw_transform_valid=r.read(object+0x200,out.raw_transform.data(),out.raw_transform.size());
 if(out.raw_transform_valid){
  std::memcpy(out.world.data(),out.raw_transform.data()+0x20,24);out.transform_valid=finite(out.world);
 }
 if(!r.unchanged(out.identity)){out.identity_valid=false;out.scene_verified=false;out.owner_matches=false;out.flags_valid=false;out.raw_transform_valid=false;out.transform_valid=false;return false;}
 return out.flags_valid&&out.transform_valid;
}
template<class R> void capture_reference(R& r,uintptr_t field,Reference& out){uintptr_t p=0;out={};out.valid=r.read(field,&p,8)&&r.identify(p,out.identity)&&r.unchanged(out.identity);}
template<class R> bool capture_actor(R& r,uintptr_t object,Actor& out){
 out={};if(!r.identify(object,out.identity))return false;out.identity_valid=true;
 out.flags_valid=r.read(object+0x58,&out.raw58,1)&&r.read(object+0x3f4,&out.active3f4,1);
 if(r.read(object+0x1a0,&out.root_pointer,8))capture_scene(r,out.root_pointer,object,out.root);
 capture_reference(r,object+0x15a0,out.geometry15a0);capture_reference(r,object+0x1af8,out.geometry1af8);
 if(!r.unchanged(out.identity)){out.identity_valid=false;out.flags_valid=false;out.root.transform_valid=false;return false;}
 return out.flags_valid&&out.root.transform_valid;
}
struct Delta {bool valid=false;Vec xyz{};double distance=0;};
inline Delta difference(const Vec& a,const Vec& b,bool eligible){
 Delta d;if(!eligible||!finite(a)||!finite(b))return d;
 double sum=0;for(unsigned i=0;i<3;++i){d.xyz[i]=a[i]-b[i];sum+=d.xyz[i]*d.xyz[i];}
 d.distance=std::sqrt(sum);d.valid=std::isfinite(d.distance);return d;
}
struct Metrics {Delta actual_step{},request_error{},source_delta{};};
inline Metrics metrics(const Actor& before,const Actor& after,const Actor& source,const Vec& requested,bool requested_valid){
 Metrics m;bool a=after.identity_valid&&after.root.identity_valid&&after.root.transform_valid;
 m.actual_step=difference(after.root.world,before.root.world,a&&before.identity_valid&&before.root.transform_valid&&same_identity(after.root.identity,before.root.identity));
 m.request_error=difference(after.root.world,requested,a&&requested_valid);
 m.source_delta=difference(after.root.world,source.root.world,a&&source.identity_valid&&source.root.identity_valid&&source.root.transform_valid);return m;
}
}
