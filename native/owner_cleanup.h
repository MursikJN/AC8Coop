#pragma once
#include "plane_flight_core.h"
namespace ac8owner {
// Slot/serial first: a freed/reused address must never be dereferenced.
// RF_Garbage is a pending receipt, not proof that the slot was retired.
template<class B,class I> plane_flight::Seen cleanup_identity(B&b,const I&i,bool accepted){
 uintptr_t at=0,p=0;int32_t serial=0;
 if(!i.p||i.serial<=0||!b.slot(i.index,at)||!b.read(at,p)||!b.read(at+16,serial))return plane_flight::Seen::unknown;
 if(p!=i.p||serial!=i.serial)return plane_flight::Seen::retired;
 if(accepted){uint32_t flags=0;uint8_t lifecycle=0;
  if(!b.read(i.p+8,flags)||!b.read(i.p+0x5d,lifecycle))return plane_flight::Seen::unknown;
  if((flags&0x40000000u)||(lifecycle&1))return plane_flight::Seen::pending;
 }
 return b.same_id(i)?plane_flight::Seen::safe:plane_flight::Seen::unknown;
}
// The setter must move the tick between the engine's lists. A raw state-byte
// write makes unregister choose the wrong list (offline dump L31-14).
template<class B> bool disable_actor_tick(B&b){
 if(!b.tick_guard())return false;
 b.native_disable_tick();
 return b.tick_disabled();
}
inline bool collection_safe(const plane_flight::Ledger&l,bool closing,bool detached){
 if(!closing||l.quarantined||l.unknown_spawn||l.unknown_network||l.unknown_parts)return false;
 return !l.attempted||(l.identified&&detached&&l.destroy_accepted);
}
}
