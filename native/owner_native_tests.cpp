// Reuse the established byte-addressable model fixture, not game code/data.
#include "plane_flight_state_fixture.h"
#include "owner_initial_seed.h"
#include "owner_spawn_receipt.h"
#include "owner_retirement.h"
struct ReceiptBackend{unsigned calls=0;uintptr_t actor=0;};
struct ReceiptLedger{void receipt(ReceiptBackend&b,uintptr_t p){++b.calls;b.actor=p;}};
int main(){unsigned checks=0;auto check=[&](bool ok){++checks;if(!ok){std::printf("FAIL owner native contract %u\n",checks);std::abort();}};
 {plane_flight::Ledger l;l.attempted=true;check(!ac8owner::retirement_complete(l,true,true));
  l.plane_retired=true;check(ac8owner::retirement_complete(l,true,true));
  l.raw_network=22;check(!ac8owner::retirement_complete(l,true,true));l.network_retired=true;check(ac8owner::retirement_complete(l,true,true));
  l.raw_parts=33;check(!ac8owner::retirement_complete(l,true,true));l.parts_retired=true;
  check(!ac8owner::retirement_complete(l,false,true)&&!ac8owner::retirement_complete(l,true,false));
  l.unknown_parts=true;check(!ac8owner::retirement_complete(l,true,true));l.unknown_parts=false;check(ac8owner::retirement_complete(l,true,true));
 }
 {using C=ac8owner::SpawnReceipt<ReceiptBackend,ReceiptLedger>;ReceiptBackend b;ReceiptLedger l;C::Context ctx{&b,&l};uintptr_t table[3]{};C::Storage storage{table,&ctx};
  uintptr_t p=0x12345678;auto*context=C::address(&storage);check(context==&ctx&&context!=&storage&&context!=&b);C::invoke(context,&p);check(b.calls==1&&b.actor==p);C::invoke(context,nullptr);check(b.calls==2&&b.actor==0);
 }
 {FlightFake f;Report r;check(finalize(f,f.s,f.owned,r));f.source=f.owned.plane;Snapshot self;const char*why=nullptr;
  check(capture(f,f.source,f.image,123,self,why));const auto before=f.writes;Result result;
  check(!stage(f,self,f.owned,result)&&f.writes==before); // legacy remains cross-actor only
  ac8owner::InitialSeed seed;seed.position={33000,9000,4000};seed.forward={0,-1,0};seed.speed=0;
  const auto original=self;check(ac8owner::seed_self(self,seed));
  check(self.aux140==original.aux140&&self.aux150==original.aux150&&self.aux160==original.aux160&&self.aux170==original.aux170&&self.timestamp==original.timestamp);
  check(stage_self(f,self,f.owned,result)&&result.scalar_writes==46&&result.readback);
  f.s=self;Report local;check(finalize_self(f,self,f.owned,local)&&local.models_seeded&&local.inputs_verified);
  f.set(f.owned.data[0]+0x50,uintptr_t{0x11223344});
  check(stage_self(f,self,f.owned,result));uintptr_t untouched=0;check(f.read(f.owned.data[0]+0x50,&untouched,sizeof untouched)&&untouched==0x11223344);
  auto cross=self;cross.source=0x10000;const auto writes=f.writes;check(!stage_self(f,cross,f.owned,result)&&f.writes==writes);
  auto bad=self;seed.position[0]=INFINITY;check(!ac8owner::seed_self(bad,seed)&&bad.main==self.main);
  seed.position[0]=33000;seed.forward={0,0,0};check(!ac8owner::seed_self(bad,seed)&&bad.main==self.main);
  seed.forward={0,-1,0};seed.speed=-1;check(!ac8owner::seed_self(bad,seed)&&bad.main==self.main);
  f.set(f.owned.network+0x20,uintptr_t{0xdeadbeef});check(!stage_self(f,self,f.owned,result));
 }
 std::printf("owner native staging/receipt: %u checks passed; fake memory only, no game/native dispatch\n",checks);return 0;
}
