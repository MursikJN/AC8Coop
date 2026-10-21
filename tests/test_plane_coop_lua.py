"""Real R7 Lua orchestration with a mocked native boundary; no Steam/game calls."""
import tempfile
import unittest
from pathlib import Path
from lupa import LuaRuntime
import test_plane_flight_lua as base
import test_plane_motion as motion
from test_plane_initialization import POSE_FIXTURE
ROOT=Path(__file__).resolve().parents[1]


class CoopLuaTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name);self.lua=LuaRuntime(unpack_returned_tuples=True)
        extra=base.EXTRA.replace('H.native.run=H.native.run+1','H.native.run=H.native.run+1')
        extra=extra.replace('assert(#H.delayed>0 and H.delayed[1].when==H.now+15000,"fallback must precede run")',
            'local watchdog=false;for _,x in ipairs(H.delayed) do if x.when==H.now+36000 then watchdog=true end end;assert(watchdog,"watchdog must precede arming")')
        extra=extra.replace('assert(name=="luaopen_ac8_flight_cleanup")', '''if name=="luaopen_ac8_coop_poll" then return function()
 H.polls=(H.polls or 0)+1;if H.poll_throws then error("network fixture fault") end
 end end
 assert(name=="luaopen_ac8_flight_cleanup")''')
        if getattr(self,'continuous',False):
            extra=extra.replace('H.now+36000','H.now+1000')
        fixture=motion.LUA_FIXTURE.replace('Class /Script/Live.LivePlayerPlaneF14D',
            'BlueprintGeneratedClass /Game/PP0023_f14d/BP_PlayerPlane_PP0023_f14d_C')
        self.lua.execute(fixture+POSE_FIXTURE+extra);self.lua.globals().H.dir=str(self.path).replace('\\','/')
        if getattr(self,'continuous',False):
            self.lua.execute('local old=os.getenv;os.getenv=function(k)if k=="AC8_COOP_CONTINUOUS"then return "25201480"end;return old(k)end;os.time=function()return math.floor(H.now/1000)end')
        self.probe=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/plane_coop_probe.lua').read_text())

    def stage(self,stamp='test'):self.probe(str(self.path).replace('\\','/'),stamp)

    def test_f8_only_starts_network_pump_and_never_arms_or_runs(self):
        self.stage();self.lua.execute('H.advance(100)')
        self.assertEqual(self.lua.eval('H.native.run'),0)
        self.assertEqual(self.lua.eval('H.polls'),5)
        self.assertFalse((self.path/'plane-flight-armed.txt').exists())

    def test_waiting_peer_is_kept_alive_then_native_status_stops(self):
        self.stage();self.lua.execute("H.run_status='waiting_peer';H.tick_status='waiting_peer';H.keys[7]();H.advance(1000)")
        self.assertTrue(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertEqual(self.lua.eval('H.native.cleanup'),0)
        self.lua.execute("H.tick_status='active';H.advance(100);H.tick_status='cleanup_pending';H.advance(100)")
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertEqual(self.lua.eval('H.native.cleanup'),1)

    def test_f9_stops_network_and_motion_without_player_lookup(self):
        self.stage();self.lua.execute('H.keys[7]();H.advance(100);H.pcprops.Pawn=nil;H.keys[9]()')
        before=self.lua.eval('H.polls');self.lua.execute('H.advance(100)')
        self.assertEqual(self.lua.eval('H.polls'),before)
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))

    def test_arming_refusal_does_not_keep_loop_active(self):
        self.stage();self.lua.execute("H.run_status='error';H.keys[7]();H.advance(100)")
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertEqual(self.lua.eval('H.native.cleanup'),1)

    def test_reload_after_arming_cannot_reallocate(self):
        self.stage();self.lua.execute('H.keys[7]();H.advance(50)');self.stage('second')
        self.lua.execute('H.keys[7]();H.advance(50)')
        self.assertEqual(self.lua.eval('H.native.run'),1)
        self.assertEqual(self.lua.eval('H.native.preflight'),1)

    def test_network_fault_requests_cleanup(self):
        self.stage();self.lua.execute('H.poll_throws=true;H.advance(100)')
        self.assertEqual(self.lua.eval('H.native.cleanup'),1)
        self.assertTrue(self.lua.eval('AC8PlaneFlightLifecycle.network_stopped'))

    def test_watchdog_precedes_arming_and_is_finite(self):
        self.stage();self.lua.execute("H.run_status='waiting_peer';H.tick_status='waiting_peer';H.keys[7]();H.advance(40000)")
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertEqual(self.lua.eval('H.native.cleanup'),3)



class ContinuousCoopLuaTests(unittest.TestCase):
    continuous=True
    setUp=CoopLuaTests.setUp
    stage=CoopLuaTests.stage
    def test_survives_old_time_and_callback_limits(self):
        self.stage();self.lua.execute('H.keys[7]();for i=1,80 do H.advance(1000)end')
        self.assertTrue(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertGreater(self.lua.eval('AC8PlaneFlightLifecycle.ticks'),4096)
        self.assertEqual(self.lua.eval('H.native.cleanup'),0)
    def test_f9_and_network_failure_still_stop(self):
        self.stage();self.lua.execute('H.keys[7]();H.advance(100);H.keys[9]();H.advance(4000)')
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertGreaterEqual(self.lua.eval('H.native.cleanup'),3)
    def test_stalled_motion_loop_triggers_watchdog(self):
        self.stage();self.lua.execute('H.keys[7]();H.advance(100);for i=#H.delayed,1,-1 do if H.delayed[i].fn==AC8PlaneFlightLifecycle.step then table.remove(H.delayed,i)end end;H.advance(7000)')
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertGreater(self.lua.eval('H.native.cleanup'),0)

if __name__=='__main__':unittest.main()
