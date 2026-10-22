"""R30 wire/render boundaries only. Mock engine; never launch the game."""
import struct
import unittest
from lupa import LuaRuntime
import test_scene_engine as scene_tests
SOURCE = scene_tests.SOURCE


def owner_packet():
    b = bytearray(392)
    struct.pack_into('<4sHHII6Q6I', b, 0, b'AC8P', 3, 392, 25201480, 5,
                     2, 20, 10, 1, 7, 1000000, 1, 7, 1, 23, 0, 1)
    struct.pack_into('<IIdddfffffffI', b, 104,
                     1, 23, 100., 200., 300., 0., 0., 0., 1., 100., 0., 0., 0)
    struct.pack_into('<ddd', b, 368, 100., 0., 0.)
    return bytes(b)


class OwnerWireTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
        self.view = self.lua.execute((SOURCE/'guest_pilot_view.lua').read_bytes())

    def test_pose_velocity_and_no_damage(self):
        frame = self.view.owner(owner_packet())
        self.assertEqual(frame[b'pose'][b'position'][2], 200.)
        self.assertEqual(frame[b'velocity'][1], 100.)
        self.assertIsNone(frame[b'pose'][b'health'])

    def test_wrong_role_damage_axes_reserved_and_legacy_rejected(self):
        for offset, fmt, value in ((4, '<H', 2), (88, '<h', 1), (98, '<B', 1),
                                   (104, '<I', 0), (156, '<f', 100.),
                                   (168, '<I', 1), (368, '<d', float('nan'))):
            with self.subTest(offset=offset):
                bad = bytearray(owner_packet())
                struct.pack_into(fmt, bad, offset, value)
                with self.assertRaises(Exception):
                    self.view.owner(bytes(bad))
        with self.assertRaises(Exception):
            self.view.parse(owner_packet())


class OwnerSceneTests(unittest.TestCase):
    def setUp(self):
        self.fixture = scene_tests.EngineTests()
        self.fixture.setUp()
        self.lua = self.fixture.lua
        self.engine = self.fixture.engine
        self.lua.globals().E = self.engine
        self.engine.accept(self.fixture.wire(self.fixture.frame()), 100, True)
        self.engine.pump(10)
        self.engine.render(100)
        self.engine.activate(100)
        self.lua.execute("""
            F={generation=1,revision=1,sequence=1,pose={role=1,aircraft=23,
              position={900,0,0},rotation={0,0,0,1},speed=100}}
            H.context.generation=1;H.context.revision=1
        """)

    def enable_backend(self):
        self.lua.execute('H.context.preview=false;H.context.isolated_world_verified=true;H.context.local_owner_verified=true')

    def test_no_owner_override_from_preview_or_unverified_context(self):
        self.lua.execute('assert(not E.set_owner_pose(F));H.context.local_owner_verified=true;assert(not E.set_owner_pose(F))')
        self.assertIsNone(self.engine.owner_pose)

    def test_local_pose_is_immediate_and_host_echo_cannot_rewind_it(self):
        self.enable_backend()
        self.lua.execute('assert(E.set_owner_pose(F));assert(E.entities[2].position[1]==900 and E.entities[2].health==200);F.pose.position[1]=123')
        self.assertEqual(self.engine.owner_pose.position[1], 900)
        f = self.fixture.frame(2)
        f['entities'][1]['position'][0] = 500
        f['entities'][1]['health'] = 50
        self.engine.accept(self.fixture.wire(f), 300, False)
        self.engine.render(400)
        self.assertEqual(self.engine.guest_pose.position[1], 900)
        self.assertEqual(self.engine.guest_pose.health, 50)
        self.assertEqual(self.engine.entities[1].position[1], 100)
        self.lua.execute('assert(not E.set_owner_pose(F));F.sequence=2;F.generation=2;assert(not E.set_owner_pose(F))')

    def test_host_death_and_teardown_revoke_local_pose(self):
        self.enable_backend()
        self.lua.execute('assert(E.set_owner_pose(F))')
        f = self.fixture.frame(2)
        f['entities'][1]['alive'] = False
        f['entities'][1]['health'] = 0
        self.engine.accept(self.fixture.wire(f), 300, False)
        self.engine.render(400)
        self.assertIsNone(self.engine.owner_pose)
        self.lua.execute('F.sequence=2;assert(not E.set_owner_pose(F))')
        self.engine.stop('test')
        self.assertIsNone(self.engine.owner_sequence)

    def test_host_despawn_revokes_owner_camera_source(self):
        self.enable_backend()
        self.lua.execute('assert(E.set_owner_pose(F))')
        self.engine.accept(self.fixture.wire(self.fixture.frame(2, ids=(1,))), 300, False)
        self.assertIsNone(self.engine.owner_pose)
        self.assertIsNone(self.engine.guest_pose)
        self.assertEqual(self.fixture.value('H.destroyed'), 1)


if __name__ == '__main__':
    unittest.main()
