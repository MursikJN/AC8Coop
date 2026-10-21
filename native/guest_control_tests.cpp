#include "guest_control_core.h"
#include <cstdio>
#include <cstdlib>
static unsigned checks=0;
static void check(bool x){++checks;if(!x){fprintf(stderr,"Guest control check %u failed\n",checks);exit(1);}}
static ac8input::Assignment assignment(){ac8input::Assignment a;a.peer=2;a.remote_nonce=20;a.local_nonce=10;a.generation=7;a.revision=3;a.slot=1;a.aircraft=23;a.host=a.world_loaded=a.guest_loaded=a.player_flight_engine=a.npc_detached=a.host_pawn_unchanged=true;return a;}
static ac8input::Frame input(){ac8input::Frame f;f.sender=2;f.session=20;f.echo=10;f.sequence=1;f.generation=7;f.revision=3;f.slot=1;f.aircraft=23;f.axes={-32767,32767,0,32767,0};return f;}
int main(){
 using namespace ac8input;auto f=input();check(valid(f));Frame decoded;auto bytes=encode(f);check(decode(bytes.data(),bytes.size(),decoded));check(decoded.axes==f.axes);
 check(!decode(nullptr,bytes.size(),decoded));check(!decode(bytes.data(),bytes.size()-1,decoded));
 for(size_t i:{size_t(0),size_t(4),size_t(6),size_t(8),size_t(12),size_t(82),size_t(95)}){auto b=bytes;b[i]^=1;check(!decode(b.data(),b.size(),decoded));}
 for(auto change:{0,1,2,3,4,5}){auto bad=f;switch(change){case 0:bad.slot=4;break;case 1:bad.aircraft=7;break;case 2:bad.buttons=1;break;case 3:bad.axes[0]=-32768;break;case 4:bad.axes[3]=-1;break;case 5:bad.axes[4]=-1;break;}check(!valid(bad));}
 Lease l;Frame out;check(!l.accept(f,100));check(!l.sample(100,out));
 auto a=assignment();
 for(auto flag:{&Assignment::host,&Assignment::world_loaded,&Assignment::guest_loaded,&Assignment::player_flight_engine,&Assignment::npc_detached,&Assignment::host_pawn_unchanged}){auto bad=a;bad.*flag=false;check(!l.bind(bad));check(!l.accept(f,100));}
 check(l.bind(a));check(l.accept(f,100));check(l.sample(400,out));check(out.axes==f.axes);check(!l.sample(401,out));check(!l.accept(f,402));
 f.sequence=2;check(l.accept(f,403));check(l.sample(404,out));
 for(int i=0;i<7;++i){auto bad=f;bad.sequence=3;switch(i){case 0:++bad.sender;break;case 1:++bad.session;break;case 2:++bad.echo;break;case 3:++bad.generation;break;case 4:++bad.revision;break;case 5:++bad.slot;break;case 6:bad.aircraft=7;break;}check(!l.accept(bad,405));}
 check(l.sample(405,out)&&out.sequence==2);f.sequence=3;check(!l.accept(f,402));
 // No 15-second flight cap: fresh intent keeps the lease alive indefinitely.
 for(uint64_t now=500;now<60000;now+=100){++f.sequence;check(l.accept(f,now));check(l.sample(now+99,out));}
 l.revoke();check(!l.sample(60000,out));check(!l.accept(f,60000));
 a.generation=8;check(l.bind(a));check(!l.accept(f,60001));f.generation=8;check(l.accept(f,60002));
 puts("Guest control wire, assignment and input lease checks passed");printf("%u checks\n",checks);
}
