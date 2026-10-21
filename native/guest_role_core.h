#pragma once
#include "guest_control_core.h"
#include <array>
#include <cstdint>
// Mission-role ledger, independent of LiveUnit's AI-only containers. This file
// never changes engine memory. The engine bridge must supply fresh readbacks;
// preparation is deliberately insufficient to authorize input or activation.
namespace ac8role {
struct Object {
 uintptr_t pointer=0;int32_t index=-1,serial=0;
 bool valid()const{return pointer>=0x10000&&index>=0&&serial>0;}
};
inline bool same(const Object&a,const Object&b){return a.pointer==b.pointer&&a.index==b.index&&a.serial==b.serial;}
struct Context {
 Object world,controller,host,npc,unit,player;
 std::array<Object,2> other_wingmen;
 uint64_t generation=0,peer=0,remote_nonce=0,local_nonce=0;
 uint32_t revision=0,slot=1,aircraft=23;
};
inline bool distinct(const Context&c){
 const Object objects[]={c.world,c.controller,c.host,c.npc,c.unit,c.player,c.other_wingmen[0],c.other_wingmen[1]};
 for(unsigned i=0;i<8;++i){if(!objects[i].valid())return false;for(unsigned j=0;j<i;++j)if(objects[i].pointer==objects[j].pointer||objects[i].index==objects[j].index)return false;}
 return true;
}
inline bool same(const Context&a,const Context&b){
 return same(a.world,b.world)&&same(a.controller,b.controller)&&same(a.host,b.host)&&same(a.npc,b.npc)&&same(a.unit,b.unit)&&same(a.player,b.player)&&
  same(a.other_wingmen[0],b.other_wingmen[0])&&same(a.other_wingmen[1],b.other_wingmen[1])&&a.generation==b.generation&&a.revision==b.revision&&
  a.peer==b.peer&&a.remote_nonce==b.remote_nonce&&a.local_nonce==b.local_nonce&&a.slot==b.slot&&a.aircraft==b.aircraft;
}
struct Readback {
 Context context;
 // These are independent engine observations, not declarations from the peer.
 bool host_controller_preserved=false,host_plane_preserved=false,other_wingmen_preserved=false;
 bool player_class=false,player_physics=false,own_configuration=false;
 bool player_hidden=false,player_inactive=false,all_player_updates_fenced=false;
 bool player_alive=false,player_death_confirmed=false;
 bool npc_active=false,npc_retired=false,ai_links_detached=false;
 bool player_in_ai_arrays=false;
 // All four bridges are required: a callsign string is not a mission role.
 bool role_lookup_routes_player=false,unit_events_route_player=false;
 bool hud_routes_player=false,wingman_orders_exclude_player=false;
 bool guest_world_loaded=false;
 // Host squadron only, not every enemy/allied aircraft present in the mission.
 unsigned active_planes=0,active_wingmen_ai=0,active_player_planes=0;
};
inline bool preserved(const Readback&r){return r.host_controller_preserved&&r.host_plane_preserved&&r.other_wingmen_preserved&&!r.player_in_ai_arrays;}
inline bool owned(const Readback&r){return r.player_class&&r.player_physics&&r.own_configuration;}
inline bool routes(const Readback&r){return r.role_lookup_routes_player&&r.unit_events_route_player&&r.hud_routes_player&&r.wingman_orders_exclude_player;}
inline bool authenticated(const Context&c){return c.peer&&c.remote_nonce&&c.local_nonce;}
struct Adapter {
 Context context{};bool prepared=false,verified=false;
 ac8input::Lease inputs;uint64_t last_input_sequence=0;
 Object dead_world{};uint64_t dead_generation=0;bool spectating=false;
 const char* detail="not_prepared";
 void revoke(const char* why){verified=false;inputs.revoke();detail=why;}
 void clear(){context={};prepared=verified=false;inputs.revoke();last_input_sequence=0;detail="cleared";}
 bool prepare(const Readback&r){
  clear();const auto&c=r.context;
  if(same(dead_world,c.world)&&dead_generation&&c.generation<=dead_generation){spectating=true;detail="guest_dead_waiting_shared_restart";return false;}
  if(!distinct(c)||!c.generation||!c.revision||c.slot!=1||c.aircraft!=23){detail="invalid_baxter_context";return false;}
  if(!preserved(r)||!owned(r)||!r.player_hidden||!r.player_inactive||!r.all_player_updates_fenced||!r.npc_active||r.npc_retired||r.active_planes!=4||r.active_wingmen_ai!=3||r.active_player_planes!=1){detail="preparation_graph_unverified";return false;}
  context=c;prepared=true;spectating=false;detail="prepared_without_engine_role_commit";return true;
 }
 bool activation_permitted(const Readback&r){
  revoke("replacement_graph_unverified");
  if(!prepared||!same(context,r.context)||!authenticated(context)||!preserved(r)||!owned(r)||!routes(r)||!r.npc_retired||r.npc_active||!r.ai_links_detached||
   !r.player_alive||r.player_death_confirmed||!r.player_hidden||!r.player_inactive||!r.all_player_updates_fenced||!r.guest_world_loaded||r.active_planes!=3||r.active_wingmen_ai!=2||r.active_player_planes!=1)return false;
  detail="replacement_verified_activation_may_be_attempted";return true;
 }
 bool verify_active(const Readback&r){
  if(prepared&&same(context,r.context)&&preserved(r)&&owned(r)&&r.player_death_confirmed&&!r.player_alive){
   dead_world=context.world;dead_generation=context.generation;spectating=true;revoke("guest_dead_waiting_shared_restart");return false;
  }
  if(spectating){revoke("guest_dead_waiting_shared_restart");return false;}
  if(!prepared||!same(context,r.context)||!authenticated(context)||!preserved(r)||!owned(r)||!routes(r)||!r.npc_retired||r.npc_active||!r.ai_links_detached||
   !r.player_alive||r.player_death_confirmed||r.player_hidden||r.player_inactive||!r.guest_world_loaded||r.active_planes!=4||r.active_wingmen_ai!=2||r.active_player_planes!=2){revoke("active_role_readback_failed");return false;}
  verified=true;detail="role_verified_from_engine_readback";return true;
 }
 // Recheck the graph at the point of granting an input lease. A prior prepared
 // receipt, a retired pointer address, or a peer's READY cannot grant control.
 bool assignment(const Readback&r,ac8input::Assignment&out){
  out={};if(!verify_active(r))return false;
  out={context.peer,context.remote_nonce,context.local_nonce,context.generation,context.revision,context.slot,context.aircraft,true,true,true,true,true,true};
  return ac8input::usable(out);
 }
 Object lookup(const Readback&r){return verify_active(r)?context.player:Object{};}
 bool accept(const Readback&r,const ac8input::Frame&frame,uint64_t received_ms){
  ac8input::Assignment grant;
  if(!assignment(r,grant)||frame.sequence<=last_input_sequence)return false;
  if(!inputs.assigned&&!inputs.bind(grant))return false;
  if(!inputs.accept(frame,received_ms))return false;
  last_input_sequence=frame.sequence;return true;
 }
 bool sample(const Readback&r,uint64_t now,ac8input::Frame&out){
  out={};return verify_active(r)&&inputs.sample(now,out);
 }
};
}
