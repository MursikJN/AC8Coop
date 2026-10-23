#pragma once
#include <cstdint>
namespace plane_flight {
struct Identity { uintptr_t pointer=0; int32_t index=-1,serial=0; };
enum class Seen { safe,pending,retired,unknown,foreign };
struct Ledger {
 bool attempted=false,receipt_seen=false,identified=false,barrier=false,finish_entered=false,finished_ready=false;
 bool network_entered=false,parts_entered=false,network_identified=false,parts_identified=false;
 bool unknown_spawn=false,unknown_network=false,unknown_parts=false,running=false,cleanup_requested=false;
 bool plane_retired=false,network_retired=false,parts_retired=false,quarantined=false,destroy_accepted=false;
 uintptr_t raw_owned=0,raw_network=0,raw_parts=0;
 Identity owned{},network{},parts{};
 unsigned callbacks=0,destroys=0,ticks=0;
 uint64_t start_ms=0,lifetime_ms=15000;
 const char* status="error"; const char* reason="not_preflighted";
 template<class B> void receipt(B& b,uintptr_t actor) {
  ++callbacks;
  if(receipt_seen){unknown_spawn=true;barrier=false;return;}
  raw_owned=actor;receipt_seen=true;
  identified=b.acquire(actor,owned,0);
  if(identified)barrier=b.initial_barrier(actor);
 }
 template<class B> void quarantine(B& b,const char* why) {
  running=false;quarantined=true;status="quarantine";reason=why;
  if(identified&&b.resolve(owned)==Seen::safe){b.close_actor_barrier();b.quarantine_components();}
 }
 template<class B> void cleanup(B& b) {
  cleanup_requested=true;running=false;
  if(!attempted||!identified){status="error";reason="no_verified_owned_identity";return;}
  const auto seen=b.resolve(owned);
  if(seen==Seen::retired)plane_retired=true;
  if(network_identified)network_retired=b.resolve(network)==Seen::retired;
  if(parts_identified)parts_retired=b.resolve(parts)==Seen::retired;
  if(plane_retired){
   if(unknown_spawn||unknown_network||unknown_parts){status="quarantine";reason="owned_allocation_outcome_unknown";return;}
   bool complete=(!raw_network||network_retired)&&(!raw_parts||parts_retired);
   status=complete?"retired":"cleanup_pending";reason=complete?"all_owned_identities_retired":"owned_children_pending";return;
  }
  if(quarantined){status="quarantine";return;}
  if(seen==Seen::pending&&destroy_accepted){status="cleanup_pending";reason="actor_destroy_pending";return;}
  if(seen!=Seen::safe){quarantine(b,"owned_identity_unverified");return;}
  if(destroy_accepted){status="cleanup_pending";reason="destroy_accepted_waiting_retirement";return;}
  if(b.pending()){status="cleanup_pending";reason="actor_destroy_pending";return;}
  if(finish_entered&&!finished_ready){quarantine(b,"partial_finish_cleanup_not_proven");return;}
  if(!b.cleanup_guard(finish_entered)){quarantine(b,"cleanup_graph_or_registry_unverified");return;}
  b.close_actor_barrier();
  if(destroys>=3){status="cleanup_pending";reason="destroy_request_limit";return;}
  ++destroys;b.event("destroy_enter");bool accepted=b.destroy(raw_owned);b.event(accepted?"destroy_return_true":"destroy_return_false");
  destroy_accepted=accepted;
  status="cleanup_pending";reason="destroy_requested_retirement_unverified";
 }
 template<class B> bool prepare(B& b) {
  if(attempted){status="error";reason="attempt_already_consumed";return false;}
  attempted=true;b.event("spawn_enter");uintptr_t returned=b.spawn(*this);b.event("spawn_return");
  if(!receipt_seen){unknown_spawn=true;status="quarantine";reason="no_preinit_receipt";return false;}
  if(returned&&returned!=raw_owned)unknown_spawn=true;
  if(!identified||!barrier||callbacks!=1||returned!=raw_owned){cleanup(b);return false;}
  if(!b.configure()){cleanup(b);return false;}
  if(!b.preseed()){cleanup(b);return false;}
  if(!b.ready_to_finish()){cleanup(b);return false;}
  finish_entered=true;b.event("finish_enter");b.finish();b.event("finish_return");
  b.close_actor_barrier();
  if(!b.disable_components()||!b.finished_graph()){quarantine(b,"finished_component_graph_unverified");return false;}
  finished_ready=true;
  status="prepared";reason="native_initialized_actor_barrier_held";return true;
 }
 template<class B> void run(B& b) {
  if(!prepare(b))return;
  if(!b.seed()){cleanup(b);return;}
  start_ms=b.now();running=true;status="active";reason="native_manual_motion_window";
 }
 template<class B> void tick(B& b) {
  if(cleanup_requested){cleanup(b);return;}
  if(!running){if(attempted)cleanup(b);else{status="error";reason="not_running";}return;}
  if(lifetime_ms && b.now()-start_ms>=lifetime_ms){cleanup(b);return;}
  if(!b.motion()){cleanup(b);return;}
  ++ticks;status="active";reason="native_remote_motion_applied";
 }
};
}
