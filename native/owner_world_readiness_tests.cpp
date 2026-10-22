#include "owner_world_readiness.h"
#include <map>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <vector>
struct TestId{uintptr_t p=0;int32_t index=-1,serial=0;};
using Objects=ac8owner::WorldObjects<TestId>;
struct WorldFake{
 std::map<uintptr_t,uint8_t>memory;std::map<uintptr_t,TestId>ids;
 bool thread=true;mutable unsigned identity_reads=0;unsigned retire_at=0;
 unsigned allocations=0,finishes=0;Objects objects;
 WorldFake(){
  TestId*all[]={&objects.world,&objects.manager,&objects.zone,&objects.level,&objects.mapper,&objects.manager_class,&objects.zone_class,&objects.mapper_class};
  for(unsigned i=0;i<8;++i){*all[i]={uintptr_t(0x10000+i*0x1000),int32_t(i),int32_t(100+i)};ids.emplace(all[i]->p,*all[i]);}
  set(objects.manager.p+0x10,objects.manager_class.p);set(objects.zone.p+0x10,objects.zone_class.p);set(objects.mapper.p+0x10,objects.mapper_class.p);
  set(objects.manager.p+0x20,objects.world.p);set(objects.manager.p+0x1a0,objects.zone.p);set(objects.manager.p+0x1b0,objects.mapper.p);
  set(objects.zone.p+0x20,objects.level.p);set(objects.level.p+0xc0,objects.world.p);set(objects.mapper.p+0x20,objects.manager.p);
  objects.tree=0x30000;objects.tree_owner=0x31000;
  set(objects.mapper.p+0x28,objects.tree);set(objects.mapper.p+0x30,objects.tree_owner);set(objects.mapper.p+0x58,uint8_t{1});
 }
 template<class T>void set(uintptr_t p,T value){uint8_t raw[sizeof(T)]{};std::memcpy(raw,&value,sizeof value);for(unsigned i=0;i<sizeof(T);++i)memory[p+i]=raw[i];}
 template<class T>bool read(uintptr_t p,T&out)const{uint8_t raw[sizeof(T)]{};for(unsigned i=0;i<sizeof(T);++i){auto it=memory.find(p+i);if(it==memory.end())return false;raw[i]=it->second;}std::memcpy(&out,raw,sizeof out);return true;}
 bool same_id(const TestId&i)const{++identity_reads;if(retire_at&&identity_reads>=retire_at)return false;auto it=ids.find(i.p);return it!=ids.end()&&i.serial>0&&it->second.index==i.index&&it->second.serial==i.serial;}
 bool game_thread()const{return thread;}
 bool allocate(){if(ac8owner::world_objects_error(*this,objects))return false;++allocations;return true;}
 bool finish(){if(ac8owner::world_objects_error(*this,objects))return false;++finishes;return true;}
};
int main(){unsigned checks=0;auto check=[&](bool ok){++checks;if(!ok){std::printf("FAIL world readiness %u\n",checks);std::abort();}};
 {WorldFake f;const auto before=f.memory;check(!ac8owner::world_objects_error(f,f.objects)&&f.memory==before);check(f.allocate()&&f.finish()&&f.allocations==1&&f.finishes==1);}
 using Break=std::function<void(WorldFake&)>;
 const std::vector<std::pair<Break,const char*>> faults={
  {[](WorldFake&f){f.thread=false;},"owner_world_objects_wrong_thread"},
  {[](WorldFake&f){++f.ids[f.objects.world.p].serial;},"owner_world_identity_changed"},
  {[](WorldFake&f){++f.ids[f.objects.manager.p].serial;},"owner_world_actor_manager_identity_changed"},
  {[](WorldFake&f){++f.ids[f.objects.zone.p].serial;},"owner_world_combat_zone_identity_changed"},
  {[](WorldFake&f){++f.ids[f.objects.level.p].serial;},"owner_world_combat_zone_level_identity_changed"},
  {[](WorldFake&f){++f.ids[f.objects.mapper.p].serial;},"owner_world_actor_mapper_identity_changed"},
  {[](WorldFake&f){f.ids.erase(f.objects.zone_class.p);},"owner_world_object_class_identity_changed"},
  {[](WorldFake&f){f.set(f.objects.manager.p+0x10,f.objects.mapper_class.p);},"owner_world_actor_manager_class_mismatch"},
  {[](WorldFake&f){f.set(f.objects.zone.p+0x10,f.objects.mapper_class.p);},"owner_world_combat_zone_class_mismatch"},
  {[](WorldFake&f){f.set(f.objects.mapper.p+0x10,f.objects.zone_class.p);},"owner_world_actor_mapper_class_mismatch"},
  {[](WorldFake&f){f.set(f.objects.manager.p+0x20,uintptr_t{0xdeadbeef});},"owner_world_actor_manager_outer_mismatch"},
  {[](WorldFake&f){f.set(f.objects.manager.p+0x1a0,uintptr_t{0});},"owner_world_combat_zone_link_changed"},
  {[](WorldFake&f){f.set(f.objects.manager.p+0x1b0,uintptr_t{0});},"owner_world_actor_mapper_link_changed"},
  {[](WorldFake&f){f.set(f.objects.zone.p+0x20,uintptr_t{0xdeadbeef});},"owner_world_combat_zone_world_mismatch"},
  {[](WorldFake&f){f.set(f.objects.level.p+0xc0,uintptr_t{0xdeadbeef});},"owner_world_combat_zone_world_mismatch"},
  {[](WorldFake&f){f.set(f.objects.mapper.p+0x20,f.objects.world.p);},"owner_world_actor_mapper_outer_mismatch"},
  {[](WorldFake&f){f.set(f.objects.mapper.p+0x58,uint8_t{0});},"owner_world_actor_mapper_not_initialized_or_changed"},
  {[](WorldFake&f){f.set(f.objects.mapper.p+0x28,uintptr_t{0});},"owner_world_actor_mapper_not_initialized_or_changed"},
  {[](WorldFake&f){f.set(f.objects.mapper.p+0x30,uintptr_t{0});},"owner_world_actor_mapper_not_initialized_or_changed"},
  {[](WorldFake&f){f.objects.tree=1;},"owner_world_actor_mapper_not_initialized_or_changed"},
  {[](WorldFake&f){f.objects.tree_owner=0x800000000000ULL;},"owner_world_actor_mapper_not_initialized_or_changed"},
  {[](WorldFake&f){f.memory.erase(f.objects.manager.p+0x1b0);},"owner_world_actor_mapper_link_changed"},
  {[](WorldFake&f){f.retire_at=9;},"owner_world_objects_identity_changed_during_read"}
 };
 for(const auto&fault:faults){WorldFake f;fault.first(f);const auto before=f.memory;const auto reason=ac8owner::world_objects_error(f,f.objects);
  check(reason&&std::strcmp(reason,fault.second)==0);check(!f.allocate()&&!f.finishes&&!f.allocations&&f.memory==before);
 }
 {WorldFake f;check(f.allocate());f.set(f.objects.manager.p+0x1b0,uintptr_t{0xdeadbeef});check(!f.finish()&&f.allocations==1&&f.finishes==0);}
 {WorldFake f;f.ids[f.objects.mapper.p].index+=1;check(!f.allocate()&&!f.allocations);}
 std::printf("owner world readiness: %u checks passed; fake memory only, no native calls\n",checks);return 0;
}
