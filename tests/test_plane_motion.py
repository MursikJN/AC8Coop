"""Offline guards/decoding tests; these do not validate native flight semantics."""
import importlib.util
import json
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("motion", ROOT / "scripts/sample_plane_motion.py")
motion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(motion)
sys.path.insert(0, r"D:\projects\unreal-mod-tools\packages\python-analysis")
from lupa import LuaRuntime

LUA_FIXTURE = r'''
H={props={},pcprops={}}
local function valid() return true end
local function named(name) return {ToString=function() return name end} end
local cls={IsValid=valid,GetAddress=function() return 0x500000 end,
 GetFullName=function() return "Class /Script/Live.LivePlayerPlaneF14D" end,
 GetSuperStruct=function() return nil end,
 ForEachProperty=function(_,callback)
  for _,name in ipairs({"Pawn","Controller"}) do
   callback({GetFName=function() return named(name) end,
    GetClass=function() return {GetFName=function() return named(H.type or "ObjectProperty") end} end,
    GetOffset_Internal=function() return name=="Pawn" and 0x300 or 0x400 end})
  end
 end}
H.world={IsValid=valid,GetAddress=function() return 0x400000 end,
 GetFullName=function() return H.worldname or "World /Game/Mission007.Mission007" end}
local function obj(addr,props)
 local methods={IsValid=valid,GetAddress=function() return addr end,
  GetClass=function() return cls end,GetWorld=function() return H.world end,
  IsA=function(_,name) assert(name=="/Script/Live.LivePlayerPlane");return true end}
 return setmetatable({}, {__index=function(_,key)
  if methods[key] then return methods[key] end
  if key=="bIsAnimationPlane" and props[key]==nil then return nil end
  assert(props[key]~=nil,"unknown property "..key);return props[key]
 end,__newindex=function() error("game object write forbidden") end})
end
H.pc=obj(0x200000,H.pcprops); H.plane=obj(0x300000,H.props)
H.pcprops.Pawn=H.plane;H.props.Controller=H.pc
H.props.bIsActivated=true;H.props.bIsIGCActor=false
function FindAllOf(name) assert(name=="LivePlayerController");return H.duplicate and {H.pc,H.pc} or {H.pc} end
local function forbidden() error("game mutation/hook forbidden") end
RegisterKeyBind=forbidden;RegisterHook=forbidden;LoopAsync=forbidden;RegisterCustomProperty=forbidden
'''


class MotionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(LUA_FIXTURE)
        self.probe = self.lua.execute((ROOT / "probe/AC8CoopRecon/Scripts/plane_motion_probe.lua").read_text())
        self.layout = motion.load_layout()

    def ticket(self):
        self.probe(str(self.path).replace("\\", "/"), "test")
        return motion.parse_ticket(self.path / "flight-ticket-test.tsv", time.time()-10, time.time()-11, time.time())

    def memory(self):
        ticket = self.ticket()
        memory = {}
        def put(address, data):
            memory.update({address+i: byte for i, byte in enumerate(data)})
        def read(address, size):
            return bytes(memory[address+i] for i in range(size))
        for name in ("controller", "pawn", "world"):
            put(ticket[name], bytes(0x28))
        put(ticket["pawn"], struct.pack("<Q", 0x140000000 + motion.F14D_VTABLE_RVA))
        put(ticket["pawn"]+0x10, struct.pack("<Q", ticket["pawn_class"]))
        put(ticket["controller"]+ticket["pc_pawn_offset"], struct.pack("<Q", ticket["pawn"]))
        put(ticket["pawn"]+ticket["plane_controller_offset"], struct.pack("<Q", ticket["controller"]))
        put(ticket["pawn"]+motion.INLINE, bytes(motion.EXTENT))
        return motion.FlightReader(read, 0x140000000, ticket), put, read, ticket

    def test_lua_ticket_parses_and_reflects_backlinks(self):
        ticket = self.ticket()
        self.assertEqual(ticket["pawn"], 0x300000)
        self.assertEqual(ticket["pc_pawn_offset"], 0x300)
        self.assertEqual(ticket["plane_controller_offset"], 0x400)

    def test_live_player_without_wingman_animation_property_can_record(self):
        # Live schema 20261020-073801-1: this property belongs to LiveAIWingmanPlane.
        # UE4SS returned nil on the player, so requiring equality to false blocked F8.
        self.lua.execute("H.props.bIsAnimationPlane=nil")
        self.assertEqual(self.ticket()["pawn"], 0x300000)

    def test_lua_refuses_cinematic_inactive_and_wrong_mission(self):
        for expression in ("H.props.bIsIGCActor=true",
                           "H.props.bIsActivated=false", "H.worldname='World Menu'", "H.duplicate=true",
                           "H.props.Controller=H.plane", "H.type='IntProperty'"):
            with self.subTest(expression=expression):
                self.lua.execute(LUA_FIXTURE)
                self.lua.execute(expression)
                with self.assertRaises(Exception):
                    self.probe(str(self.path), "blocked")
                self.assertFalse((self.path / "flight-ticket-blocked.tsv").exists())

    def test_ticket_rejects_stale_process_and_old_capture(self):
        self.ticket()
        path = self.path / "flight-ticket-test.tsv"
        for process, session, now in ((time.time()+10, time.time()-11, time.time()),
                                       (time.time()-10, time.time()-11, time.time()+90)):
            with self.assertRaisesRegex(ValueError, "stale ticket"):
                motion.parse_ticket(path, process, session, now)

    def test_decode_mixed_pose_types_and_nonfinite_preserves_bytes(self):
        block = bytearray(motion.EXTENT)
        struct.pack_into("<4f3d", block, 0x920, .25, .5, .75, 1, 123456789.5, -20, 30)
        struct.pack_into("<f", block, 0x108, float("nan"))
        result = motion.decode_block(block, self.layout)
        self.assertEqual(result["0x920"]["values"], [.25, .5, .75, 1])
        self.assertEqual(result["0x930"]["values"], [123456789.5, -20, 30])
        self.assertEqual(result["0x108"]["values"], ["nan"])
        json.dumps(result, allow_nan=False)
        with self.assertRaises(ValueError):
            motion.decode_block(block[:-1], self.layout)

    def test_controlled_pawn_swap_stops_before_flight_read(self):
        reader, put, _, ticket = self.memory()
        put(ticket["controller"]+ticket["pc_pawn_offset"], struct.pack("<Q", 0x900000))
        with self.assertRaisesRegex(ValueError, "controlled pawn changed"):
            reader.sample(self.layout)

    def test_object_header_reuse_stops(self):
        reader, put, _, ticket = self.memory()
        put(ticket["pawn"]+12, struct.pack("<I", 200))
        with self.assertRaisesRegex(ValueError, "identity header changed"):
            reader.sample(self.layout)

    def test_swap_during_block_read_discards_sample(self):
        reader, put, read, ticket = self.memory()
        def swapping_read(address, size):
            result = read(address, size)
            if size == motion.EXTENT:
                put(ticket["pawn"]+ticket["plane_controller_offset"], struct.pack("<Q", 0x900000))
            return result
        reader.read = swapping_read
        with self.assertRaisesRegex(ValueError, "backlink changed"):
            reader.sample(self.layout)

    def test_layout_cannot_expand_native_read(self):
        self.layout["fields"][-1]["count"] = 4
        path = self.path / "bad.json"
        path.write_text(json.dumps(self.layout))
        with self.assertRaisesRegex(ValueError, "bounds"):
            motion.load_layout(path)

    def test_correct_identity_records_all_groups(self):
        reader, _, _, _ = self.memory()
        self.assertEqual(len(reader.sample(self.layout)), 16)

    def test_wrong_aircraft_vtable_stops(self):
        reader, put, _, ticket = self.memory()
        put(ticket["pawn"], struct.pack("<Q", 0x140000001))
        with self.assertRaisesRegex(ValueError, "vtable"):
            reader.sample(self.layout)


if __name__ == "__main__":
    unittest.main()
