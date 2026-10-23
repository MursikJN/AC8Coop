#include "owner_cleanup.h"
#include <cstdio>
#include <cstdlib>
#include <map>
#include <cstring>
struct Id{uintptr_t p;int32_t index,serial;};
struct Fake{
 std::map<uintptr_t,uint64_t>memory;bool readable=true,live=true,guard=true,stuck=false;
 unsigned dereferences=0,setters=0;uint8_t state=1;bool enabled_set=true,disabled_set=false;
 bool slot(int32_t i,uintptr_t&at){at=0x1000;return readable&&i==7;}
 template<class T>bool read(uintptr_t at,T&v){if(at>=0x2000)++dereferences;auto it=memory.find(at);if(it==memory.end())return false;v=T(it->second);return true;}
 bool same_id(const Id&){return live;}
 bool tick_guard(){return guard;}
 void native_disable_tick(){++setters;if(stuck)return;if(state!=0){enabled_set=false;state=0;disabled_set=true;}}
 bool tick_disabled(){return state==0;}
 void unregister(){if(state==0)disabled_set=false;else enabled_set=false;}
};
int main(){unsigned n=0;auto check=[&](bool ok){++n;if(!ok){std::printf("FAIL cleanup %u\n",n);std::exit(1);}};
 using plane_flight::Seen;
 {Fake b;b.state=0;b.unregister();check(b.enabled_set); // reproduces stale tick after direct byte write
  Fake fixed;check(ac8owner::disable_actor_tick(fixed)&&fixed.setters==1&&!fixed.enabled_set&&fixed.disabled_set);
  fixed.unregister();check(!fixed.enabled_set&&!fixed.disabled_set);
  check(ac8owner::disable_actor_tick(fixed)&&!fixed.enabled_set&&!fixed.disabled_set); // idempotent
  Fake refused;refused.guard=false;check(!ac8owner::disable_actor_tick(refused)&&refused.setters==0);
  refused.guard=true;refused.stuck=true;check(!ac8owner::disable_actor_tick(refused));
 }
 {Fake b;Id id{0x2000,7,12};b.memory={{0x1000,0x2000},{0x1010,12},{0x2008,0},{0x205d,0}};
  check(ac8owner::cleanup_identity(b,id,false)==Seen::safe);
  b.live=false;b.memory[0x2008]=0x40000000;check(ac8owner::cleanup_identity(b,id,true)==Seen::pending);
  check(ac8owner::cleanup_identity(b,id,false)==Seen::unknown);
  b.memory[0x2008]=0;b.memory[0x205d]=1;check(ac8owner::cleanup_identity(b,id,true)==Seen::pending);
  b.memory.erase(0x205d);check(ac8owner::cleanup_identity(b,id,true)==Seen::unknown);
  b.memory[0x1010]=13;b.dereferences=0;check(ac8owner::cleanup_identity(b,id,true)==Seen::retired&&b.dereferences==0);
  b.memory[0x1010]=12;b.memory[0x1000]=0;b.dereferences=0;check(ac8owner::cleanup_identity(b,id,true)==Seen::retired&&b.dereferences==0);
  b.readable=false;check(ac8owner::cleanup_identity(b,id,true)==Seen::unknown);
 }
 {plane_flight::Ledger l;check(!ac8owner::collection_safe(l,false,false));check(ac8owner::collection_safe(l,true,false));
  l.attempted=true;check(!ac8owner::collection_safe(l,true,false));l.identified=true;l.destroy_accepted=true;
  check(!ac8owner::collection_safe(l,true,false));check(ac8owner::collection_safe(l,true,true));
  l.quarantined=true;check(!ac8owner::collection_safe(l,true,true));l.quarantined=false;
  l.unknown_parts=true;check(!ac8owner::collection_safe(l,true,true));l.unknown_parts=false;
  l.unknown_network=true;check(!ac8owner::collection_safe(l,true,true));l.unknown_network=false;
  l.unknown_spawn=true;check(!ac8owner::collection_safe(l,true,true));
 }
 std::printf("%u cleanup contract checks passed; simulated tick sets and object slots only\n",n);
}
