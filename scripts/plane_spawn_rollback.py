"""Offline rollback decision model. NO native backend, calls, memory access or spawning.

Observations must eventually come from fresh game-thread weak-identity checks.
An action is a request, never evidence of completion. Re-observe after each action.
"""
from dataclasses import dataclass
from enum import Enum


class Seen(Enum):
    ABSENT = "verified_absent"
    OWNED = "same_index_serial_world_owner"
    OTHER = "different_owner_or_serial"
    UNKNOWN = "unverified"


@dataclass(frozen=True)
class Identity:
    world_generation: int
    index: int
    serial: int

    def __post_init__(self):
        if any(type(v) is not int for v in (self.world_generation, self.index, self.serial)):
            raise ValueError("identity must contain integers")
        if self.world_generation <= 0 or self.index < 0 or self.serial <= 0:
            raise ValueError("unverified weak identity")


@dataclass(frozen=True)
class Observation:
    # Derived from the exact receipt identities, never from address/name alone.
    registry: Seen
    plane: Seen
    dummy: Seen
    network: Seen
    dummy_has_foreign_pawn: bool = False
    world_verified: bool = True

    def __post_init__(self):
        if any(type(v) is not Seen for v in (self.registry, self.plane, self.dummy, self.network)):
            raise ValueError("observation requires explicit verified state")
        if type(self.world_verified) is not bool or type(self.dummy_has_foreign_pawn) is not bool:
            raise ValueError("observation requires explicit boolean guards")


class Rollback:
    """Tracks acquisitions; partial/unknown native call outcomes quarantine retry.

    Native adapters must acquire a receipt immediately on a successful allocation,
    before fallible initialization. The observer must verify registry ABSENT even
    if BeginPlay/Init failed before a registration receipt could be recorded.
    """
    def __init__(self, world_generation, plane_generation):
        if any(type(v) is not int or v <= 0 for v in (world_generation, plane_generation)):
            raise ValueError("invalid generation")
        self.world_generation = world_generation
        self.plane_generation = plane_generation
        self.receipts = {}
        self.unknown_outcome = False
        self.retired = False
        self.released = False

    def acquired(self, kind, identity):
        if self.retired or kind not in ("dummy", "plane", "network") or kind in self.receipts:
            raise ValueError("invalid acquisition")
        if identity.world_generation != self.world_generation or identity in self.receipts.values():
            raise ValueError("wrong world or duplicate resource")
        if kind == "network" and "plane" not in self.receipts:
            raise ValueError("network must have an owned plane Outer")
        self.receipts[kind] = identity

    def allocation_outcome_unknown(self):
        self.unknown_outcome = True

    def retire(self):
        # Must happen before queue cancellation/native cleanup. Terminal generation.
        self.retired = True

    def next_action(self, observed):
        if not self.retired:
            raise ValueError("retire generation before cleanup")
        if self.released:
            return "complete"
        if self.unknown_outcome or not observed.world_verified or observed.dummy_has_foreign_pawn:
            return "quarantine"
        for kind in ("plane", "dummy", "network"):
            state = getattr(observed, kind)
            if state in (Seen.UNKNOWN, Seen.OTHER):
                return "quarantine"
            if state == Seen.OWNED and kind not in self.receipts:
                return "quarantine"
        if observed.registry in (Seen.UNKNOWN, Seen.OTHER):
            return "quarantine"
        if observed.registry == Seen.OWNED:
            if "network" not in self.receipts or observed.network != Seen.OWNED:
                return "quarantine"
            return "compare_owner_then_unregister_on_game_thread"
        if observed.plane == Seen.OWNED:
            return "destroy_owned_plane_via_world_actor_path"
        if observed.dummy == Seen.OWNED:
            # Dummy K2_DestroyActor is a no-op in this build.
            return "destroy_owned_dummy_via_world_actor_path"
        if observed.network == Seen.OWNED:
            # Outer-owned UObject; never call delete/free or force GC here.
            return "wait_for_owned_network_retirement"
        self.released = True
        return "complete"
