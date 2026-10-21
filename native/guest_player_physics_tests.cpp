#include "guest_player_physics.h"
#include <cassert>
#include <cstdio>
#include <limits>
int main(){unsigned checks=0;
 ac8input::Frame f;f.sender=1;f.session=2;f.echo=3;f.sequence=1;f.generation=4;f.revision=1;f.slot=1;f.aircraft=23;
 std::array<float,6> out;
 for(int p:{-32767,0,32767})for(int r:{-32767,0,32767})for(int y:{-32767,0,32767})for(int t:{0,32767})for(int b:{0,32767}){
  f.axes={int16_t(p),int16_t(r),int16_t(y),int16_t(t),int16_t(b)};assert(ac8player::controls(f,out));
  assert(out[0]==float(p)/32767&&out[1]==float(y)/32767&&out[2]==float(r)/32767);
  assert(out[3]==float(t)/32767&&out[4]==float(b)/32767&&out[5]==(float(t)+b)/65534);++checks;
 }
 f.buttons=1;assert(!ac8player::controls(f,out));for(float v:out)assert(v==0);++checks;f.buttons=0;
 f.axes[0]=INT16_MIN;assert(!ac8player::controls(f,out));++checks;f.axes[0]=0;
 f.axes[3]=-1;assert(!ac8player::controls(f,out));++checks;
 ac8player::Pose a{{1,2,3},{0,0,0,1}},b=a;assert(ac8player::finite(a));assert(ac8player::orientation_delta(a,b)==0);++checks;
 b.rotation[3]=-1;assert(ac8player::orientation_delta(a,b)==0);++checks;
 b.rotation={0,0,0.6f,0.8f};assert(ac8player::orientation_delta(a,b)>0.6);++checks;
 b.position[0]=std::numeric_limits<double>::infinity();assert(!ac8player::finite(b)&&ac8player::orientation_delta(a,b)==-1);++checks;
 b=a;b.rotation[3]=0.5f;assert(!ac8player::finite(b));++checks;
 std::printf("guest player physics: %u mapping and pose checks passed; no engine calls\n",checks);
}
