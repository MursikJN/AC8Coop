#pragma once
#include <cstdint>

namespace dummy_probe {
struct Identity { uintptr_t pointer = 0; int32_t index = -1; int32_t serial = 0; };
enum class Seen { safe, pending, retired, foreign, unknown, world_lost };
// Decisions shared with a fault-injection backend. No engine or Lua API here.
struct Ledger {
    bool attempted = false;
    bool identified = false;
    bool retired = false;
    uintptr_t raw_owned = 0;
    Identity owned{};
    unsigned destroy_requests = 0;
    const char* status = "error";
    const char* reason = "not_preflighted";

    template<class Backend> void verify(Backend& b) {
        if (!attempted) { status = "error"; reason = "no_owned_attempt"; return; }
        if (retired) { status = "retired"; reason = "identity_retired"; return; }
        if (!identified) { status = "error"; reason = "unknown_allocation_or_serial"; return; }
        const Seen seen = b.inspect(owned);
        if (seen == Seen::retired) {
            retired = true; status = "retired"; reason = "identity_retired"; return;
        }
        if (seen == Seen::pending) { status = "cleanup_pending"; reason = "destroy_marked_not_freed"; return; }
        if (seen != Seen::safe) {
            status = "error";
            reason = seen == Seen::foreign ? "foreign_pawn_or_playerstate" :
                seen == Seen::world_lost ? "owned_world_unverified" : "owned_identity_unverified";
            return;
        }
        if (destroy_requests >= 3) { status = "cleanup_pending"; reason = "destroy_request_limit"; return; }
        ++destroy_requests;
        b.event("destroy_enter");
        const bool accepted = b.destroy(owned.pointer);
        b.event(accepted ? "destroy_return_true" : "destroy_return_false");
        status = accepted ? "performed" : "cleanup_pending";
        reason = accepted ? "destroy_requested_retirement_unverified" : "destroy_not_marked";
        // A returned bool never proves deallocation. A later observation does.
    }

    template<class Backend> void run(Backend& b) {
        if (attempted) { status = "error"; reason = "attempt_already_consumed"; return; }
        // Consume before calling any mutating native function, including faults.
        attempted = true;
        b.event("spawn_enter");
        raw_owned = b.spawn(); // Receipt is the very first operation on return.
        b.event(raw_owned ? "spawn_return_nonnull" : "spawn_return_null_unknown");
        if (!raw_owned) { status = "error"; reason = "null_spawn_outcome_unverified"; return; }
        identified = b.acquire(raw_owned, owned);
        if (!identified) { status = "error"; reason = "owned_serial_unverified"; return; }
        b.event("owned_serial_acquired");
        verify(b);
    }
};
}
