"""Read bounds, identity and registry failure tests; no native flight validation."""
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import sample_plane_configuration as config
import test_plane_motion as fixture
from lupa import LuaRuntime


class Memory:
    def __init__(self):
        self.data = {}
        self.base = 0x140000000
        self.pawn, self.world, self.pc = 0x300000, 0x400000, 0x200000
        self.parts, self.activator, self.gi = 0x600000, 0x700000, 0x800000
        self.table, self.rows = 0x900000, 0xA00000
        self.metadata = 0x1100000
        self.component = 0x1200000
        self.weapon_component = 0x1300000
        self.chunk, self.chunk_array = 0xB00000, 0xC00000
        self.ticket = dict(pawn=self.pawn, world=self.world, controller=self.pc,
                           pawn_class=0x500000, pc_pawn_offset=0x300, plane_controller_offset=0x2C8)
        for address, size in ((self.pawn, 0x6000), (self.world, 0x200), (self.pc, 0x400),
                              (self.parts, 0x1A800), (self.activator, 0x600), (self.gi, 0xA00),
                              (self.table, 0x30), (self.rows, 0x448), (self.chunk, 24 * 32),
                              (self.metadata, 0x28), (self.component, 0x200),
                              (self.weapon_component, 0x200)):
            self.raw(address, bytes(size))
        array = self.base + 0xDC60CD0
        self.put(array + 0x10, 'Q', self.chunk_array)
        self.put(array + 0x24, 'i', 32)
        self.put(array + 0x2C, 'i', 1)
        self.put(self.chunk_array, 'Q', self.chunk)
        for i, address in enumerate((self.pawn, self.world, self.pc, self.parts, self.activator, self.gi, self.metadata, self.component)):
            self.put(address, 'Q', self.base + config.motion.F14D_VTABLE_RVA if i == 0 else self.base + 100)
            self.put(address + 12, 'i', i)
            self.put(address + 0x10, 'Q', 0x500000)
            self.put(address + 0x20, 'Q', self.pawn if i in (3, 4) else 0)
            self.put(self.chunk + i * 24, 'Q', address)
            self.put(self.chunk + i * 24 + 16, 'i', 90 + i)
        self.put(self.pc + 0x300, 'Q', self.pawn)
        self.put(self.pawn + 0x2C8, 'Q', self.pc)
        self.put(self.pawn + 0x1328, 'Q', self.parts)
        self.put(self.pawn + 0x16A8, 'Q', self.activator)
        self.put(self.pawn + 0x18D8, 'Q', self.component)
        self.put(self.component + 0x1C0, 'Q', self.pawn)
        self.put(self.activator + 0x2D0, 'Q', self.pawn)
        self.put(self.activator + 0x2E0, 'Q', self.weapon_component)
        self.put(self.weapon_component + 12, 'i', 9)
        self.put(self.chunk + 9 * 24, 'Q', self.weapon_component)
        self.put(self.chunk + 9 * 24 + 16, 'i', 99)
        self.put(self.pawn + 0x3AB0, 'Q', self.table)
        self.put(self.table + 0x18, 'Q', self.rows)
        self.put(self.table + 0x20, 'i', 1)
        self.put(self.world + 0x1D8, 'Q', self.gi)
        self.put(self.gi + 0x878, 'Q', self.metadata)
        for offset, mode in ((0x2268, 0), (0x3C60, 1)):
            self.put(self.pawn + offset + 0x860, 'Q', self.pawn + 0xF48)
            self.put(self.pawn + offset + 0x8B4, 'B', mode)

    def raw(self, address, data):
        self.data.update((address + i, b) for i, b in enumerate(data))

    def put(self, address, fmt, *values):
        self.raw(address, struct.pack('<' + fmt, *values))

    def read(self, address, size):
        if not 0 < size <= config.motion.EXTENT:
            raise ValueError('read bound')
        return bytes(self.data[address + i] for i in range(size))

    def probe(self):
        return config.ConfigurationReader(self.read, self.base, self.ticket)


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.m = Memory()

    def test_complete_read_is_nonmutating_and_both_models_recorded(self):
        before = dict(self.m.data)
        result = self.m.probe().capture()
        self.assertEqual(before, self.m.data)
        self.assertEqual(set(result['models']), {'0x2268', '0x3c60'})
        self.assertEqual(result['models']['0x2268']['configuration']['bytes'], 0x45C)
        self.assertEqual(result['network_registry']['result'], 'unavailable_no_native_cleanup_owner')
        self.assertIn('0x1140', result['plane_blocks'])
        self.assertNotIn('0x1340', result['plane_blocks'])

    def test_parts_count_is_rejected_before_reading_payload(self):
        self.m.put(self.m.parts + 0x30, 'Qii', 0xD00000, 17, 17)
        with self.assertRaisesRegex(ValueError, 'array bounds'):
            self.m.probe().capture()

    def test_invalid_table_index_never_uses_default_row(self):
        self.m.put(self.m.pawn + 0x3AB8, 'i', -1)
        with self.assertRaisesRegex(ValueError, 'row unavailable'):
            self.m.probe().capture()

    def test_foreign_parts_owner_rejected(self):
        self.m.put(self.m.parts + 0x20, 'Q', self.m.world)
        with self.assertRaisesRegex(ValueError, 'Outer'):
            self.m.probe().capture()

    def test_secondary_model_provider_rejected(self):
        self.m.put(self.m.pawn + 0x3C60 + 0x860, 'Q', self.m.world)
        with self.assertRaisesRegex(ValueError, 'provider mismatch'):
            self.m.probe().capture()

    def test_retirement_during_capture_detected_before_final_header_read(self):
        original = self.m.read
        def read(address, size):
            data = original(address, size)
            if address == self.m.activator + 0x158:
                self.m.put(self.m.chunk + 3 * 24 + 16, 'i', 999)
            return data
        probe = config.ConfigurationReader(read, self.m.base, self.m.ticket)
        with self.assertRaisesRegex(ValueError, 'retired'):
            probe.capture()

    def registry(self, cycle=False):
        owner, data = 0xE00000, 0xF00000
        self.m.raw(owner, bytes(0x400))
        self.m.put(owner + 12, 'i', 8)
        self.m.put(self.m.chunk + 8 * 24, 'Q', owner)
        self.m.put(self.m.chunk + 8 * 24 + 16, 'i', 98)
        self.m.raw(owner + 0x2E0, bytes(0x50))
        self.m.put(self.m.gi + 0x910, 'Q', owner)
        self.m.put(owner + 0x2E0, 'Qii', data, 1, 1)
        self.m.put(owner + 0x2E0 + 0x48, 'i', 1)
        self.m.raw(data, bytes(24))
        self.m.put(data, 'Qiii', 0x434F4F5000000001, 17, 99, 0 if cycle else -1)
        return owner

    def test_registry_collision_recorded_not_reserved(self):
        self.registry()
        r = self.m.probe().capture()['network_registry']
        self.assertTrue(r['candidates'][0]['present'])
        self.assertFalse(r['candidates'][1]['present'])

    def test_registry_cycle_reported_without_losing_configuration(self):
        self.registry(cycle=True)
        r = self.m.probe().capture()
        self.assertEqual(r['network_registry']['result'], 'unverified')
        self.assertIn('chain', r['network_registry']['error'])
        self.assertIn('models', r)

    def test_array_descriptor_mutation_rejected(self):
        probe = self.m.probe()
        self.m.put(self.m.parts + 0x30, 'Qii', 0xD00000, 1, 1)
        self.m.put(0xD00000, 'i', 123)
        original = probe.read
        def read(address, size):
            data = original(address, size)
            if address == 0xD00000:
                self.m.put(self.m.parts + 0x38, 'i', 0)
            return data
        probe.read = read
        with self.assertRaisesRegex(ValueError, 'array changed'):
            probe.capture()

    def test_zero_serial_is_reported_not_allocated(self):
        self.m.put(self.m.chunk + 3 * 24 + 16, 'i', 0)
        self.assertEqual(self.m.probe().capture()['upgrade_parts']['serial'], 0)

    def test_missing_metadata_not_claimed_complete(self):
        self.m.put(self.m.gi + 0x878, 'Q', 0)
        with self.assertRaisesRegex(ValueError, 'invalid aligned pointer'):
            self.m.probe().capture()


class ConfigurationLuaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(fixture.LUA_FIXTURE)
        self.probe = self.lua.execute((ROOT / 'probe/AC8CoopRecon/Scripts/plane_configuration_probe.lua').read_text())

    def test_ticket_reads_only_no_keys_no_maneuvers(self):
        self.probe(str(self.path), 'test')
        ticket = config.motion.parse_ticket(self.path / 'configuration-ticket-test.tsv',
                                           time.time() - 10, time.time() - 10, time.time())
        self.assertEqual(ticket['pawn'], 0x300000)

    def test_cinematic_or_wrong_mission_has_no_ticket(self):
        for expr in ('H.props.bIsIGCActor=true', "H.worldname='World Menu'"):
            self.lua.execute(fixture.LUA_FIXTURE)
            self.lua.execute(expr)
            with self.assertRaises(Exception):
                self.probe(str(self.path), 'blocked')
            self.assertFalse((self.path / 'configuration-ticket-blocked.tsv').exists())


if __name__ == '__main__':
    unittest.main()
