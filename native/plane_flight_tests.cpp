#include "plane_flight_core.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
using namespace plane_flight;
struct Mock {
 Ledger* l=nullptr; Seen plane=Seen::safe,net=Seen::safe,parts=Seen::safe;
 bool identify=true,barrier=true,configure_ok=true,preseed_ok=true,ready=true,components=true,graph=true,seed_ok=true,motion_ok=true,cleanup_ok=true,pending_flag=false;
 bool receipt=true,duplicate=false,mismatch=false,unknown_net=false,accept_destroy=true;unsigned closes=0,quarantine_passes=0,finish_calls=0,spawn_calls=0,destroy_calls=0,seed_calls=0;
 uint64_t clock=100;
 bool acquire(uintptr_t p,Identity& i,int){i={p,1,2};return identify;}
 Seen resolve(const Identity& i){return i.pointer==22?net:i.pointer==33?parts:plane;}
 bool initial_barrier(uintptr_t){return barrier;}
 void close_actor_barrier(){++closes;}
 void quarantine_components(){++quarantine_passes;}
 void event(const char*){}
 bool pending(){return pending_flag;}
 bool cleanup_guard(bool){return cleanup_ok;}
 bool destroy(uintptr_t){++destroy_calls;return accept_destroy;}
 uintptr_t spawn(Ledger& x){l=&x;++spawn_calls;if(receipt)x.receipt(*this,11);if(duplicate)x.receipt(*this,11);return mismatch?44:11;}
 bool configure(){
  l->network_entered=true;if(unknown_net){l->unknown_network=true;return false;}
  l->raw_network=22;l->network={22,2,3};l->network_identified=true;
  l->parts_entered=true;l->raw_parts=33;l->parts={33,3,4};l->parts_identified=true;return configure_ok;
 }
 bool ready_to_finish(){return ready;}
 bool preseed(){return preseed_ok;}
 void finish(){++finish_calls;}
 bool disable_components(){return components;}
 bool finished_graph(){return graph;}
 bool seed(){++seed_calls;return seed_ok;}
 bool motion(){return motion_ok;}
 uint64_t now(){return clock;}
};
void check(bool ok,const char* name){if(!ok){std::printf("FAIL %s\n",name);std::exit(1);}}
bool state(const Ledger& l,const char* s){return !std::strcmp(l.status,s);}
int main(){unsigned n=0;
 {Ledger l;Mock b;l.run(b);check(state(l,"active")&&l.finished_ready&&b.finish_calls==1&&b.destroy_calls==0,"full sequence");++n;}
 {Ledger l;Mock b;l.run(b);l.run(b);check(b.spawn_calls==1&&state(l,"error"),"one attempt");++n;}
 {Ledger l;Mock b;b.identify=false;l.run(b);check(!b.finish_calls&&!b.destroy_calls,"unidentified never freed");++n;}
 {Ledger l;Mock b;b.barrier=false;l.run(b);check(!b.finish_calls&&b.destroy_calls==1,"cold barrier failure rollback");++n;}
 {Ledger l;Mock b;b.configure_ok=false;l.run(b);check(!b.finish_calls&&b.destroy_calls==1,"configuration failure rollback");++n;}
 {Ledger l;Mock b;b.ready=false;l.run(b);check(!b.finish_calls&&b.destroy_calls==1,"pre finish gate");++n;}
 {Ledger l;Mock b;b.preseed_ok=false;l.run(b);check(!l.finish_entered&&!b.finish_calls&&b.destroy_calls==1&&!l.finished_ready,"first state failure cold rollback before Finish");++n;}
 {Ledger l;Mock b;b.components=false;l.run(b);check(state(l,"quarantine")&&b.destroy_calls==0&&b.quarantine_passes==1,"partial component graph quarantine");++n;}
 {Ledger l;Mock b;b.graph=false;l.run(b);l.cleanup(b);check(state(l,"quarantine")&&!b.destroy_calls,"partial graph cannot destroy");++n;}
 {Ledger l;Mock b;b.seed_ok=false;l.run(b);check(l.finished_ready&&b.destroy_calls==1,"seed failure complete graph rollback");++n;}
 {Ledger l;Mock b;l.run(b);b.motion_ok=false;l.tick(b);check(b.destroy_calls==1&&!l.running,"update failure cleanup");++n;}
 {Ledger l;Mock b;l.run(b);b.clock+=15000;l.tick(b);check(b.destroy_calls==1&&l.ticks==0,"absolute lifetime limit");++n;}
 {Ledger l;Mock b;l.run(b);b.clock+=50;l.tick(b);check(l.ticks==1&&state(l,"active"),"bounded update");++n;}
 {Ledger l;Mock b;l.run(b);b.cleanup_ok=false;l.cleanup(b);check(state(l,"quarantine")&&!b.destroy_calls,"cleanup graph guard");++n;}
 {Ledger l;Mock b;l.run(b);b.plane=Seen::unknown;l.cleanup(b);check(state(l,"quarantine")&&!b.destroy_calls,"unknown weak identity");++n;}
 {Ledger l;Mock b;l.run(b);b.plane=Seen::retired;l.cleanup(b);check(state(l,"cleanup_pending"),"children independent retirement");b.net=Seen::retired;b.parts=Seen::retired;l.cleanup(b);check(state(l,"retired"),"all retire");++n;}
 {Ledger l;Mock b;b.unknown_net=true;l.run(b);b.plane=Seen::retired;l.cleanup(b);check(state(l,"quarantine"),"unknown network cannot report retired");++n;}
 {Ledger l;Mock b;b.duplicate=true;l.run(b);b.plane=Seen::retired;l.cleanup(b);check(state(l,"quarantine"),"duplicate receipt stays unknown");++n;}
 {Ledger l;Mock b;b.mismatch=true;l.run(b);b.plane=Seen::retired;l.cleanup(b);check(state(l,"quarantine"),"different spawn return stays unknown");++n;}
 {Ledger l;Mock b;b.receipt=false;l.run(b);check(state(l,"quarantine")&&!b.destroy_calls,"no receipt no destroy");++n;}
 {Ledger l;Mock b;b.graph=false;l.run(b);b.pending_flag=true;l.cleanup(b);check(state(l,"quarantine"),"quarantine sticky during pending");++n;}
 {Ledger l;Mock b;b.accept_destroy=false;l.run(b);for(int i=0;i<5;++i)l.cleanup(b);check(b.destroy_calls==3,"bounded refused destroy retries");++n;}
 {Ledger l;Mock b;l.run(b);l.cleanup(b);auto closes=b.closes;for(int i=0;i<5;++i)l.cleanup(b);check(b.destroy_calls==1&&b.closes==closes&&!l.plane_retired,"accepted destroy is never repeated");++n;}
 {Ledger l;Mock b;l.run(b);l.cleanup(b);b.plane=Seen::pending;l.cleanup(b);check(state(l,"cleanup_pending")&&!l.quarantined&&!l.plane_retired&&b.destroy_calls==1,"garbage flag is pending not unknown or retired");++n;}
 {Ledger l;Mock b;l.run(b);b.plane=Seen::pending;l.cleanup(b);check(state(l,"quarantine")&&!b.destroy_calls,"unowned pending transition quarantined");++n;}
 {Ledger l;Mock b;l.run(b);b.pending_flag=true;l.cleanup(b);check(!b.destroy_calls&&state(l,"cleanup_pending"),"pending engine destroy not repeated");++n;}
 {Ledger l;Mock b;l.lifetime_ms=0;l.run(b);b.clock+=3600000;l.tick(b);check(l.running&&l.ticks==1&&b.destroy_calls==0,"continuous survives one hour");++n;}
 {Ledger l;Mock b;l.lifetime_ms=0;l.run(b);b.clock+=3600000;b.motion_ok=false;l.tick(b);check(!l.running&&b.destroy_calls==1,"continuous failure still cleans up");++n;}
 {Ledger l;Mock b;l.lifetime_ms=0;l.run(b);b.clock+=3600000;l.cleanup(b);check(!l.running&&b.destroy_calls==1,"continuous explicit stop cleans up");++n;}
 {Ledger l;Mock b;check(l.prepare(b)&&l.finished_ready&&!l.running&&state(l,"prepared")&&b.seed_calls==0&&b.finish_calls==1,"prepare holds actor without motion seed");++n;l.cleanup(b);check(b.destroy_calls==1,"prepared actor remains owned and cleanable");++n;}
 {Ledger l;Mock b;b.graph=false;check(!l.prepare(b)&&state(l,"quarantine")&&!l.running&&!b.seed_calls,"prepare rejects partial graph");++n;}
 std::printf("%u plane flight lifecycle tests passed\n",n);return 0;
}
