#include "plane_flight_cadence.h"
#include <cstdio>
#include <cstdlib>
#include <cmath>
namespace c=plane_flight_cadence;
unsigned checks=0;
void check(bool ok,const char* label){++checks;if(!ok){std::printf("FAIL %s\n",label);std::exit(1);}}
int main(){
 {c::StatusGate g;check(g.publish(100,false),"preflight status immediate");check(g.publish(110,false),"spawn status immediate");
  check(!g.publish(111,true)&&!g.publish(1109,true),"active frames do not write synchronous status");
  check(g.publish(1110,true),"one second heartbeat");check(g.publish(1111,false),"error not throttled");
  check(g.publish(1112,false),"cleanup not throttled");check(g.publish(1113,false),"retirement not throttled");}
 {c::StatusGate g;unsigned writes=0;g.publish(1000,false);for(unsigned i=1;i<=3600;++i)if(g.publish(1000+i*4,true))++writes;
  check(writes==14,"250Hz updates produce bounded 1Hz reports");check(g.publish(500,false),"clock reversal forces status");}
 {float dt=0;bool clamp=false;check(c::delta(1000000,1008333,dt,clamp)&&!clamp&&std::fabs(dt-0.008333f)<1e-7f,"120Hz dt is not quantized to GetTickCount64");
  check(c::delta(1000000,1069000,dt,clamp)&&!clamp&&std::fabs(dt-0.069f)<1e-7f,"baseline 69ms preserved");
  check(c::delta(1000000,1422000,dt,clamp)&&clamp&&dt==0.1f,"422ms stall retains 100ms native dt cap");
  check(!c::delta(1000000,1000000,dt,clamp),"duplicate clock rejected");check(!c::delta(1000000,999999,dt,clamp),"reversed clock rejected");check(!c::delta(0,1000000,dt,clamp),"uninitialized clock rejected");}
 // Heap allocation: the bounded trace is intentionally larger than a small thread stack.
 auto* t=new c::Trace;for(unsigned i=0;i<c::max_samples+12;++i){c::Sample s;s.begin_us=i;s.requested[0]=i;t->append(s);}
 check(t->count==c::max_samples&&t->dropped==12,"trace cannot overrun or grow without bound");
 check(t->samples.front().begin_us==0&&t->samples.back().begin_us==4095,"trace retains first and last valid records");delete t;
 std::printf("%u cadence checks passed\n",checks);return 0;
}
