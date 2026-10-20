"""Read-only probe guard/ownership tests with fake memory and reflected objects."""
import json
from pathlib import Path
import struct
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import sample_plane_initialization as init
import sample_plane_motion as motion
import test_plane_motion as fixture_module

POSE_FIXTURE = r'''
H.props.K2_GetActorLocation=function() return {X=100,Y=-200,Z=300} end
-- Exact reflected Rotator schema from camera-diagnostic-20261020-042322-2:
-- lowercase pitch, uppercase Yaw/Roll. A capital-P mock hid the live failure.
H.props.K2_GetActorRotation=function() return {pitch=10,Yaw=20,Roll=30} end
function StaticFindObject(path)
 local struct=path:find("Location",1,true) and "Vector" or "Rotator"
 return {IsValid=function() return true end,ForEachProperty=function(_,cb)
  cb({GetFName=function() return {ToString=function() return "ReturnValue" end} end,
      GetClass=function() return {GetFName=function() return {ToString=function() return "StructProperty" end} end} end,
      GetStruct=function() return {GetFullName=function() return "ScriptStruct /Script/CoreUObject."..(H.bad_struct or struct) end} end})
 end}
end
'''


class InitializationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixture_module.MotionTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.path = self.fixture.path

    def memory(self):
        _, put, read, ticket = self.fixture.memory()
        base = 0x140000000
        for offset, fmt in init.ACTOR_FIELDS.items():
            put(ticket["pawn"] + int(offset, 0), bytes(struct.calcsize("<" + fmt)))
        put(ticket["pawn"] + 0x18c8, bytes(8))
        put(base + init.CLOCK_POINTER_RVA, bytes(8))
        put(base + init.CLOCK_SCALE_RVA, struct.pack("<d", 1e-7))
        put(base + init.POSITION_SCALE_RVA, struct.pack("<f", 100))
        return init.InitializationReader(read, base, ticket, lambda: 12345), put, ticket

    def test_lua_pose_companion_and_ticket_are_consistent(self):
        lua = self.fixture.lua
        lua.execute(POSE_FIXTURE)
        probe = lua.execute((ROOT / "probe/AC8CoopRecon/Scripts/plane_initialization_probe.lua").read_text())
        probe(str(self.path), "new")
        ticket = motion.parse_ticket(self.path / "initialization-ticket-new.tsv", time.time()-10, time.time()-11, time.time())
        pose = init.read_pose(self.path / "initialization-pose-new.tsv", ticket)
        self.assertEqual(pose["location_y"], -200)
        self.assertEqual(pose["rotation_pitch"], 10)
        with self.assertRaises(Exception): probe(str(self.path), "new")

    def test_lua_unsafe_schema_or_phase_does_not_publish_ticket(self):
        for expr in ("H.bad_struct='Quat'", "H.props.bIsIGCActor=true", "H.worldname='MainMenu'",
                     "H.props.K2_GetActorLocation=function() return {X=0/0,Y=0,Z=0} end"):
            lua = self.fixture.lua
            lua.execute(fixture_module.LUA_FIXTURE + POSE_FIXTURE + expr)
            probe = lua.execute((ROOT / "probe/AC8CoopRecon/Scripts/plane_initialization_probe.lua").read_text())
            with self.assertRaises(Exception): probe(str(self.path), "bad")
            self.assertFalse((self.path / "initialization-ticket-bad.tsv").exists())

    def test_missing_or_nonfinite_pitch_is_named_and_never_zero_filled(self):
        for value in ("nil", "0/0", "math.huge"):
            lua = self.fixture.lua
            lua.execute(fixture_module.LUA_FIXTURE + POSE_FIXTURE +
                        "H.props.K2_GetActorRotation=function() return {pitch="+value+",Yaw=20,Roll=30} end")
            probe = lua.execute((ROOT / "probe/AC8CoopRecon/Scripts/plane_initialization_probe.lua").read_text())
            with self.assertRaisesRegex(Exception, "invalid pose field rotation_pitch"):
                probe(str(self.path), "bad-pitch")
            self.assertFalse((self.path / "initialization-ticket-bad-pitch.tsv").exists())

    def test_reads_missing_input_sources_and_null_clock_without_creating_it(self):
        reader, put, ticket = self.memory()
        put(ticket["pawn"] + 0xfe4, struct.pack("<6f", .1, .2, .3, .4, .5, .6))
        row = reader.sample(motion.load_layout())
        self.assertEqual(len(row["fields"]), 16)
        self.assertAlmostEqual(row["actor_fields"]["0xfe4"]["values"][5], .6, places=6)
        self.assertEqual(row["clock"]["status"], "not_initialized")
        self.assertEqual(row["position_scale"]["values"], [100.0])
        self.assertEqual(row["input_chain"]["actor+18c8"], "0x0")
        json.dumps(row, allow_nan=False)

    def test_runtime_scale_change_discards_sample(self):
        reader, put, _ = self.memory()
        original = reader.read
        def changed(address, size):
            data = original(address, size)
            if address == reader.base + init.CLOCK_SCALE_RVA:
                put(reader.base + init.POSITION_SCALE_RVA, struct.pack("<f", 10))
            return data
        reader.read = changed
        with self.assertRaisesRegex(ValueError, "position scale changed"):
            reader.sample(motion.load_layout())

    def test_pointer_chain_swap_is_unknown_not_zero_input(self):
        reader, put, ticket = self.memory()
        put(ticket["pawn"] + 0x18c8, struct.pack("<Q", 0x600000))
        put(0x600000, bytes(0x28)); put(0x600100, bytes(8)); put(0x600108, b"\x01")
        original = reader.read
        def changed(address, size):
            data = original(address, size)
            if address == 0x600108: put(ticket["pawn"] + 0x18c8, bytes(8))
            return data
        reader.read = changed
        row = reader.sample(motion.load_layout())
        self.assertEqual(row["input_chain"]["status"], "unavailable")
        self.assertIn("pointer changed", row["input_chain"]["error"])

    def test_native_clock_capture_and_pointer_change_refusal(self):
        reader, put, _ = self.memory()
        put(reader.base + init.CLOCK_POINTER_RVA, struct.pack("<Q", 0x700000))
        put(0x700008, struct.pack("<4q", 11, 12, 13, -14))
        self.assertEqual(reader.clock()["fields_08_10_18_20"]["values"], [11, 12, 13, -14])
        original = reader.read
        def changed(address, size):
            data = original(address, size)
            if address == 0x700008: put(reader.base + init.CLOCK_POINTER_RVA, bytes(8))
            return data
        reader.read = changed
        with self.assertRaisesRegex(ValueError, "clock instance changed"): reader.clock()

    def test_player_swap_after_extra_reads_discards_whole_sample(self):
        reader, put, ticket = self.memory()
        original = reader.read
        def changed(address, size):
            data = original(address, size)
            if address == reader.base + init.CLOCK_SCALE_RVA:
                put(ticket["controller"]+ticket["pc_pawn_offset"], struct.pack("<Q", 0x900000))
            return data
        reader.read = changed
        with self.assertRaisesRegex(ValueError, "controlled pawn changed"): reader.sample(motion.load_layout())


if __name__ == "__main__": unittest.main()
