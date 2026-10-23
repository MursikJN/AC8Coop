#include "owner_sound_readiness.h"
#include <map>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <vector>
struct Id{uintptr_t p=0;int serial=0;};
struct Fake{
 ac8owner::SoundObjects<Id>s{{0x10000,1},{0x20000,2},0x30000,0x40000,0x50000};
 std::map<uintptr_t,uint8_t>m;bool thread=true,identity=true;mutable unsigned identities=0;unsigned retire_at=0;
 Fake(){set(s.gi.p+0x908,s.manager.p);set(s.manager.p+0x1a8,s.registry);set(s.manager.p+0x210,s.settings);set(s.settings+0x140,s.names);for(unsigned i=0;i<3;++i)set(s.names+0x1c8+i*8,uint64_t{0});}
 template<class T>void set(uintptr_t p,T v){uint8_t b[sizeof(T)]{};memcpy(b,&v,sizeof v);for(unsigned i=0;i<sizeof(T);++i)m[p+i]=b[i];}
 template<class T>bool read(uintptr_t p,T&v)const{uint8_t b[sizeof(T)]{};for(unsigned i=0;i<sizeof(T);++i){auto a=m.find(p+i);if(a==m.end())return false;b[i]=a->second;}memcpy(&v,b,sizeof v);return true;}
 bool game_thread()const{return thread;}
 bool same_id(const Id&)const{++identities;return identity&&(!retire_at||identities<retire_at);}
};
int main(){unsigned checks=0;auto check=[&](bool ok){if(!ok){printf("FAIL sound %u\n",checks);abort();}++checks;};
 {Fake f;const auto before=f.m;check(!ac8owner::sound_objects_error(f,f.s));check(f.m==before);}
 const std::vector<std::function<void(Fake&)>> faults={
 [](Fake&f){f.thread=false;},[](Fake&f){f.identity=false;},[](Fake&f){f.retire_at=3;},
 [](Fake&f){f.set(f.s.gi.p+0x908,uintptr_t{0});},[](Fake&f){f.set(f.s.manager.p+0x1a8,uintptr_t{0});},
 [](Fake&f){f.set(f.s.manager.p+0x210,uintptr_t{0});},[](Fake&f){f.set(f.s.settings+0x140,uintptr_t{0});},
 [](Fake&f){f.m.erase(f.s.names+0x1c8);},[](Fake&f){f.m.erase(f.s.names+0x1d0);},[](Fake&f){f.m.erase(f.s.names+0x1d8);},
 [](Fake&f){f.s.registry=1;},[](Fake&f){f.s.settings=0x800000000000ULL;},[](Fake&f){f.s.names=0;}
 };
 for(const auto&fault:faults){Fake f;fault(f);const auto before=f.m;check(ac8owner::sound_objects_error(f,f.s)!=nullptr);check(f.m==before);}
 printf("owner sound readiness: %u checks passed; fake memory, no game calls\n",checks);
}
