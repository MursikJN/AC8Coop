"""Experimental offline motion-message contract. No sockets, game access or native calls.

Not wired into Connection Test 0.1.2. Values stay in observed AC8 internal axes/units.
Native SDK objects, pointers, aircraft loadouts and gameplay events are NOT encoded.
"""
from dataclasses import dataclass
import math
import struct

BUILD = 25201480
HEADER = struct.Struct("<4sHHI7Q")
BODY = struct.Struct("<3d4f3fd")
SIZE = HEADER.size + BODY.size  # 128 bytes, explicit little endian


@dataclass(frozen=True)
class Binding:
    # Established by authenticated transport + reliable mission/spawn readiness, not by motion.
    peer_id: int
    peer_nonce: int
    local_nonce: int
    mission_epoch: int
    plane_generation: int


@dataclass(frozen=True)
class Motion:
    binding: Binding
    sequence: int
    source_time_us: int  # sender-relative observation time; not a shared wall clock
    position: tuple
    orientation: tuple  # selected native float32[4]; component convention remains native
    direction: tuple
    speed: float


def validate(m):
    ids = (*vars(m.binding).values(), m.sequence)
    if any(type(v) is not int or not 0 < v < 2**64 for v in ids):
        raise ValueError("invalid binding/sequence")
    if type(m.source_time_us) is not int or not 0 <= m.source_time_us < 2**64:
        raise ValueError("invalid source timestamp")
    if (len(m.position), len(m.orientation), len(m.direction)) != (3, 4, 3):
        raise ValueError("invalid component counts")
    values = (*m.position, *m.orientation, *m.direction, m.speed)
    if not all(type(v) in (float, int) and math.isfinite(v) for v in values):
        raise ValueError("non-finite/non-numeric motion")
    # Diagnostic admission bounds, not claimed engine/world limits.
    if max(abs(v) for v in m.position) > 1e12 or not 0 <= m.speed <= 1e6:
        raise ValueError("motion outside diagnostic bounds")
    for vector in (m.orientation, m.direction):
        if not .98 <= sum(v*v for v in vector) <= 1.02:
            raise ValueError("orientation/direction not approximately unit length")


def encode(m):
    validate(m)
    b = m.binding
    return HEADER.pack(b"AC8M", 1, 0, BUILD, b.peer_id, b.peer_nonce, b.local_nonce,
                       b.mission_epoch, b.plane_generation, m.sequence, m.source_time_us) + BODY.pack(
                           *m.position, *m.orientation, *m.direction, m.speed)


def decode(data):
    if len(data) != SIZE:
        raise ValueError("invalid motion packet length")
    magic, version, flags, build, *ids = HEADER.unpack_from(data)
    if (magic, version, flags, build) != (b"AC8M", 1, 0, BUILD):
        raise ValueError("unsupported motion header/build")
    values = BODY.unpack_from(data, HEADER.size)
    m = Motion(Binding(*ids[:5]), ids[5], ids[6], values[:3], values[3:7], values[7:10], values[10])
    validate(m)
    return m


def from_observation(row, binding):
    fields = row["fields"]
    selector = fields["0x868"]["values"][0]
    if type(selector) is not int or not 0 <= selector <= 255:
        raise ValueError("invalid native transform selector")
    position_key, orientation_key = ("0x930", "0x920") if selector == 0 else ("0x908", "0x8f8")
    return Motion(binding, row["index"]+1, round(row["elapsed_s"]*1e6),
                  tuple(fields[position_key]["values"]), tuple(fields[orientation_key]["values"]),
                  tuple(fields["0x1f8"]["values"]), fields["0x1e0"]["values"][2])


class MotionGate:
    """Offline admission model, not a native actor manager or destruction implementation.

    A retired binding is terminal. The caller must use a NEW generation/epoch/nonce
    when constructing a replacement. Transport arrival must never create the actor.
    """
    def __init__(self, binding):
        self.binding = binding
        self.ready = False
        self.retired = False
        self.last_sequence = 0
        self.last_time = -1

    def mark_native_ready(self):
        if self.retired:
            raise ValueError("retired binding cannot reactivate")
        self.ready = True

    def retire(self):
        self.ready = False
        self.retired = True

    def accept(self, data, transport_peer_id):
        if not self.ready or self.retired or transport_peer_id != self.binding.peer_id:
            return None
        try:
            motion = decode(data)
        except (ValueError, TypeError, struct.error):
            return None
        if (motion.binding != self.binding or motion.sequence <= self.last_sequence
                or motion.source_time_us <= self.last_time):
            return None
        self.last_sequence, self.last_time = motion.sequence, motion.source_time_us
        return motion
