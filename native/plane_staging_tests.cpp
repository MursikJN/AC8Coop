#include "plane_staging_core.h"
#include <cassert>
#include <cstdio>
#include <string_view>
using namespace plane_stage;
struct Mock {
 bool callback=true,acquire_ok=true,barrier_ok=true,network_ok=true,stage_ok=true,duplicate=false,prerequisites=true;
 uintptr_t result=100;
 Seen actor_seen=Seen::safe,network_seen=Seen::safe;
 unsigned creates=0,stages=0,destroys=0,receipts=0;
 Ledger* active=nullptr;
 void event(const char*){}
 uintptr_t spawn(Ledger& l) {active=&l;if(callback){l.receipt(*this,100);++receipts;if(duplicate)l.receipt(*this,100);}return result;}
 bool acquire(uintptr_t p,Identity& id,bool n) {assert(active&&active->attempted);if(!n)assert(active->raw_owned==p);if(!acquire_ok)return false;id={p,n?2:1,42};return true;}
 bool barrier(uintptr_t){assert(active->identified);return barrier_ok;}
 Seen inspect(const Identity&){return actor_seen;}
 Seen resolve(const Identity&){return network_seen;}
 bool network_prerequisites(uintptr_t){return prerequisites;}
 uintptr_t create_network(uintptr_t){assert(active->barrier);++creates;return network_ok?200:0;}
 bool stage(){assert(active->network_identified);++stages;return stage_ok;}
 bool destroy(uintptr_t p){assert(p==100);++destroys;return true;}
};
int main(){
 unsigned count=0;
 {Ledger l;Mock b;l.run(b);assert(l.staged&&b.creates==1&&b.destroys==1&&!l.retired);++count;}
 {Ledger l;Mock b;b.callback=false;l.run(b);assert(!l.received&&b.creates==0&&b.destroys==0);++count;}
 {Ledger l;Mock b;b.acquire_ok=false;l.run(b);assert(l.raw_owned==100&&!l.identified&&b.creates==0&&b.destroys==0);++count;}
 {Ledger l;Mock b;b.barrier_ok=false;l.run(b);assert(!l.barrier&&b.creates==0&&b.destroys==1);++count;}
 {Ledger l;Mock b;b.result=0;l.run(b);assert(l.received&&b.creates==0&&b.destroys==1);++count;}
 {Ledger l;Mock b;b.result=999;l.run(b);assert(b.creates==0&&b.destroys==1);++count;}
 {Ledger l;Mock b;b.duplicate=true;l.run(b);assert(l.callbacks==2&&b.creates==0&&b.destroys==1);++count;}
 {Ledger l;Mock b;b.network_ok=false;l.run(b);assert(!l.raw_network&&b.stages==0&&b.destroys==1);++count;}
 {Ledger l;Mock b;b.stage_ok=false;l.run(b);assert(!l.staged&&b.destroys==1);++count;}
 {Ledger l;Mock b;b.actor_seen=Seen::foreign;l.run(b);assert(b.creates==0&&b.destroys==0);++count;}
 {Ledger l;Mock b;l.run(b);b.actor_seen=Seen::retired;l.verify(b);assert(l.retired&&!l.network_retired&&l.status==std::string_view("cleanup_pending"));++count;}
 {Ledger l;Mock b;l.run(b);b.actor_seen=Seen::retired;b.network_seen=Seen::retired;l.verify(b);assert(l.retired&&l.network_retired&&l.status==std::string_view("retired"));++count;}
 {Ledger l;Mock b;l.run(b);b.actor_seen=Seen::pending;l.verify(b);assert(b.destroys==1&&!l.retired);++count;}
 {Ledger l;Mock b;l.run(b);for(int i=0;i<8;++i)l.verify(b);assert(b.destroys==3);++count;}
 {Ledger l;Mock b;l.run(b);l.run(b);assert(b.receipts==1&&b.creates==1);++count;}
 {Ledger l;Mock b;l.verify(b);assert(!b.receipts&&!b.destroys);++count;}
 {Ledger l;Mock b;b.network_ok=false;l.run(b);b.actor_seen=Seen::retired;l.verify(b);assert(l.network_creation_entered&&l.network_outcome_unknown&&l.status==std::string_view("error"));++count;}
 {Ledger l;Mock b;b.prerequisites=false;l.run(b);b.actor_seen=Seen::retired;l.verify(b);assert(!l.network_creation_entered&&!l.network_outcome_unknown&&l.status==std::string_view("retired"));++count;}
 {Ledger l;Mock b;b.result=999;l.run(b);b.actor_seen=Seen::retired;l.verify(b);assert(l.spawn_outcome_unknown&&l.status==std::string_view("error"));++count;}
 {Ledger l;Mock b;b.duplicate=true;l.run(b);b.actor_seen=Seen::retired;l.verify(b);assert(l.spawn_outcome_unknown&&l.status==std::string_view("error"));++count;}
 std::printf("%u plane staging lifecycle tests passed\n",count);
}
