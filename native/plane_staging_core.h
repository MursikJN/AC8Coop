#pragma once
#include <cstdint>
namespace plane_stage {
struct Identity { uintptr_t pointer=0; int32_t index=-1,serial=0; };
enum class Seen { safe,pending,retired,foreign,unknown,world_lost };
struct Ledger {
 bool attempted=false,received=false,identified=false,barrier=false,retired=false,network_identified=false,network_retired=false,staged=false;
 bool network_creation_entered=false,network_outcome_unknown=false,spawn_outcome_unknown=false;
 uintptr_t raw_owned=0,raw_network=0;
 Identity owned{},network{};
 unsigned callbacks=0,destroy_requests=0;
 const char* status="error"; const char* reason="not_preflighted";
 template<class B> void receipt(B& b,uintptr_t actor) {
  ++callbacks;
  if(received) { spawn_outcome_unknown=true;barrier=false; status="error"; reason="duplicate_callback"; return; }
  raw_owned=actor; received=true; // Receipt BEFORE reads, serial allocation, logging or writes.
  identified=b.acquire(actor,owned,false);
  if(!identified) { reason="callback_identity_unverified"; return; }
  barrier=b.barrier(actor);
  b.event(barrier?"preinit_barrier_applied":"preinit_barrier_failed");
 }
 template<class B> void verify(B& b) {
  if(!attempted || !identified) { status="error"; reason="owned_identity_unverified"; return; }
  auto seen=b.inspect(owned);
  if(seen==Seen::retired) retired=true;
  if(network_identified) network_retired=b.resolve(network)==Seen::retired;
  if(retired && (network_outcome_unknown||spawn_outcome_unknown)) { status="error";reason="plane_retired_allocation_outcome_unknown";return; }
  if(retired) { status=(!raw_network||network_retired)?"retired":"cleanup_pending"; reason=(!raw_network||network_retired)?"all_owned_identities_retired":"plane_retired_network_pending"; return; }
  if(seen==Seen::pending) { status="cleanup_pending"; reason="destroy_marked_not_freed"; return; }
  if(seen!=Seen::safe) { status="error"; reason=seen==Seen::foreign?"foreign_possession_or_state":"owned_cleanup_unverified"; return; }
  if(destroy_requests>=3) { status="cleanup_pending"; reason="destroy_request_limit"; return; }
  ++destroy_requests; b.event("destroy_enter"); bool accepted=b.destroy(raw_owned);
  b.event(accepted?"destroy_return_true":"destroy_return_false");
  status="cleanup_pending"; reason=accepted?"destroy_requested_retirement_unverified":"destroy_not_marked";
 }
 template<class B> void run(B& b) {
  if(attempted) { status="error";reason="attempt_already_consumed";return; }
  attempted=true; b.event("spawn_enter"); auto returned=b.spawn(*this);
  b.event("spawn_return");
  if(!received) { spawn_outcome_unknown=true; status="error";reason="no_preinit_receipt";return; }
  if(returned&&returned!=raw_owned)spawn_outcome_unknown=true;
  bool valid=identified&&barrier&&callbacks==1&&returned==raw_owned&&b.inspect(owned)==Seen::safe;
  if(valid && b.network_prerequisites(raw_owned)) {
   network_creation_entered=true;network_outcome_unknown=true;
   raw_network=b.create_network(raw_owned); // Immediate receipt before fallible validation.
   if(raw_network) network_identified=b.acquire(raw_network,network,true);
   if(network_identified) { network_outcome_unknown=false;staged=b.stage(); }
   b.event(staged?"cold_cache_stage_readback_ok":"cold_cache_stage_not_completed");
  }
  // No FinishSpawning, Init, possession, registry insertion or release exists here.
  verify(b);
 }
};
}
