#pragma once
#include "guest_control_core.h"
#include <array>
#include <cmath>
namespace ac8player {
// Wire axes -> stock network-cache input setter, not LiveAIPlane input fields.
// Native 4d32580 negates the first three cache channels itself.
inline bool controls(const ac8input::Frame& f,std::array<float,6>& cache) {
 cache={};if(!ac8input::valid(f))return false;
 constexpr float inv=1.0f/32767.0f;
 cache={f.axes[0]*inv,f.axes[2]*inv,f.axes[1]*inv,
        f.axes[3]*inv,f.axes[4]*inv,(f.axes[3]*inv+f.axes[4]*inv)*0.5f};
 return true;
}
struct Pose {std::array<double,3> position{};std::array<float,4> rotation{};};
inline bool finite(const Pose& p) {
 double n=0;for(double v:p.position)if(!std::isfinite(v)||std::fabs(v)>1e7)return false;
 for(float q:p.rotation){if(!std::isfinite(q))return false;n+=double(q)*q;}
 return std::fabs(n-1)<0.002;
}
// Compare orientations modulo q == -q. Translation alone is not input proof.
inline double orientation_delta(const Pose& a,const Pose& b) {
 if(!finite(a)||!finite(b))return -1;
 double plus=0,minus=0;for(unsigned i=0;i<4;++i){double d=double(a.rotation[i])-b.rotation[i],s=double(a.rotation[i])+b.rotation[i];minus+=d*d;plus+=s*s;}
 return std::sqrt(plus<minus?plus:minus);
}
}
