#pragma once
#include "plane_initial_state.h"
namespace ac8owner {
// One initial spawn pose only. All other scalar state and aerodynamic data
// stay local to the new actor. No host model/cache memory is imported.
struct InitialSeed {
 std::array<double,3> position{},degrees{};
 std::array<float,3> forward{};float speed=0;
};
inline bool seed_self(plane_initial_state::Snapshot&s,const InitialSeed&p){
 if(!s.complete||!s.source||!s.token||s.scale!=100||!std::isfinite(p.speed)||p.speed<0||p.speed>1e6)return false;
 double norm=0;
 for(unsigned i=0;i<3;++i){
  if(!std::isfinite(p.position[i])||p.position[i]<INT32_MIN||p.position[i]>INT32_MAX||
   !std::isfinite(p.degrees[i])||std::fabs(p.degrees[i])>360||!std::isfinite(p.forward[i]))return false;
  norm+=double(p.forward[i])*p.forward[i];
 }
 if(std::fabs(norm-1)>.002)return false;
 // Validate everything before committing any seed scalar.
 for(unsigned i=0;i<3;++i){
  plane_initial_state::put(s.main,0x2c+4*i,int32_t(p.position[i]));
  plane_initial_state::put(s.main,0x38+4*i,float(p.degrees[i]));
  plane_initial_state::put(s.main,0x20+4*i,p.forward[i]);
 }
 plane_initial_state::put(s.main,0x48,p.speed);return true;
}
}
