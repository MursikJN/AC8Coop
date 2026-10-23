#pragma once
#include "owner_world_readiness.h"
#include <array>
// Build 25201480: init 147d4af60 reads GI+908 -> +210 -> +140.
// Children are opaque native pointers, NOT assumed to be UObjects.
namespace ac8owner {
template<class Id>struct SoundObjects { Id gi,manager;uintptr_t registry=0,settings=0,names=0; };
template<class B,class Id>const char* sound_objects_error(const B&b,const SoundObjects<Id>&s){
 if(!b.game_thread())return "owner_sound_wrong_thread";
 if(!b.same_id(s.gi)||!b.same_id(s.manager))return "owner_sound_identity_changed";
 uintptr_t p=0;
 if(!b.read(s.gi.p+0x908,p)||p!=s.manager.p)return "owner_sound_manager_link_changed";
 if(!world_pointer(s.registry)||!b.read(s.manager.p+0x1a8,p)||p!=s.registry)return "owner_sound_registry_missing_or_changed";
 if(!world_pointer(s.settings)||!b.read(s.manager.p+0x210,p)||p!=s.settings)return "owner_sound_settings_missing_or_changed";
 if(!world_pointer(s.names)||!b.read(s.settings+0x140,p)||p!=s.names)return "owner_sound_names_missing_or_changed";
 // Init passes FName addresses +1c8 and +1d0/+1d8 to the stock sound call.
 // Only prove readability here; do not invent required name IDs.
 std::array<uint64_t,3>names{};
 for(unsigned i=0;i<3;++i)if(!b.read(s.names+0x1c8+i*8,names[i]))return "owner_sound_names_unreadable";
 if(!b.same_id(s.gi)||!b.same_id(s.manager))return "owner_sound_identity_changed_during_read";
 if(!b.read(s.manager.p+0x210,p)||p!=s.settings||!b.read(s.settings+0x140,p)||p!=s.names)return "owner_sound_chain_changed_during_read";
 return nullptr;
}
}
