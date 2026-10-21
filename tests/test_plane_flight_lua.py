"""Scheduling/cleanup seam tests with a fake DLL; no proof of engine flight behavior."""
from pathlib import Path
import tempfile
import unittest
import test_plane_motion as motion_fixture
from test_plane_initialization import POSE_FIXTURE
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
EXTRA = r'''
H.keys={};H.delayed={};H.requested_delays={};H.now=0;H.native={preflight=0,run=0,tick=0,cleanup=0}
Key={F7=7,F9=9}
RegisterKeyBind=function(key,fn) assert(not H.keys[key],"duplicate key");H.keys[key]=fn end
ExecuteInGameThread=function(fn) fn() end
ExecuteInGameThreadWithDelay=function(ms,fn)
 H.requested_delays[#H.requested_delays+1]=ms
 if ms==1 then ms=H.frame_ms or 16 end -- an engine callback runs at most once per frame
 H.delayed[#H.delayed+1]={when=H.now+ms,fn=fn}
end
H.advance=function(ms)
 local limit=H.now+ms;local count=0
 while true do
  local index,earliest=nil,limit+1
  for i,entry in ipairs(H.delayed) do if entry.when<earliest then index=i;earliest=entry.when end end
  if not index then break end
  local entry=table.remove(H.delayed,index);H.now=entry.when;entry.fn();count=count+1
  assert(count<10000,"callback runaway")
 end
 H.now=limit
end
os.getenv=function(key) if key=="AC8_COOP_RECON" then return H.marker or "1" elseif key=="AC8_COOP_PLANE_FLIGHT_DLL" then return "test-r5.dll" end end
H.status=function(kind,stamp)
 local f=assert(io.open(H.dir.."/plane-flight-status.tsv","w"))
 f:write("status\t",kind,"\nstamp\t",stamp or "test","\nreason\tfixture\n");f:close()
end
package.loadlib=function(_,name)
 if name=="luaopen_ac8_flight_preflight" then return function()
  H.native.preflight=H.native.preflight+1
  local f=assert(io.open(H.dir.."/plane-flight-request.tsv","r"));local text=f:read("*a");f:close()
  assert(text:find("format\tac8-plane-flight-v1",1,true))
  H.status(H.refuse and "error" or "ready",text:match("stamp\t([^\n]+)"))
 end end
 if name=="luaopen_ac8_flight_run" then return function()
  assert(#H.delayed>0 and H.delayed[1].when==H.now+15000,"fallback must precede run")
  H.native.run=H.native.run+1
  if H.run_throws then error("run fixture failure") end
  H.status(H.run_status or "active")
 end end
 if name=="luaopen_ac8_flight_tick" then return function()
  H.native.tick=H.native.tick+1
  if H.tick_throws then error("tick fixture failure") end
  H.status(H.tick_status or "active")
 end end
 assert(name=="luaopen_ac8_flight_cleanup")
 return function()
  assert(not AC8PlaneFlightLifecycle.active,"producer still active during cleanup")
  H.native.cleanup=H.native.cleanup+1
  if H.cleanup_throws then error("cleanup fixture failure") end
  H.status(H.cleanup_status or "retired")
 end
end
'''


class FlightLuaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        fixture = motion_fixture.LUA_FIXTURE.replace('Class /Script/Live.LivePlayerPlaneF14D',
            'BlueprintGeneratedClass /Game/PP0023_f14d/BP_PlayerPlane_PP0023_f14d_C')
        self.lua.execute(fixture + POSE_FIXTURE + EXTRA)
        self.lua.globals().H.dir = str(self.path).replace('\\', '/')
        self.probe = self.lua.execute((ROOT / 'probe/AC8CoopRecon/Scripts/plane_flight_probe.lua').read_text())

    def stage(self, stamp='test'):
        self.probe(str(self.path).replace('\\', '/'), stamp)

    def test_f8_never_runs_or_arms(self):
        self.stage()
        self.assertEqual(self.lua.eval('H.native.run'), 0)
        self.assertEqual(self.lua.eval('#H.delayed'), 0)
        self.assertFalse((self.path / 'plane-flight-armed.txt').exists())

    def test_f9_stops_producer_without_player_lookup(self):
        self.stage(); self.lua.execute('H.keys[7]();H.advance(100);H.pcprops.Pawn=nil;H.keys[9]();H.advance(100)')
        self.assertEqual(self.lua.eval('H.native.tick'), 6)
        self.assertEqual(self.lua.eval('H.native.cleanup'), 1)

    def test_timeout_is_bounded_and_precedes_run(self):
        self.stage(); self.lua.execute('H.keys[7]();H.advance(20000)')
        self.assertGreaterEqual(self.lua.eval('H.native.tick'), 800)
        self.assertLessEqual(self.lua.eval('H.native.tick'), 1000)
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertEqual(self.lua.eval('H.native.cleanup'), 3)

    def test_run_exception_requests_cleanup_and_preserves_fallback(self):
        self.stage(); self.lua.execute('H.run_throws=true;H.keys[7]();H.advance(15000)')
        self.assertEqual(self.lua.eval('H.native.run'), 1)
        self.assertEqual(self.lua.eval('H.native.tick'), 0)
        self.assertEqual(self.lua.eval('H.native.cleanup'), 2)

    def test_tick_exception_stops_even_if_cleanup_throws(self):
        self.stage(); self.lua.execute('H.keys[7]();H.tick_throws=true;H.cleanup_throws=true;H.advance(1000)')
        self.assertEqual(self.lua.eval('H.native.tick'), 1)
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))

    def test_native_quarantine_never_schedules_movement(self):
        self.stage(); self.lua.execute("H.run_status='quarantine';H.cleanup_status='quarantine';H.keys[7]();H.advance(20000)")
        self.assertEqual(self.lua.eval('H.native.tick'), 0)

    def test_reload_after_run_stops_and_cannot_reallocate(self):
        self.stage(); self.lua.execute('H.keys[7]();H.advance(50)')
        self.stage('second'); self.lua.execute('H.keys[7]();H.advance(100)')
        self.assertEqual(self.lua.eval('H.native.run'), 1)
        self.assertEqual(self.lua.eval('H.native.tick'), 3)
        self.assertEqual(self.lua.eval('H.native.preflight'), 1)

    def test_rejected_preflight_or_changed_world_never_runs(self):
        self.lua.execute('H.refuse=true'); self.stage(); self.lua.execute('H.keys[7]()')
        self.assertEqual(self.lua.eval('H.native.run'), 0)
        self.lua.execute('H.refuse=false'); self.stage('next')
        self.lua.execute("H.worldname='World MainMenu';H.keys[7]()")
        self.assertEqual(self.lua.eval('H.native.run'), 0)

    def test_restage_keeps_one_handler_and_current_stamp(self):
        self.stage('first'); self.stage('second'); self.lua.execute('H.keys[7]()')
        self.assertEqual(self.lua.eval('H.native.run'), 1)
        self.assertIn('stamp\tsecond', (self.path / 'plane-flight-request.tsv').read_text())

    def test_native_tick_failure_stops_immediately(self):
        self.stage(); self.lua.execute("H.keys[7]();H.tick_status='error';H.advance(1000)")
        self.assertEqual(self.lua.eval('H.native.tick'), 1)
        self.assertEqual(self.lua.eval('H.native.cleanup'), 1)

    def test_next_frame_cadence_uses_positive_delay_and_retains_fallback(self):
        self.stage(); self.lua.execute('H.keys[7]()')
        self.assertEqual(self.lua.eval('H.requested_delays[1]'), 15000)
        self.assertEqual(self.lua.eval('H.requested_delays[2]'), 1)
        self.assertTrue(self.lua.eval('H.delayed[1].when==15000'))

    def test_high_frame_rate_reaches_absolute_deadline(self):
        self.stage(); self.lua.execute('H.frame_ms=4;H.keys[7]();H.advance(20000)')
        self.assertGreater(self.lua.eval('H.native.tick'), 3000)
        self.assertLess(self.lua.eval('H.native.tick'), 4096)
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertEqual(self.lua.eval('H.native.cleanup'), 3)

    def test_pathological_scheduler_hits_callback_cap_and_stops(self):
        self.stage(); self.lua.execute('H.frame_ms=1;H.keys[7]();H.advance(10000)')
        self.assertEqual(self.lua.eval('H.native.tick'), 4096)
        self.assertFalse(self.lua.eval('AC8PlaneFlightLifecycle.active'))
        self.assertEqual(self.lua.eval('H.native.cleanup'), 1)


if __name__ == '__main__': unittest.main()
