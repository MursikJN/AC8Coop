"""Front-end safety seams with a fake DLL; no engine spawn/lifecycle simulation."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
import test_plane_motion as motion_fixture
from test_plane_initialization import POSE_FIXTURE
sys.path.insert(0, r"D:\projects\unreal-mod-tools\packages\python-analysis")
from lupa import LuaRuntime

EXTRA = r'''
H.keys={};H.delayed={};H.native={preflight=0,run=0,verify=0}
Key={F7=7,F9=9}
RegisterKeyBind=function(key,fn) assert(not H.keys[key],"duplicate key");H.keys[key]=fn end
ExecuteInGameThread=function(fn) fn() end
ExecuteInGameThreadWithDelay=function(ms,fn) H.delayed[#H.delayed+1]=fn end
os.getenv=function(key)
 if key=="AC8_COOP_PLANE_STAGING" then return H.marker or "25201480" end
 if key=="AC8_COOP_PLANE_STAGING_DLL" then return "mock.dll" end
end
local function status(kind,stamp)
 local f=assert(io.open(H.dir.."/plane-staging-status.tsv","w"))
 f:write("status\t",kind,"\nstamp\t",stamp or "test","\nreason\tfixture\n");f:close()
end
package.loadlib=function(_,name)
 if name=="luaopen_ac8_plane_preflight" then return function()
  H.native.preflight=H.native.preflight+1
  local f=assert(io.open(H.dir.."/plane-staging-request.tsv","r"));local text=f:read("*a");f:close()
  assert(text:find("format\tac8-plane-staging-v1",1,true))
  local stamp=text:match("stamp\t([^\n]+)")
  status(H.refuse and "error" or "ready",stamp)
 end end
 if name=="luaopen_ac8_plane_run" then return function()
  H.native.run=H.native.run+1;status("cleanup_pending")
 end end
 assert(name=="luaopen_ac8_plane_verify")
 return function() H.native.verify=H.native.verify+1;status("retired") end
end
'''


class PlaneStagingLuaTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        fixture=motion_fixture.LUA_FIXTURE.replace("Class /Script/Live.LivePlayerPlaneF14D",
                      "BlueprintGeneratedClass /Game/PP0023_f14d/BP_PlayerPlane_PP0023_f14d_C")
        self.lua.execute(fixture+POSE_FIXTURE+EXTRA)
        self.lua.globals().H.dir=str(self.path).replace("\\","/")
        self.probe=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/plane_staging_probe.lua').read_text())

    def stage(self,stamp="test"):
        self.probe(str(self.path).replace("\\","/"),stamp)

    def test_f8_only_stages_no_run_and_writes_fresh_baseline(self):
        self.stage()
        self.assertEqual(self.lua.eval("H.native.preflight"),1)
        self.assertEqual(self.lua.eval("H.native.run"),0)
        text=(self.path/'plane-staging-request.tsv').read_text()
        self.assertIn("pawn\t0x300000\n",text)
        self.assertIn("plane_class\t0x500000\n",text)
        self.assertIn("rotation_pitch\t10\n",text)
        self.assertEqual(len(text.splitlines()),15)
        self.assertFalse((self.path/'plane-staging-armed.txt').exists())

    def test_changed_world_blocks_run_before_native_call(self):
        self.stage();self.lua.execute("H.worldname='World MainMenu';H.keys[7]()")
        self.assertEqual(self.lua.eval("H.native.run"),0)

    def test_one_attempt_cleanup_works_even_when_local_pawn_is_gone(self):
        self.stage();self.lua.execute("H.keys[7]();H.keys[7]()")
        self.assertEqual(self.lua.eval("H.native.run"),1)
        self.lua.execute("H.pcprops.Pawn=nil;H.keys[9]();for _,fn in ipairs(H.delayed) do fn() end")
        self.assertEqual(self.lua.eval("H.native.verify"),4)
        self.stage("reload")
        self.assertEqual(self.lua.eval("H.native.run"),1)
        self.assertEqual(self.lua.eval("H.native.preflight"),1)

    def test_restage_does_not_accumulate_key_handlers_or_keep_old_stamp(self):
        self.stage("first");self.stage("second")
        self.assertEqual(self.lua.eval("AC8PlaneStagingLifecycle.stamp"),"second")
        self.lua.execute("H.keys[7]()")
        self.assertEqual(self.lua.eval("H.native.run"),1)
        self.assertIn("stamp\tsecond\n",(self.path/'plane-staging-request.tsv').read_text())

    def test_failed_native_preflight_disables_run(self):
        self.lua.execute("H.refuse=true")
        self.stage();self.lua.execute("H.keys[7]()")
        self.assertEqual(self.lua.eval("H.native.run"),0)

    def test_wrong_launcher_or_oversize_stamp_never_reaches_preflight(self):
        self.lua.execute("H.marker='other'")
        with self.assertRaises(Exception): self.stage()
        self.lua.execute("H.marker=nil")
        with self.assertRaises(Exception): self.stage("a" * 65)
        self.assertEqual(self.lua.eval("H.native.preflight"),0)

    def test_wrong_aircraft_cannot_reach_native_preflight(self):
        self.lua.execute('H.plane:GetClass().GetFullName=function() return "Class OtherPlane" end')
        with self.assertRaises(Exception): self.stage()
        self.assertEqual(self.lua.eval("H.native.preflight"),0)

    def test_missing_lowercase_pitch_and_nonfinite_pose_block_before_native(self):
        for expr in ('H.props.K2_GetActorRotation=function() return {Pitch=10,Yaw=20,Roll=30} end',
                     'H.props.K2_GetActorRotation=function() return {pitch=0/0,Yaw=20,Roll=30} end'):
            self.lua.execute(expr)
            with self.assertRaises(Exception): self.stage()
        self.assertEqual(self.lua.eval("H.native.preflight"),0)


if __name__=='__main__': unittest.main()
