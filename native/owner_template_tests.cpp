#include "owner_template_identity.h"
#include "owner_lab_wait.h"
#include <map>
#include <cstring>
#include <cstdio>
#include <cstdlib>
struct Id{uintptr_t p;int serial;};
struct Fake{
 Id klass{0x10000,1},cdo{0x20000,2};std::map<uintptr_t,uint8_t>memory;
 bool klass_live=true,cdo_live=true;int serial=2;mutable unsigned checks=0;bool retire_during=false;
 template<class T>void set(uintptr_t p,T v){uint8_t bytes[sizeof(T)];memcpy(bytes,&v,sizeof v);for(unsigned i=0;i<sizeof(T);++i)memory[p+i]=bytes[i];}
 template<class T>bool read(uintptr_t p,T&v)const{uint8_t bytes[sizeof(T)];for(unsigned i=0;i<sizeof(T);++i){auto it=memory.find(p+i);if(it==memory.end())return false;bytes[i]=it->second;}memcpy(&v,bytes,sizeof v);return true;}
 bool same_id(const Id&i)const{return klass_live&&i.p==klass.p&&i.serial==klass.serial;}
 bool same_cdo_id(const Id&i)const{return cdo_live&&i.p==cdo.p&&i.serial==serial&&!(retire_during&&++checks>1);}
 Fake(){set(klass.p+0x110,cdo.p);set(cdo.p+0x10,klass.p);set(cdo.p,uintptr_t{0x30000});set(cdo.p+8,uint32_t{0x10});}
};
int main(){unsigned n=0;auto check=[&](bool ok){++n;if(!ok){printf("FAIL template/wait %u\n",n);abort();}};
 using ac8owner::IdentityKind;using ac8owner::identity_flags;
 for(uint32_t flags:{0u,0x10u,0x20000000u,0x40000000u,0x60000000u,0x20000010u,0x40000010u,0x60000010u}){
  check(identity_flags(flags,IdentityKind::instance)==!(flags&0x60000010));
  check(identity_flags(flags,IdentityKind::cdo)==(flags==0x10));
 }
 auto valid=[](const Fake&b){return ac8owner::template_identity(b,b.klass,b.cdo,0x30000);};
 {Fake b;const auto before=b.memory;check(valid(b));check(before==b.memory);}
 {Fake b;b.serial=3;check(!valid(b));}
 {Fake b;b.klass_live=false;check(!valid(b));}
 {Fake b;b.cdo_live=false;check(!valid(b));}
 {Fake b;b.retire_during=true;check(!valid(b));}
 {Fake b;b.set(b.klass.p+0x110,uintptr_t{0x20001});check(!valid(b));}
 {Fake b;b.set(b.cdo.p+0x10,uintptr_t{0x10001});check(!valid(b));}
 {Fake b;b.set(b.cdo.p,uintptr_t{0x30001});check(!valid(b));}
 {Fake b;b.set(b.cdo.p+8,uint32_t{0});check(!valid(b));}
 {Fake b;b.set(b.cdo.p+8,uint32_t{0x40000010});check(!valid(b));}
 {Fake b;b.memory.erase(b.cdo.p+8);check(!valid(b));}
 {ac8owner::LabWait w;check(!w.expired(999999));w.observe_connection(1000);check(w.idle_budget()==60000);
  check(!w.expired(17000));check(!w.expired(46000));w.observe_connection(50000);check(w.connected_at==1000);
  check(!w.expired(60999));check(w.expired(61000));check(w.expired(999));
  w.loaded=true;check(w.idle_budget()==15000&&!w.expired(999999));}
 printf("owner template identity and helper loading window: %u checks passed; fake memory/virtual clock only\n",n);
}
