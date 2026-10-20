"""Offline packet admission; no claim of tested native plane create/apply/destroy."""
from dataclasses import replace
from pathlib import Path
import math
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import plane_motion_wire as wire


class MotionWireTests(unittest.TestCase):
    def setUp(self):
        self.binding = wire.Binding(123, 456, 789, 1, 1)
        self.motion = wire.Motion(self.binding, 1, 100000, (4., -5., 6.), (0., 0., 0., 1.), (1., 0., 0.), 300.)
        self.gate = wire.MotionGate(self.binding)

    def test_wire_has_fixed_bytes_and_no_alignment_or_native_pointers(self):
        packet = wire.encode(self.motion)
        self.assertEqual(len(packet), 128)
        self.assertEqual(packet[:8], b"AC8M\x01\x00\x00\x00")
        self.assertEqual(wire.decode(packet), self.motion)

    def test_packets_do_not_spawn_or_ready_a_plane(self):
        self.assertIsNone(self.gate.accept(wire.encode(self.motion), 123))
        self.assertFalse(self.gate.ready)
        self.gate.mark_native_ready()
        self.assertEqual(self.gate.accept(wire.encode(self.motion), 123), self.motion)

    def test_wrong_transport_identity_cannot_use_matching_payload(self):
        self.gate.mark_native_ready()
        self.assertIsNone(self.gate.accept(wire.encode(self.motion), 999))
        self.assertEqual(self.gate.last_sequence, 0)

    def test_reorder_duplicates_and_stale_clock_do_not_replace_sample(self):
        self.gate.mark_native_ready()
        newer = replace(self.motion, sequence=5, source_time_us=500000)
        self.assertIsNotNone(self.gate.accept(wire.encode(newer), 123))
        for packet in (newer, self.motion, replace(newer, sequence=6)):
            self.assertIsNone(self.gate.accept(wire.encode(packet), 123))
        self.assertEqual(self.gate.last_sequence, 5)

    def test_prior_connection_mission_or_plane_is_rejected(self):
        for field in ("peer_nonce", "local_nonce", "mission_epoch", "plane_generation"):
            with self.subTest(field=field):
                binding = replace(self.binding, **{field:getattr(self.binding, field)+1})
                gate = wire.MotionGate(binding)
                gate.mark_native_ready()
                self.assertIsNone(gate.accept(wire.encode(self.motion), 123))
                self.assertIsNotNone(gate.accept(wire.encode(replace(self.motion, binding=binding)), 123))

    def test_retire_is_terminal_and_cuts_off_arrivals_before_destruction(self):
        self.gate.mark_native_ready()
        self.gate.retire()
        self.assertIsNone(self.gate.accept(wire.encode(self.motion), 123))
        with self.assertRaises(ValueError):
            self.gate.mark_native_ready()

    def test_bad_length_magic_version_flags_build_rejected(self):
        self.gate.mark_native_ready()
        packet = wire.encode(self.motion)
        variants = [packet[:-1], packet+b"\0"]
        for offset in (0, 4, 6, 8):
            broken = bytearray(packet); broken[offset] ^= 0x10
            variants.append(broken)
        for broken in variants:
            self.assertIsNone(self.gate.accept(broken, 123))
        self.assertEqual(self.gate.last_sequence, 0)

    def test_nonfinite_and_invalid_orientation_rejected(self):
        for motion in (replace(self.motion, speed=math.nan), replace(self.motion, position=(math.inf, 0, 0)),
                       replace(self.motion, orientation=(0, 0, 0, 0)), replace(self.motion, speed=-1)):
            with self.assertRaises(ValueError):
                wire.encode(motion)
        corrupted = bytearray(wire.encode(self.motion))
        corrupted[wire.HEADER.size:wire.HEADER.size+8] = __import__('struct').pack('<d', math.nan)
        self.gate.mark_native_ready()
        self.assertIsNone(self.gate.accept(corrupted, 123))

    def test_selector_uses_both_distinct_native_orientation_blocks(self):
        row = {"index":0, "elapsed_s":0., "fields":{key:{"values":values} for key,values in {
            "0x868":[1], "0x908":[1,2,3], "0x8f8":[0,0,0,1],
            "0x930":[4,5,6], "0x920":[0,0,1,0], "0x1f8":[1,0,0], "0x1e0":[0,0,300]}.items()}}
        first = wire.from_observation(row, self.binding)
        self.assertEqual(first.orientation, (0,0,0,1))
        row['fields']['0x868']['values'] = [0]
        second = wire.from_observation(row, self.binding)
        self.assertEqual(second.orientation, (0,0,1,0))
        self.assertNotEqual(first.position, second.position)


if __name__ == "__main__":
    unittest.main()
