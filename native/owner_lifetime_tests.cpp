#include "owner_identity_capture.h"
#include "owner_root_lease.h"
#include <map>
#include <cstring>
#include <cstdio>
#include <cstdlib>
struct Id{uintptr_t p=0;int32_t index=-1,serial=0;};
struct Fake{
 std::map<uintptr_t,uint8_t>mem;Id obj{0x10000,7,42};unsigned mints=0,sets=0,clears=0;
 bool root=false,alive=true,slot_ok=true,bad_mint=false,replace=false,set_fails=false,clear_fails=false;
 template<class T>void put(uintptr_t p,T v){auto b=reinterpret_cast<const uint8_t*>(&v);for(unsigned i=0;i<sizeof(T);++i)mem[p+i]=b[i];}
 template<class T>bool read(uintptr_t p,T&v){uint8_t b[sizeof(T)];for(unsigned i=0;i<sizeof(T);++i){auto it=mem.find(p+i);if(it==mem.end())return false;b[i]=it->second;}memcpy(&v,b,sizeof v);return true;}
 bool slot(int32_t index,uintptr_t&at){at=0x20000;return slot_ok&&index==7;}
 int32_t mint(int32_t){++mints;put(0x20010,int32_t{42});if(replace)put(0x20000,uintptr_t{0x10001});return bad_mint?43:42;}
 bool live(const Id&i){return alive&&i.p==obj.p&&i.index==obj.index&&i.serial==obj.serial;}
 bool rooted(const Id&){return root;}
 void set_root(const Id&){++sets;if(!set_fails)root=true;}
 void clear_root(const Id&){++clears;if(!clear_fails)root=false;}
 Fake(){put(obj.p+12,obj.index);put(obj.p+8,uint32_t{0});put(0x20000,obj.p);put(0x20010,int32_t{0});}
};
int main(){unsigned n=0;auto check=[&](bool ok){++n;if(!ok){printf("FAIL owner lifetime %u\n",n);abort();}};
 auto capture=[](Fake&b,Id&out,bool mint,const char*&why){return ac8owner::capture_identity(b,b.obj.p,out,mint,ac8owner::IdentityKind::instance,why);};
 const char*why=nullptr;Id out;
 {Fake b;check(!capture(b,out,false,why)&&!strcmp(why,"serial_unassigned")&&b.mints==0);check(capture(b,out,true,why)&&out.serial==42&&b.mints==1);check(capture(b,out,true,why)&&b.mints==1);}
 {Fake b;b.bad_mint=true;check(!capture(b,out,true,why)&&!strcmp(why,"serial_mint_readback"));}
 {Fake b;b.replace=true;check(!capture(b,out,true,why)&&!strcmp(why,"identity_changed"));}
 {Fake b;b.put(b.obj.p+8,uint32_t{0x10});check(!capture(b,out,true,why)&&!strcmp(why,"object_flags")&&!b.mints);check(ac8owner::capture_identity(b,b.obj.p,out,true,ac8owner::IdentityKind::cdo,why));}
 for(auto flags:{0x20000000u,0x40000000u,0x60000000u}){Fake b;b.put(b.obj.p+8,flags);check(!capture(b,out,true,why)&&!b.mints);}
 {Fake b;b.put(0x20000,uintptr_t{0x10001});check(!capture(b,out,true,why)&&!strcmp(why,"slot_pointer")&&!b.mints);}
 {Fake b;b.slot_ok=false;check(!capture(b,out,true,why)&&!strcmp(why,"slot_lookup"));}
 for(auto addr:{uintptr_t{0x10008},uintptr_t{0x1000c},uintptr_t{0x20010}}){Fake b;b.mem.erase(addr);check(!capture(b,out,true,why)&&!b.mints);}
 {Fake b;check(!ac8owner::capture_identity(b,uintptr_t{0},out,true,ac8owner::IdentityKind::instance,why));}
 {Fake b;ac8owner::RootLease<Id>l;check(l.acquire(b,b.obj)&&l.owned&&b.sets==1);check(l.acquire(b,b.obj)&&b.sets==1);check(l.release(b)&&!b.root&&b.clears==1);check(l.release(b)&&b.clears==1);}
 {Fake b;b.root=true;ac8owner::RootLease<Id>l;check(l.acquire(b,b.obj)&&!l.owned&&!b.sets);check(l.release(b)&&b.root&&!b.clears);}
 {Fake b;ac8owner::RootLease<Id>l;check(l.acquire(b,b.obj));auto changed=b.obj;++changed.serial;check(!l.acquire(b,changed)&&b.sets==1);b.obj=changed;check(!l.release(b)&&!b.clears&&l.owned);}
 {Fake b;ac8owner::RootLease<Id>l;b.alive=false;check(!l.acquire(b,b.obj)&&!l.captured&&!b.sets);}
 {Fake b;ac8owner::RootLease<Id>l;b.set_fails=true;check(!l.acquire(b,b.obj)&&l.captured&&l.owned);check(!l.release(b)&&!b.clears);}
 {Fake b;ac8owner::RootLease<Id>l;check(l.acquire(b,b.obj));b.clear_fails=true;check(!l.release(b)&&l.captured&&l.owned);b.clear_fails=false;check(l.release(b)&&!l.captured);}
 {Fake b;ac8owner::RootLease<Id>l;check(l.acquire(b,b.obj));b.root=false;check(!l.acquire(b,b.obj)&&b.sets==1);check(!l.release(b)&&!b.clears);}
 printf("owner dependency identity / root lease: %u checks passed; fake objects only\n",n);
}
