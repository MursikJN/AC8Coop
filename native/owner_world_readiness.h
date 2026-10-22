#pragma once
#include <cstdint>
#include <initializer_list>
// Build 25201480 only. GW-02 / RG-02 evidence in MODLOG and offline reports.
// This gate only reads; identity acquisition is owned by the caller.
namespace ac8owner {
template<class Id>struct WorldObjects {
 Id world,manager,zone,level,mapper,manager_class,zone_class,mapper_class;
 uintptr_t tree=0,tree_owner=0;
};
inline bool world_pointer(uintptr_t p){return p>=0x10000&&p<0x800000000000ULL;}
template<class B,class Id>const char* world_objects_error(const B&b,const WorldObjects<Id>&s){
 if(!b.game_thread())return "owner_world_objects_wrong_thread";
 if(!b.same_id(s.world))return "owner_world_identity_changed";
 if(!b.same_id(s.manager))return "owner_world_actor_manager_identity_changed";
 if(!b.same_id(s.zone))return "owner_world_combat_zone_identity_changed";
 if(!b.same_id(s.level))return "owner_world_combat_zone_level_identity_changed";
 if(!b.same_id(s.mapper))return "owner_world_actor_mapper_identity_changed";
 if(!b.same_id(s.manager_class)||!b.same_id(s.zone_class)||!b.same_id(s.mapper_class))return "owner_world_object_class_identity_changed";
 uintptr_t p=0;
 if(!b.read(s.manager.p+0x10,p)||p!=s.manager_class.p)return "owner_world_actor_manager_class_mismatch";
 if(!b.read(s.zone.p+0x10,p)||p!=s.zone_class.p)return "owner_world_combat_zone_class_mismatch";
 if(!b.read(s.mapper.p+0x10,p)||p!=s.mapper_class.p)return "owner_world_actor_mapper_class_mismatch";
 if(!b.read(s.manager.p+0x20,p)||p!=s.world.p)return "owner_world_actor_manager_outer_mismatch";
 if(!b.read(s.manager.p+0x1a0,p)||p!=s.zone.p)return "owner_world_combat_zone_link_changed";
 if(!b.read(s.manager.p+0x1b0,p)||p!=s.mapper.p)return "owner_world_actor_mapper_link_changed";
 if(!b.read(s.zone.p+0x20,p)||p!=s.level.p||!b.read(s.level.p+0xc0,p)||p!=s.world.p)return "owner_world_combat_zone_world_mismatch";
 if(!b.read(s.mapper.p+0x20,p)||p!=s.manager.p)return "owner_world_actor_mapper_outer_mismatch";
 // 147d30f90 allocates the spatial index, publishes +28/+30, and sets +58.
 // These are not UObject pointers or a saved pointer back to CombatZone.
 uint8_t mapper_initialized=0;
 if(!world_pointer(s.tree)||!world_pointer(s.tree_owner)||!b.read(s.mapper.p+0x58,mapper_initialized)||mapper_initialized!=1||
    !b.read(s.mapper.p+0x28,p)||p!=s.tree||!b.read(s.mapper.p+0x30,p)||p!=s.tree_owner)return "owner_world_actor_mapper_not_initialized_or_changed";
 // Reject retirement/reuse that occurred during the bounded set of reads.
 for(const auto&i:{s.world,s.manager,s.zone,s.level,s.mapper,s.manager_class,s.zone_class,s.mapper_class})
  if(!b.same_id(i))return "owner_world_objects_identity_changed_during_read";
 return nullptr;
}
}
