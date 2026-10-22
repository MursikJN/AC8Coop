// Exact-build candidate. All native entry points are existing verified R19/R20
// calls, except the table getter whose RCX/EDX/RAX ABI is recorded in R31.
// It creates one hidden, manually stepped stock actor in the guest world.
// The mesh renderer/camera remain separate; no protagonist possession or AI.
#include "plane_flight_core.h"
#include "owner_initial_seed.h"
#include "owner_spawn_receipt.h"
#include "owner_retirement.h"
#include "owner_world_readiness.h"
namespace owner_native {
using pilot_engine::Id;using pilot_engine::read;using pilot_engine::bytes;
using pilot_engine::same;using pilot_engine::identity;
struct Backend {
 Id world,pc,pawn,klass,cdo,gi,metadata,system,actor_manager,camera_actor;
 Id actor,network,parts;std::vector<Id>children;
 plane_flight::Ledger ledger;
 plane_initial_state::Snapshot initial_state;plane_flight_state::Report model_report;
 ac8owner::InitialSeed seed;
 uint64_t token=0,key=0x434f4f5000000001ULL,local_sequence=0;
 uint32_t revision=0;uint64_t generation=0;
 uint8_t hidden_mask=0;
 uintptr_t sound_manager=0,sound_registry=0;
 ac8owner::WorldObjects<Id>world_objects;bool world_objects_bound=false;
 ac8pilot::Context binding{};bool configured=false,closing=false,seeded=false,cleanup_complete=false,endplay_graph_verified=false;
 const char*detail="owner_native_not_configured";
 std::array<int32_t,8>mods{};int32_t mod_count=0;uint32_t weapon1=0,weapon2=0;
 std::array<double,3>last_position{};uint64_t steps=0;std::array<double,3>velocity{};
 const char*reason()const{return detail;}
 uintptr_t image()const{return pilot_engine::image;}
 bool fail(const char*why){detail=why;event(why);return false;}
 void event(const char*what){
  FILE*f=nullptr;if(!_wfopen_s(&f,(pilot_engine::directory+L"\\guest-owner-native.jsonl").c_str(),L"ab")&&f){
   fprintf(f,"{\"tick\":%llu,\"generation\":%llu,\"revision\":%u,\"event\":\"%s\",\"actor\":\"0x%llx\",\"cleanup\":%s}\n",GetTickCount64(),generation,revision,what,static_cast<unsigned long long>(actor.p),closing?"true":"false");fclose(f);
  }
 }
 bool fingerprint(uintptr_t rva,const char*hex){return pilot_engine::fingerprint(rva,hex);}
 bool game_thread()const{return GetCurrentThreadId()==pilot_engine::thread;}
 bool same_id(const Id&i)const{return same(i);}
 const char* world_objects_reason()const{return world_objects_bound?ac8owner::world_objects_error(*this,world_objects):"owner_world_objects_not_bound";}
 bool require_world_objects(){const auto why=world_objects_reason();return !why||fail(why);}
 bool bind_world_objects(const std::map<std::string,std::string>&r){
  world_objects_bound=false;world_objects={};world_objects.world=world;world_objects.manager=actor_manager;
  auto expected=[&](const char*key,Id&out){uint64_t p=0;auto i=r.find(key);return i!=r.end()&&pilot_engine::number(i->second,p)&&identity(p,out,true);};
  if(!expected("actor_manager_class",world_objects.manager_class)||!expected("combat_zone_class",world_objects.zone_class)||!expected("actor_mapper_class",world_objects.mapper_class))return fail("owner_world_object_classes_unavailable");
  uintptr_t p=0;
  if(!read(actor_manager.p+0x1a0,p)||!p)return fail("owner_world_combat_zone_missing");
  if(!identity(p,world_objects.zone,true))return fail("owner_world_combat_zone_identity_unavailable");
  if(!read(actor_manager.p+0x1b0,p)||!p)return fail("owner_world_actor_mapper_missing");
  if(!identity(p,world_objects.mapper,true))return fail("owner_world_actor_mapper_identity_unavailable");
  if(!read(world_objects.zone.p+0x20,p)||!identity(p,world_objects.level,true))return fail("owner_world_combat_zone_level_unavailable");
  if(!read(world_objects.mapper.p+0x28,world_objects.tree)||!read(world_objects.mapper.p+0x30,world_objects.tree_owner))return fail("owner_world_actor_mapper_index_unreadable");
  world_objects_bound=true;if(!require_world_objects())return false;
  event("owner_world_objects_ready");return true;
 }
 bool context()const {
  uintptr_t p=0;uint8_t active=1,type=0,construction=0,teardown=0;
  return !world_objects_reason()&&GetCurrentThreadId()==pilot_engine::thread&&same(world)&&same(pc)&&same(pawn)&&same(gi)&&same(metadata)&&same(system)&&same(actor_manager)&&
   same(klass)&&same(cdo)&&read(pc.p+0x2d0,p)&&p==pawn.p&&read(world.p+0x1d8,p)&&p==gi.p&&
   read(gi.p+0x878,p)&&p==metadata.p&&read(gi.p+0x910,p)&&p==system.p&&read(system.p+0x1fa,active)&&!active&&
   read(world.p+0x13a,type)&&type==1&&read(world.p+0x13c,construction)&&!(construction&2)&&read(world.p+0x13d,teardown)&&!(teardown&0x20);
 }
 bool absent(){
  // Same bounded sparse-map lookup/hash used by the verified R19 builder.
  if(!context())return false;std::array<uint8_t,0x50>a{},b{};
  if(!bytes(system.p+0x2e0,a.data(),a.size()))return false;
  uintptr_t data=0,external=0;int32_t count=0,free=0,buckets=0;
  memcpy(&data,a.data(),8);memcpy(&count,a.data()+8,4);memcpy(&free,a.data()+0x34,4);memcpy(&external,a.data()+0x40,8);memcpy(&buckets,a.data()+0x48,4);
  if(count<0||count>1000000||free<0||free>count)return false;
  if(count!=free){
   if(buckets<=0||buckets>1048576||(buckets&(buckets-1))||(!external&&buckets>2))return false;
   const auto table=external?external:system.p+0x318;const auto hash=uint32_t(key)+23u*uint32_t(key>>32);int32_t index=0;
   if(!read(table+(hash&uint32_t(buckets-1))*4,index))return false;
   unsigned hops=0;while(index!=-1){uint64_t found=0;if(index<0||index>=count||++hops>128||!read(data+uintptr_t(index)*24,found)||found==key||!read(data+uintptr_t(index)*24+16,index))return false;}
  }
  return bytes(system.p+0x2e0,b.data(),b.size())&&a==b;
 }
 bool own(){
  uintptr_t vt=0,cl=0,level=0,w=0,controller=1;
  return actor.p!=cdo.p&&actor.p!=pawn.p&&context()&&same(actor)&&read(actor.p,vt)&&vt==image()+0xcc01cc8&&read(actor.p+0x10,cl)&&cl==klass.p&&
   read(actor.p+0x20,level)&&read(level+0xc0,w)&&w==world.p&&read(actor.p+0x2c8,controller)&&!controller;
 }
 bool barrier(){uint8_t active=1,tick=1,player=1,ai=1;
  return own()&&read(actor.p+0x3f4,active)&&!active&&read(actor.p+0x33,tick)&&!tick&&read(actor.p+0x2a0,player)&&!player&&read(actor.p+0x2a1,ai)&&!ai;
 }
 bool configure_request(const std::map<std::string,std::string>&r,uint64_t gen,uint32_t rev,const ac8pilot::Context&ctx){
  if(configured||ledger.attempted||ctx.host)return fail("owner_request_already_consumed_or_not_guest");
  if(!fingerprint(0x1aae560,"40574883ec203b1588271b0c7d1e0fb7"))return fail("owner_identity_mint_fingerprint");
  generation=gen;revision=rev;binding=ctx;token=gen;
  auto get=[&](const char*name,Id&out){uint64_t v=0;auto it=r.find(name);return it!=r.end()&&pilot_engine::number(it->second,v)&&identity(v,out,true);};
  if(!get("world",world)||!get("controller",pc)||!get("default_pawn",pawn)||!get("owner_class",klass)||!get("owner_cdo",cdo)||!get("actor_manager",actor_manager)||!get("camera",camera_actor))return fail("owner_request_identity_invalid");
  uint64_t property=0;int32_t offset=0;uint8_t bits[4]{};
  auto prop=r.find("hidden_property");if(prop==r.end()||!pilot_engine::number(prop->second,property)||!read(property+0x44,offset)||offset!=0x58||!bytes(property+0x70,bits,sizeof bits)||bits[0]!=1||bits[1]!=0||!bits[3]||(bits[3]&(bits[3]-1)))return fail("owner_hidden_property_layout_changed");hidden_mask=bits[3];
  uintptr_t p=0,vt=0;if(!read(world.p+0x1d8,p)||!identity(p,gi)||!read(gi.p+0x878,p)||!identity(p,metadata)||!read(gi.p+0x910,p)||!identity(p,system)||
   !read(klass.p+0x110,p)||p!=cdo.p||!read(cdo.p+0x10,p)||p!=klass.p||!read(cdo.p,vt)||vt!=image()+0xcc01cc8)return fail("owner_guest_world_metadata_or_registry_invalid");
  if(!bind_world_objects(r))return false;
  if(!absent())return fail("owner_guest_world_registry_invalid");
  if(!read(gi.p+0x908,sound_manager)||!read(sound_manager+0x1a8,sound_registry)||sound_registry<0x10000)return fail("owner_beginplay_sound_manager_missing");
  // The table lookup is checked BEFORE allocating a plane. No guessed class
  // lookup ABI: class/asset/PlaneTypeID are checked by the Lua caller as well.
  if(!fingerprint(0x73610b0,"40534881ec30020000488b0540bb8c06"))return fail("owner_table_getter_fingerprint");
  using Table=uintptr_t(__fastcall*)(uintptr_t,int32_t);
  event("owner_table_lookup_enter");
  const auto table=reinterpret_cast<Table>(image()+0x73610b0)(metadata.p,23010);
  event("owner_table_lookup_return");
  int32_t rows=0;uintptr_t data=0;if(!read(table+0x20,rows)||rows<1||rows>4096||!read(table+0x18,data)||data<0x10000)return fail("owner_f14_flight_table_unavailable");
  auto number=[&](const std::string&k,uint64_t&v){auto it=r.find(k);return it!=r.end()&&pilot_engine::number(it->second,v);};
  uint64_t n=0;if(!number("mod_count",n)||n>8)return fail("owner_mod_count_invalid");mod_count=int32_t(n);
  for(int32_t i=0;i<mod_count;++i){if(!number("mod"+std::to_string(i),n)||!n||n>65535)return fail("owner_mod_invalid");mods[size_t(i)]=int32_t(n);for(int32_t j=0;j<i;++j)if(mods[size_t(j)]==mods[size_t(i)])return fail("owner_duplicate_mod");}
  if(!number("weapon1",n)||n>255)return fail("owner_weapon_invalid");weapon1=uint32_t(n);
  if(!number("weapon2",n)||n>255)return fail("owner_weapon_invalid");weapon2=uint32_t(n);
  // Lobby zero currently means stock/default, not a verified native weapon ID.
  if(!weapon1&&!weapon2){weapon1=16;weapon2=11;}
  if(mod_count||weapon1!=16||weapon2!=11)return fail("owner_non_stock_loadout_catalog_unverified");
  const std::pair<uintptr_t,const char*> anchors[]={
   {0x465a120,"40555356574154415541564157488dac"},{0x4263b80,"4889542410534883ec20488b4110488b"},
   {0x7d4ad20,"4c8bdc5541554156498d6bb84881ec30"},{0x7d6ed30,"40574881ecc0000000488b05c0deeb05"},
   {0x3fdc360,"4055565741544157488dac2490fcffff"},{0x3fe0160,"48895c24084889742410574883ec20f6"},
   {0x4d344f0,"48895c2408574883ec20488db9c00900"},{0x74d8c00,"488bc448895808488970104889781855"},
   {0x4d32580,"4883ec38f64218010f57c9f30f1005fd"},{0x4d326e0,"488bc448895808488970104889781855"},
   {0x4d318a0,"40534881ec80000000f30f100d777957"},{0x3fdebc0,"4881ec78010000488b89a00100004885"},
   {0x41df200,"f6413a027426488bc10f1f8000000000"},{0x42dfa90,"48895c2408574883ec20f6413a020fb6"},
   {0x7d2c180,"8891d3000000c3cccccccccccccccccc"}};
  for(auto a:anchors)if(!fingerprint(a.first,a.second))return fail("owner_native_entry_fingerprint");
  ledger.lifetime_ms=0;configured=true;detail="owner_world_preflight_wait_initial_state";event(detail);return true;
 }
 bool read_seed(const ac8pilot::Frame&host){
  std::map<std::string,std::string>r;uint64_t n=0;
  if(!pilot_engine::file(L"guest-owner-seed.tsv",r)||!pilot_engine::number(r["generation"],n)||n!=generation||!pilot_engine::number(r["revision"],n)||n!=revision||
   !pilot_engine::number(r["host_sequence"],n)||n!=host.sequence)return fail("owner_seed_context_changed");
  auto scalar=[&](const std::string&name,double&v){const auto&s=r[name];char*end=nullptr;errno=0;v=strtod(s.c_str(),&end);return !s.empty()&&!errno&&end==s.c_str()+s.size()&&std::isfinite(v);};
  for(unsigned i=0;i<3;++i){double d=0;if(!scalar("position"+std::to_string(i),seed.position[i])||seed.position[i]!=host.poses[1].position[i]||
   !scalar("angle"+std::to_string(i),seed.degrees[i])||!scalar("forward"+std::to_string(i),d))return fail("owner_seed_invalid");seed.forward[i]=float(d);}
  seed.speed=host.poses[1].speed;return true;
 }
 plane_flight::Seen resolve(const plane_flight::Identity&i){Id id{i.pointer,i.index,i.serial};if(same(id))return plane_flight::Seen::safe;return pilot_engine::retired(id)?plane_flight::Seen::retired:plane_flight::Seen::unknown;}
 bool acquire(uintptr_t p,plane_flight::Identity&out,int kind){Id id;uintptr_t vt=0,outer=0;
  if(!identity(p,id,true)||!read(p,vt))return false;
  if(kind==0){actor=id;if(!own())return false;}
  else{if(!read(p+0x20,outer)||outer!=actor.p)return false;if(kind==1){if(vt!=image()+0xc88a868)return false;network=id;}else parts=id;}
  out={p,id.index,id.serial};return true;
 }
 bool initial_barrier(uintptr_t p){if(p!=actor.p||!own())return false;
  uint8_t start=0,allow=0,hidden=0;if(!read(p+0x32,start)||!read(p+0x5a,allow)||!read(p+0x58,hidden)||!hidden_mask)return false;
  *reinterpret_cast<uint8_t*>(p+0x58)=uint8_t(hidden|hidden_mask);
  *reinterpret_cast<uint8_t*>(p+0x3f4)=0;*reinterpret_cast<uint8_t*>(p+0x32)=uint8_t(start&~4u);*reinterpret_cast<uint8_t*>(p+0x33)=0;
  *reinterpret_cast<uint8_t*>(p+0x5a)=uint8_t(allow&~1u);*reinterpret_cast<uint8_t*>(p+0x2a0)=0;*reinterpret_cast<uint8_t*>(p+0x2a1)=0;return barrier();
 }
 void close_actor_barrier(){if(own()){uint8_t hidden=0;if(read(actor.p+0x58,hidden))*reinterpret_cast<uint8_t*>(actor.p+0x58)=uint8_t(hidden|hidden_mask);*reinterpret_cast<uint8_t*>(actor.p+0x3f4)=0;*reinterpret_cast<uint8_t*>(actor.p+0x33)=0;}}
 uintptr_t spawn(plane_flight::Ledger&receipt){
  if(!require_world_objects())return 0;
  alignas(16) double transform[12]={0,0,0,1,seed.position[0],seed.position[1],seed.position[2],0,1,1,1,0};
  alignas(16) uint8_t params[0x80]{};params[0x30]=1;params[0x31]=1;params[0x32]=4;uint32_t flags=8;memcpy(params+0x34,&flags,4);
  using Callback=ac8owner::SpawnReceipt<Backend,plane_flight::Ledger>;
  uintptr_t table[3]={0,reinterpret_cast<uintptr_t>(&Callback::address),0};Callback::Context ctx{this,&receipt};Callback::Storage c{table,&ctx};
  uintptr_t fn=reinterpret_cast<uintptr_t>(&Callback::invoke),capture=reinterpret_cast<uintptr_t>(&c);
  memcpy(params+0x40,&fn,8);memcpy(params+0x50,&capture,8);
  using Spawn=uintptr_t(__fastcall*)(uintptr_t,uintptr_t,const void*,const void*);return reinterpret_cast<Spawn>(image()+0x465a120)(world.p,klass.p,transform,params);
 }
 bool configure(){
  if(!barrier()||!absent())return false;uintptr_t existing=1;
  if(!read(actor.p+0x1328,existing)||existing||!read(actor.p+0xed0,existing)||existing)return false;
  *reinterpret_cast<int32_t*>(actor.p+0xf98)=23010;
  struct Ints{const int32_t*data;int32_t count,cap;};Ints selected{mods.data(),mod_count,mod_count},empty{};
  ledger.parts_entered=ledger.unknown_parts=true;
  event("owner_parts_create_enter");
  using Parts=void(__fastcall*)(uintptr_t,const void*,const void*);reinterpret_cast<Parts>(image()+0x7d4ad20)(actor.p,&selected,&empty);
  event("owner_parts_create_return");
  if(!read(actor.p+0x1328,ledger.raw_parts)||!acquire(ledger.raw_parts,ledger.parts,2))return false;ledger.parts_identified=true;ledger.unknown_parts=false;
  ledger.network_entered=ledger.unknown_network=true;
  event("owner_network_create_enter");
  using Network=void(__fastcall*)(uintptr_t);reinterpret_cast<Network>(image()+0x7d6ed30)(actor.p);
  event("owner_network_create_return");
  if(!read(actor.p+0xed0,ledger.raw_network)||!acquire(ledger.raw_network,ledger.network,1))return false;ledger.network_identified=true;ledger.unknown_network=false;
  *reinterpret_cast<uint8_t*>(actor.p+0xfa0)=uint8_t(weapon1);*reinterpret_cast<uint8_t*>(actor.p+0xfa1)=uint8_t(weapon2);
  *reinterpret_cast<int32_t*>(actor.p+0xf9c)=0;*reinterpret_cast<int32_t*>(actor.p+0x3ab8)=0;
  // Stock inactive System uses local role 1 (71ca650). Role 3 would require
  // native room initialization; custom Steam transport does not enable it.
  *reinterpret_cast<uint8_t*>(actor.p+0xed8)=1;*reinterpret_cast<uint64_t*>(network.p+0x28)=key;
  return barrier()&&absent();
 }
 plane_initial_state::OwnedCaches caches(){plane_initial_state::OwnedCaches out;out.plane=actor.p;out.network=network.p;unsigned offsets[]={0x98,0x140,0x150,0x160,0x170};for(unsigned i=0;i<5;++i)if(!read(network.p+offsets[i],out.data[i]))return{};return out;}
 bool guard(uint64_t t,uintptr_t source,uintptr_t owned,uintptr_t net){return !closing&&t==token&&source==actor.p&&owned==actor.p&&net==network.p&&barrier()&&same(network)&&same(parts)&&absent();}
 template<class T>bool read(uintptr_t p,T&v)const{return owner_native::read(p,v);}
 bool read(uintptr_t p,void*out,size_t n){return bytes(p,out,n);}
 bool write(uintptr_t p,const void*v,size_t n){if(!n||n>8||!guard(token,actor.p,actor.p,network.p))return false;uint8_t old[8]{};if(!bytes(p,old,n))return false;memcpy(reinterpret_cast<void*>(p),v,n);return true;}
 bool qpc(uint64_t&v){LARGE_INTEGER q{};if(!QueryPerformanceCounter(&q))return false;v=uint64_t(q.QuadPart);return true;}
 bool preseed(){
  // Layout proof only. Offline local role 1 does not run remote role 2's bootstrap.
  plane_initial_state::Snapshot layout;layout.source=actor.p;layout.image=image();layout.token=token;layout.scale=100;layout.complete=true;
  return plane_initial_state::verify_self_owned(*this,layout,caches());
 }
 bool initialize_self(){const char*why=nullptr;plane_initial_state::Result r;
  if(!plane_initial_state::capture(*this,actor.p,image(),token,initial_state,why))return fail(why?why:"owner_self_capture_failed");
  if(!ac8owner::seed_self(initial_state,seed))return fail("owner_initial_pose_invalid");
  return plane_initial_state::stage_self(*this,initial_state,caches(),r)||fail(r.error);
 }
 bool ready_to_finish(){return require_world_objects()&&barrier()&&absent();}
 void finish(){alignas(16)double transform[12]={0,0,0,1,seed.position[0],seed.position[1],seed.position[2],0,1,1,1,0};
  using Finish=void(__fastcall*)(uintptr_t,const void*,bool,void*,uint8_t);reinterpret_cast<Finish>(image()+0x3fdc360)(actor.p,transform,false,nullptr,1);
 }
 bool components(bool disable){
  if(!barrier())return false;const auto set=actor.p+0x218;std::array<uint8_t,0x38>a{},b{};
  uintptr_t data=0,external=0;int32_t count=0,cap=0,bits=0,maxbits=0,free=0;
  if(!bytes(set,a.data(),a.size()))return false;
  memcpy(&data,a.data(),8);memcpy(&count,a.data()+8,4);memcpy(&cap,a.data()+12,4);memcpy(&external,a.data()+0x20,8);memcpy(&bits,a.data()+0x28,4);memcpy(&maxbits,a.data()+0x2c,4);memcpy(&free,a.data()+0x34,4);
  if(count<1||count>512||bits!=count||cap<count||cap>4096||free<0||free>count||maxbits<bits||maxbits>4096||(!external&&bits>128))return false;
  unsigned allocated=0;for(int i=0;i<bits;++i){uint32_t mask=0;if(!owner_native::read((external?external:set+0x10)+uintptr_t(i/32)*4,mask))return false;if(!(mask&(1u<<(i%32))))continue;++allocated;
   uintptr_t p=0,owner=0,vt=0,setter=0,getter=0;Id id;
   if(!owner_native::read(data+uintptr_t(i)*16,p)||!identity(p,id,true)||!owner_native::read(p+0x90,owner)||owner!=actor.p||!owner_native::read(p,vt)||!owner_native::read(vt+0x3d8,setter)||!owner_native::read(vt+0x3e8,getter)||setter<image()||getter<image())return false;
   auto kind=plane_component_ticks::classify({setter-image(),getter-image()});if(kind==plane_component_ticks::Kind::unknown)return false;
   if(disable){using Set=void(__fastcall*)(uintptr_t,bool);reinterpret_cast<Set>(setter)(p,false);if(kind==plane_component_ticks::Kind::live)reinterpret_cast<Set>(image()+0x41df200)(p,false);}
   uint8_t tick=1,custom=1,flags=0;uintptr_t registration=0;
   if(!same(id)||!owner_native::read(p+0x3b,tick)||tick)return false;
   if(kind==plane_component_ticks::Kind::live&&(!owner_native::read(p+0xd3,custom)||custom))return false;
   if(kind==plane_component_ticks::Kind::mesh&&(!owner_native::read(p+0xbd0,registration)||(registration&&(!owner_native::read(registration,flags)||(flags&1)))))return false;
  }
  return allocated==unsigned(count-free)&&bytes(set,b.data(),b.size())&&a==b;
 }
 bool disable_components(){return components(true);}void quarantine_components(){components(true);}
 bool finished_graph(){
  uintptr_t p=0,table=0,rows=0;uint64_t network_key=0;int32_t count=0,row=0,type=0;uint8_t begun=0,plane_role=0,init_flags=0;
  if(!barrier()||!same(network)||!same(parts)||!absent()||!owner_native::read(actor.p+0x5d,begun)||(begun&12)!=8||!owner_native::read(actor.p+0xed8,plane_role)||plane_role!=1||
   !owner_native::read(actor.p+0xed0,p)||p!=network.p||!owner_native::read(network.p+0x20,p)||p!=actor.p||!owner_native::read(network.p+0x28,network_key)||network_key!=key||
   !owner_native::read(actor.p+0x1328,p)||p!=parts.p||!owner_native::read(parts.p+0x20,p)||p!=actor.p||!owner_native::read(actor.p+0xf98,type)||type!=23010||
   !owner_native::read(actor.p+0x5c,init_flags)||!(init_flags&2)||!owner_native::read(actor.p+0x3ab0,table)||!owner_native::read(table+0x18,rows)||rows<0x10000||!owner_native::read(table+0x20,count)||count<1||count>4096||!owner_native::read(actor.p+0x3ab8,row)||row!=0)return false;
  return components(false);
 }
 bool reset_model(uintptr_t m){if(m!=actor.p+0x3c60||!guard(token,actor.p,actor.p,network.p))return false;using Fn=void(__fastcall*)(uintptr_t);reinterpret_cast<Fn>(image()+0x4d344f0)(m);return true;}
 bool consume(uintptr_t n,uintptr_t m){if(n!=network.p||(m!=actor.p+0x2268&&m!=actor.p+0x3c60)||!guard(token,actor.p,actor.p,network.p))return false;using Fn=void(__fastcall*)(uintptr_t,uintptr_t);reinterpret_cast<Fn>(image()+0x74d8c00)(n,m);return true;}
 bool input(uintptr_t m,uintptr_t p){auto c=caches();if(p!=c.data[4]+8||!guard(token,actor.p,actor.p,network.p))return false;using Fn=void(__fastcall*)(uintptr_t,uintptr_t);reinterpret_cast<Fn>(image()+0x4d32580)(m,p);return true;}
 bool prepare(const ac8sortie::Key&k){
  if(!require_world_objects())return false;
  if(!configured||closing||k.generation!=generation||k.revision!=revision||!absent())return fail("owner_prepare_context_changed");
  if(!ledger.prepare(*this)){if(!require_world_objects())return false;return fail(ledger.reason);}
  auto child=[&](uintptr_t p,uintptr_t outer){Id id;uintptr_t actual=0;
   if(!identity(p,id,true)||!owner_native::read(p+0x20,actual)||actual!=outer||p==actor.p||p==network.p||p==parts.p)return false;
   for(const auto&i:children)if(i.p==p)return false;children.push_back(id);return true;
  };
  const unsigned owned_children[]={0x16a8,0x1ae8,0x18d8};
  for(auto off:owned_children){uintptr_t p=0;if(!owner_native::read(actor.p+off,p)||!child(p,actor.p))return fail("owner_initialized_child_identity_missing");}
  uintptr_t weapon=0,nested=0,extra=0,link=0;uint8_t activator_initialized=0;
  if(!owner_native::read(children[0].p+0x2e0,weapon)||!child(weapon,actor.p))return fail("owner_weapon_identity_missing");
  if(!owner_native::read(weapon+0xa8,nested)||!child(nested,actor.p))return fail("owner_weapon_child_identity_missing");
  if(!owner_native::read(children[0].p+0x2e8,extra)||!child(extra,children[0].p))return fail("owner_extra_identity_missing");
  if(!owner_native::read(children[0].p+0x579,activator_initialized)||activator_initialized!=1||!owner_native::read(children[0].p+0x2d0,link)||link!=actor.p||!owner_native::read(children[0].p+0x2d8,link)||link!=children[1].p)return fail("owner_endplay_links_unverified");
  endplay_graph_verified=true;
  if(!initialize_self())return false;
  if(!plane_flight_state::finalize_self(*this,initial_state,caches(),model_report))return fail(model_report.error);
  seeded=true;detail="owner_stock_f14_self_initialized_manual_steps_ready";event(detail);return valid();
 }
 bool valid(){if(!require_world_objects()||!seeded||closing||!finished_graph()||!endplay_graph_verified)return false;for(const auto&i:children)if(!same(i))return false;return true;}
 bool step(const ac8input::Frame&f,unsigned count){
  std::array<float,6>axes{};if(!count||count>6||!valid()||!ac8player::controls(f,axes))return false;
  struct Controls{std::array<float,6>axes;uint8_t flags=0,pad[7]{};} controls{axes};
  for(unsigned i=0;i<count;++i){if(!valid())return false;const auto m=actor.p+0x2268;
   if(!steps)event("owner_first_local_step_enter");
   using Input=void(__fastcall*)(uintptr_t,const void*);reinterpret_cast<Input>(image()+0x4d32580)(m,&controls);
   using Step=void(__fastcall*)(uintptr_t,float);reinterpret_cast<Step>(image()+0x4d326e0)(m,1.f/60.f);++steps;
   if(steps==1)event("owner_first_local_step_return");
  }
  return true;
 }
 bool snapshot_pose(ac8pilot::Pose&out,std::array<double,3>&v){
  if(!valid())return false;const auto m=actor.p+0x2268;std::array<double,3>p{},angles{};std::array<float,4>q{};float speed=0;
  if(!bytes(m+0x8e0,p.data(),24)||!bytes(m+0x8d0,q.data(),16)||!owner_native::read(m+0xb0,speed)||!ac8player::finite({p,q}))return false;
  using Angles=double*(__fastcall*)(const float*,double*);reinterpret_cast<Angles>(image()+0x4d318a0)(q.data(),angles.data());
  constexpr double degrees=57.29577951308232;double at[]={p[2]*100,-p[0]*100,p[1]*100},rot[]={-angles[0]*degrees,-angles[1]*degrees,angles[2]*degrees};
  using Move=bool(__fastcall*)(uintptr_t,const double*,const double*,bool,void*,uint8_t);
  if(!reinterpret_cast<Move>(image()+0x3fdebc0)(actor.p,at,rot,false,nullptr,0))return false;
  uintptr_t root=0;std::array<double,4>r{};if(!owner_native::read(actor.p+0x1a0,root)||!bytes(root+0x200,r.data(),32)||!bytes(root+0x220,out.position.data(),24))return false;
  out.role=1;out.aircraft=23;out.speed=speed;for(unsigned i=0;i<4;++i)out.rotation[i]=float(r[i]);
  // Model direction is already normalized by stock simulation; convert axes.
  std::array<double,3>d{};if(!bytes(m+0x1f8,d.data(),24))return false;v={d[2]*speed*100,-d[0]*speed*100,d[1]*speed*100};return valid();
 }
 bool camera_pose(const ac8pilot::Pose&p){
  if(!same(camera_actor)||local_sequence==UINT64_MAX)return false;
  ac8pilot::Frame f;f.kind=ac8pilot::Kind::owner_state;f.sender=binding.local;f.session=binding.nonce;f.echo=binding.remote;f.sequence=++local_sequence;
  f.generation=generation;f.revision=revision;f.source_us=GetTickCount64()*1000;f.count=1;f.poses[0]=p;f.velocity=velocity;
  if(!ac8pilot::valid(f))return false;const auto b=ac8pilot::encode(f);const auto path=pilot_engine::directory+L"\\guest-owner-local.ac8p",temp=path+L".tmp";
  FILE*file=nullptr;if(_wfopen_s(&file,temp.c_str(),L"wb")||!file)return false;const bool wrote=fwrite(b.data(),1,b.size(),file)==b.size();fclose(file);return wrote&&MoveFileExW(temp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING)!=0;
 }
 // LocalPilot interface names; keep the captured Snapshot distinct.
 bool snapshot(ac8pilot::Pose&p,std::array<double,3>&v){if(!snapshot_pose(p,v))return false;velocity=v;return true;}
 bool camera(const ac8pilot::Pose&p){return camera_pose(p);}
 bool pending(){uint8_t actor_state=0;return owner_native::read(actor.p+0x5d,actor_state)&&(actor_state&1);}
 bool cleanup_guard(bool finished){if(!own()||!absent())return false;
  uint64_t actual=0;if(network.p&&(!same(network)||!owner_native::read(network.p+0x28,actual)||actual!=key))return false;
  if(!finished)return true;if(!endplay_graph_verified||!same(network)||!same(parts))return false;for(const auto&i:children)if(!same(i))return false;return true;
 }
 bool destroy(uintptr_t p){using Destroy=bool(__fastcall*)(uintptr_t,bool);return reinterpret_cast<Destroy>(image()+0x3fe0160)(p,false);}
 bool release(){
  closing=true;seeded=false;
  if(!ledger.attempted){cleanup_complete=!configured||pilot_engine::retired(camera_actor);return cleanup_complete;}
  ledger.cleanup(*this);
  if(!ledger.plane_retired)return false;
  for(const auto&i:children)if(!pilot_engine::retired(i))return false;
  // Camera belongs to the Lua adapter; never destroy it behind its back.
  if(!pilot_engine::retired(camera_actor))return false;
  cleanup_complete=ac8owner::retirement_complete(ledger,true,true);return cleanup_complete;
 }
};
}
