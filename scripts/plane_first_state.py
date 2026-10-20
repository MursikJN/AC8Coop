"""Offline first-movement-state staging. NO native backend or memory/network IO.

Outputs are requests, not completed writes. Even a successful Ready request does
not enable MotionGate or native updates. A future game-thread backend must own
fresh identity/barrier observations, cache writes, model initialization, readback
and final barrier release. Full movement state is not loadout/health/rollback.
"""
from dataclasses import asdict, dataclass
import copy
import hashlib
import json
import math
import struct

import plane_full_state as full
from plane_motion_wire import Binding, MotionGate
from plane_spawn_rollback import Identity, Rollback


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def _hash(value):
    if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("expected SHA256 identity")
    return value


@dataclass(frozen=True)
class Capture:
    process_instance: str  # session/process creation identity, not PID alone
    capture_sha256: str
    row_index: int

    def __post_init__(self):
        if not self.process_instance or type(self.row_index) is not int or self.row_index < 0:
            raise ValueError("invalid capture identity")
        _hash(self.capture_sha256)


@dataclass(frozen=True)
class ScaleEvidence:
    process_instance: str
    value: float
    evidence_sha256: str

    def __post_init__(self):
        _hash(self.evidence_sha256)
        if not self.process_instance or full.f32(self.value) <= 0:
            raise ValueError("invalid runtime scale")


@dataclass(frozen=True)
class FrozenState:
    binding: Binding
    capture: Capture
    configuration_digest: str
    document: bytes

    @property
    def sha256(self):
        return hashlib.sha256(self.document).hexdigest()


def stage_capture(row, binding, capture, configuration_digest, *, scale_evidence=None):
    """Freeze ONE row. Never combines fields from different capture generations."""
    _hash(configuration_digest)
    if type(binding) is not Binding or any(type(v) is not int or not 0 < v < 2**64 for v in vars(binding).values()):
        raise ValueError("invalid binding")
    if row["index"] != capture.row_index:
        raise ValueError("capture row mismatch")
    source = copy.deepcopy(row)
    provenance = "per_row"
    if "position_scale" not in source:
        if scale_evidence is None or scale_evidence.process_instance != capture.process_instance:
            raise ValueError("runtime scale must come from this source process instance")
        source["position_scale"] = {"values": [scale_evidence.value]}
        provenance = asdict(scale_evidence)
    elif scale_evidence is not None:
        if (scale_evidence.process_instance != capture.process_instance or
                full.f32(source["position_scale"]["values"][0]) != full.f32(scale_evidence.value)):
            raise ValueError("conflicting runtime scale evidence")
    mapped = full.map_initialization_observation(source)
    allowed_missing = {"native_clock_point_not_selected", "same_domain_native_clock_snapshot"}
    if set(mapped["missing"]) - allowed_missing:
        raise ValueError("incomplete movement source: " + ",".join(mapped["missing"]))
    # Sender clock is provenance only. Never put it in the first native sample.
    mapped["primary"]["0x8"] = None
    document = canonical({"schema": "ac8-first-movement-state-v1", "binding": asdict(binding),
                          "capture": asdict(capture), "configuration_digest": configuration_digest,
                          "scale_provenance": provenance, "movement": mapped,
                          "scope": "movement only; excludes aircraft/loadout/health/ownership/rollback"})
    return FrozenState(binding, capture, configuration_digest, document)


@dataclass(frozen=True)
class Guard:
    receiver_process: str
    plane: Identity
    network: Identity
    configuration_digest: str
    barrier_token: str
    revision: int
    identities_current: bool
    configuration_current: bool
    update_barrier_held: bool
    cache_ownership_verified: bool
    delta_arrays_empty_verified: bool
    models_configured: bool
    receiver_position_scale: float
    remote_role: int
    update_route: str


@dataclass(frozen=True)
class ReceiverClockPoint:
    receiver_process: str
    barrier_token: str
    observation_revision: int
    qpc_ticks: int
    seconds_per_tick: float
    clock08: int
    clock18: int
    clock20: int

    def timestamp(self):
        return full.native_timestamp(**{k: v for k, v in asdict(self).items()
                                      if k not in ("receiver_process", "barrier_token", "observation_revision")})


@dataclass(frozen=True)
class Scalar:
    target: str  # semantic cache name, never a native address
    offset: int
    kind: str
    value: object

    def bits(self):
        kinds = {"float32": "f", "uint8": "B", "uint32": "I", "int32": "i", "uint64": "Q"}
        if self.kind != "float32" and type(self.value) is not int:
            raise ValueError("noninteger scalar")
        if self.kind == "float32" and (type(self.value) not in (int, float) or not math.isfinite(self.value)):
            raise ValueError("nonfinite scalar")
        try:
            return struct.pack("<" + kinds[self.kind], self.value)
        except (KeyError, OverflowError, struct.error) as exc:
            raise ValueError("invalid scalar") from exc


@dataclass(frozen=True)
class CommitRequest:
    snapshot_sha256: str
    receiver_process: str
    barrier_token: str
    initial_revision: int
    writes: tuple

    @property
    def sha256(self):
        return digest({"snapshot": self.snapshot_sha256, "process": self.receiver_process,
                       "barrier": self.barrier_token, "revision": self.initial_revision,
                       "writes": [(x.target, x.offset, x.kind, x.bits().hex()) for x in self.writes]})


@dataclass(frozen=True)
class Readback:
    commit_sha256: str
    scalars: tuple
    # Future backend must verify BOTH model baselines, including dependencies.
    # A receipt asserts that proof; this module cannot produce such a receipt.
    both_model_baselines_for_commit: str


class FirstState:
    """Offline request state machine. Failures retire this exact generation."""
    def __init__(self, snapshot, rollback, receiver_process):
        if type(snapshot) is not FrozenState or type(rollback) is not Rollback or not receiver_process:
            raise ValueError("invalid first-state owners")
        if rollback.retired or rollback.unknown_outcome or rollback.plane_generation != snapshot.binding.plane_generation:
            raise ValueError("retired/unknown/mismatched rollback generation")
        doc = json.loads(snapshot.document)
        if (doc["binding"] != asdict(snapshot.binding) or doc["capture"] != asdict(snapshot.capture)
                or doc["configuration_digest"] != snapshot.configuration_digest):
            raise ValueError("snapshot identity/document mismatch")
        self.snapshot = snapshot
        self.rollback = rollback
        self.receiver_process = receiver_process
        self.motion_gate = MotionGate(snapshot.binding)
        self.phase = "staged"
        self.commit = None
        self.last_revision = -1

    @property
    def native_updates_enabled(self):
        return False  # No native backend exists in this module.

    def fail(self, reason):
        self.phase = "failed"
        self.motion_gate.retire()
        self.rollback.retire()
        raise ValueError(reason)

    def _guard(self, guard):
        if type(guard) is not Guard:
            self.fail("typed current observation required")
        if self.phase == "failed" or self.rollback.retired or self.rollback.unknown_outcome:
            self.fail("retired/uncertain generation")
        bool_fields = ("identities_current", "configuration_current", "update_barrier_held",
                       "cache_ownership_verified", "delta_arrays_empty_verified", "models_configured")
        if any(getattr(guard, k) is not True for k in bool_fields):
            self.fail("identity/configuration/barrier/cache/model prerequisite unverified")
        try:
            source_scale = json.loads(self.snapshot.document)["movement"]["runtime_position_scale"]
            if full.f32(guard.receiver_position_scale) != source_scale:
                self.fail("receiver runtime scale differs from fixed snapshot")
        except (KeyError, TypeError, ValueError) as exc:
            self.fail(str(exc))
        if (guard.receiver_process != self.receiver_process or not guard.barrier_token
                or type(guard.revision) is not int or guard.revision < 0
                or type(guard.remote_role) is not int or guard.remote_role != 2
                or guard.update_route != "fallback_7d6f0c0"
                or self.rollback.plane_generation != self.snapshot.binding.plane_generation
                or guard.configuration_digest != self.snapshot.configuration_digest
                or guard.plane != self.rollback.receipts.get("plane")
                or guard.network != self.rollback.receipts.get("network")
                or guard.plane.world_generation != self.rollback.world_generation):
            self.fail("wrong instance/identity/configuration/generation")
        if self.commit and guard.barrier_token != self.commit.barrier_token:
            self.fail("update barrier replaced")

    def prepare_request(self, guard, receiver_clock=None):
        self._guard(guard)
        if self.phase != "staged":
            self.fail("prepare may occur once per generation")
        if receiver_clock is None:
            return {"request": "observe_receiver_local_native_clock_point", "executed": False,
                    "snapshot_sha256": self.snapshot.sha256, "blocked": "native_point_unselected"}
        if (type(receiver_clock) is not ReceiverClockPoint or receiver_clock.receiver_process != self.receiver_process
                or receiver_clock.barrier_token != guard.barrier_token
                or receiver_clock.observation_revision != guard.revision):
            self.fail("clock must be receiver-local and current inside this exact barrier observation")
        try:
            timestamp = receiver_clock.timestamp()
            mapped = json.loads(self.snapshot.document)["movement"]
            writes = []
            # Explicit whitelists prevent C++ headers/arrays/refcounts entering a commit.
            for target, start, count in (("primary", 0x20, 11), ("cache140", 8, 11),
                                         ("cache150", 8, 8), ("cache160", 0x20, 6), ("cache170", 8, 6)):
                for offset in range(start, start + 4 * count, 4):
                    kind = "float32"
                    if target == "primary":
                        if 0x2c <= offset <= 0x34: kind = "int32"
                        elif offset == 0x44: kind = "uint32"
                    scalar = Scalar(target, offset, kind, mapped[target][hex(offset)])
                    scalar.bits(); writes.append(scalar)
            writes += [Scalar("cache140", 0x34, "uint8", mapped["cache140"]["0x34"]),
                       Scalar("cache170", 0x20, "uint8", mapped["cache170"]["0x20"]),
                       Scalar("primary", 8, "uint64", timestamp),
                       Scalar("owned_plane", 0x3c38, "uint64", timestamp)]
            for scalar in writes: scalar.bits()
        except (KeyError, TypeError, ValueError) as exc:
            self.fail("cannot prepare full state: " + str(exc))
        self.commit = CommitRequest(self.snapshot.sha256, self.receiver_process, guard.barrier_token,
                                    guard.revision, tuple(writes))
        self.last_revision = guard.revision
        self.phase = "commit_requested"
        return self.commit

    def verify_readback(self, guard, readback):
        self._guard(guard)
        if self.phase != "commit_requested" or guard.revision <= self.last_revision:
            self.fail("readback must follow this commit request")
        if (type(readback) is not Readback or readback.commit_sha256 != self.commit.sha256
                or readback.both_model_baselines_for_commit != self.commit.sha256):
            self.fail("unverified commit or both model baselines")
        try:
            expected = {(s.target, s.offset, s.kind): s.bits() for s in self.commit.writes}
            observed = {(s.target, s.offset, s.kind): s.bits() for s in readback.scalars}
            if len(observed) != len(readback.scalars) or observed != expected:
                self.fail("cache/timestamp readback mismatch or duplicate")
        except (TypeError, ValueError, AttributeError) as exc:
            self.fail(str(exc))
        self.last_revision = guard.revision
        self.phase = "readback_verified"

    def ready_request(self, guard):
        self._guard(guard)
        if self.phase != "readback_verified" or guard.revision <= self.last_revision:
            self.fail("Ready requires fresh observation after complete verified readback")
        self.phase = "ready_requested"
        return {"request": "release_exact_barrier_then_verify_ready", "executed": False,
                "snapshot_sha256": self.snapshot.sha256, "commit_sha256": self.commit.sha256,
                "binding": asdict(self.snapshot.binding), "barrier_token": self.commit.barrier_token,
                "native_updates_enabled": False, "motion_gate_enabled": False,
                "requires_backend": "atomic game-thread revalidation and barrier release; failure retires generation"}
