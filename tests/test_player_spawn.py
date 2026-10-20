"""Check ownership and failure handling; cannot prove native constructor safety."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, r"D:\projects\unreal-mod-tools\packages\python-analysis")
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class DeferredSpawnLifecycle(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        for path in ("tests/manual_control_fixture.lua", "tests/player_spawn_fixture.lua"):
            self.lua.execute((ROOT / path).read_text(encoding="utf-8"))
        self.install = self.lua.execute((ROOT / "probe/AC8CoopRecon/Scripts/player_spawn_probe.lua").read_text(encoding="utf-8"))

    def run_lua(self, code):
        self.lua.execute(code)

    def test_no_allocation_until_exact_token_and_f7(self):
        self.install("mock", "stamp")
        self.run_lua('''
            assert(H.spawn_calls==nil)
            H.press("F7"); assert(H.spawn_calls==nil)
            H.files["mock/spawn-ready.txt"]="old"; H.press("F7"); assert(H.spawn_calls==nil)
            H.spawn_ready(); assert(H.spawn_calls==nil)
        ''')

    def test_poisoned_cached_components_are_never_read(self):
        self.run_lua('H.poison_cached_components()')
        self.install("mock", "stamp")
        self.run_lua('''
            H.spawn_ready(); H.press("F7")
            assert(H.stale_accesses==0,"old component was dereferenced")
            assert(H.spawn_calls==1 and H.destroyed==1)
        ''')

    def test_owned_destroy_and_one_attempt_no_original_mutation(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.spawn_ready(); H.press("F7")
            assert(H.spawn_calls==1 and H.destroyed==1 and AC8PlayerSpawnProbe.owned==nil)
            H.press("F7"); H.advance(4000)
            assert(H.spawn_calls==1 and H.destroyed==1 and #H.writes==0)
        ''')

    def test_entire_old_context_is_not_dereferenced(self):
        self.run_lua('''
            local poison=setmetatable({}, {__index=function() H.stale_accesses=H.stale_accesses+1; error("old context") end,
                __pairs=function() H.stale_accesses=H.stale_accesses+1; error("old slots") end})
            AC8ManualControl.slots=poison; AC8ManualControl.pc=poison; AC8ManualControl.player=poison
        ''')
        self.install("mock", "stamp")
        self.run_lua('H.spawn_ready(); H.press("F7"); H.advance(4000); assert(H.stale_accesses==0 and H.spawn_calls==1 and H.destroyed==1)')

    def test_changed_component_blocks_before_custom_read_and_transform(self):
        self.install("mock", "stamp")
        self.run_lua('''
            local fresh=H.object("replacement_AI", {Owner=H.planes[1]})
            local mt=getmetatable(fresh); local index=mt.__index
            mt.__index=function(o,k)
                if k=="AC8ManualEnable" then H.stale_accesses=H.stale_accesses+1; error("premature custom read") end
                return index(o,k)
            end
            H.planes[1].AIStateComponent=fresh
            H.spawn_ready(); H.press("F7")
            assert(H.spawn_calls==nil and H.transform==nil and H.stale_accesses==0)
        ''')

    def test_missing_duplicate_wrong_callsign_and_owner_block(self):
        cases = [
            'H.planes[3]=nil',
            'H.planes[4]=H.planes[1]',
            'H.planes[1].CallsignId=FName("unexpected")',
            'H.components[1].Owner=H.planes[2]',
            'H.planes[1].bIsActivated=false',
            'H.planes[1].bIsIGCActor=true',
        ]
        for case in cases:
            with self.subTest(case=case):
                self.setUp()
                self.install("mock", "stamp")
                self.run_lua(case + '; H.spawn_ready(); H.press("F7"); assert(H.spawn_calls==nil and H.transform==nil)')

    def test_replaced_plane_blocks_before_allocation(self):
        self.install("mock", "stamp")
        self.run_lua('''
            local replacement=H.object("replacement_plane", {
                bIsActivated=true,bIsIGCActor=false,bIsAnimationPlane=false,
                ObjNameID=H.planes[1].ObjNameID,CallsignId=H.planes[1].CallsignId,
            })
            replacement.AIStateComponent=H.object("replacement_AI",{Owner=replacement,AC8ManualEnable=1})
            H.planes[1]=replacement; H.poison_cached_components()
            H.spawn_ready(); H.press("F7")
            assert(H.stale_accesses==0 and H.spawn_calls==nil and H.transform==nil)
        ''')

    def test_delayed_baseline_does_not_read_old_components(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.spawn_ready(); H.press("F7"); H.poison_cached_components()
            H.planes[1].AIStateComponent=H.object("new_AI",{Owner=H.planes[1],AC8ManualEnable=1})
            H.advance(4000)
            assert(H.stale_accesses==0 and H.spawn_calls==1 and H.destroyed==1)
            assert(H.files["mock/player-spawn-stamp.tsv"]:find("Current object changed",1,true))
        ''')

    def test_owned_stale_handle_never_dereferenced_after_delayed_removal(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.destroy_pending=true; H.spawn_ready(); H.press("F7")
            local poison=setmetatable({}, {__index=function() H.stale_accesses=H.stale_accesses+1; error("stale owned") end})
            AC8PlayerSpawnProbe.owned=poison; H.spawned={}
            H.advance(4000); H.press("F9")
            assert(H.stale_accesses==0 and H.destroyed==1)
            assert(AC8PlayerSpawnProbe.owned~=nil)
            assert(H.files["mock/player-spawn-stamp.tsv"]:find("cleanup quarantined",1,true))
        ''')

    def test_inspection_failure_still_destroys_owned_actor(self):
        self.install("mock", "stamp")
        self.run_lua('H.bad_controller=true; H.spawn_ready(); H.press("F7"); assert(H.destroyed==1 and AC8PlayerSpawnProbe.owned==nil)')

    def test_failed_destroy_retains_handle_for_f9(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.destroy_fails=true; H.spawn_ready(); H.press("F7")
            assert(AC8PlayerSpawnProbe.owned and H.destroyed==0)
            H.destroy_fails=false; H.press("F9")
            assert(AC8PlayerSpawnProbe.owned==nil and H.destroyed==1)
        ''')

    def test_failed_destroy_retried_by_watchdog(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.destroy_fails=true; H.spawn_ready(); H.press("F7")
            H.destroy_fails=false; H.advance(1000)
            assert(AC8PlayerSpawnProbe.owned==nil and H.destroyed==1)
        ''')

    def test_destroy_mark_is_not_reported_as_removal_or_abandoned_on_reload(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.destroy_pending=true; H.spawn_ready(); H.press("F7"); H.advance(4000)
            assert(AC8PlayerSpawnProbe.owned~=nil and H.destroyed==1)
            assert(not H.files["mock/player-spawn-stamp.tsv"]:find("removed",1,true))
        ''')
        with self.assertRaisesRegex(Exception, "Previous cleanup still pending"):
            self.install("mock", "new")
        self.run_lua('assert(not AC8PlayerSpawnProbe.retired)')

    def test_original_player_is_never_destroyed_on_wrong_return(self):
        self.install("mock", "stamp")
        self.run_lua('H.return_actor=H.player; H.spawn_ready(); H.press("F7"); assert(H.destroyed==0 and H.player:IsValid() and #H.writes==0)')

    def test_wingman_is_never_destroyed_on_wrong_return(self):
        self.install("mock", "stamp")
        self.run_lua('H.return_actor=H.planes[1]; H.spawn_ready(); H.press("F7"); assert(H.destroyed==0 and H.planes[1]:IsValid())')

    def test_world_drift_blocks_allocation(self):
        self.install("mock", "stamp")
        self.run_lua('AC8ManualControl.world_id=0; H.spawn_ready(); H.press("F7"); assert(H.spawn_calls==nil)')

    def test_pawn_drift_blocks_allocation(self):
        self.install("mock", "stamp")
        self.run_lua('H.pc.Pawn=H.planes[1]; H.spawn_ready(); H.press("F7"); assert(H.spawn_calls==nil)')

    def test_incompatible_parameter_order_blocks_installation(self):
        self.run_lua('local s=H.signatures.BeginDeferredActorSpawnFromClass; s[1],s[2]=s[2],s[1]')
        with self.assertRaisesRegex(Exception, "Unexpected spawn argument order"):
            self.install("mock", "stamp")

    def test_unknown_parameter_blocks_installation(self):
        self.run_lua('H.signatures.BeginDeferredActorSpawnFromClass[8]={"Unknown","IntProperty"}')
        with self.assertRaisesRegex(Exception, "Unexpected parameter"):
            self.install("mock", "stamp")

    def test_logging_failure_does_not_prevent_cleanup(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.spawn_ready()
            local open=io.open
            io.open=function(path,mode) if mode=="a" then error("disk unavailable") end; return open(path,mode) end
            H.bad_controller=true; H.press("F7")
            assert(H.destroyed==1 and AC8PlayerSpawnProbe.owned==nil)
        ''')

    def test_inspection_file_failure_still_cleans_up(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.spawn_ready()
            local open=io.open
            io.open=function(path,mode) if mode=="w" then return nil end; return open(path,mode) end
            H.press("F7"); assert(H.destroyed==1 and AC8PlayerSpawnProbe.owned==nil)
        ''')

    def test_wrong_nested_struct_blocks_installation(self):
        self.run_lua('H.wrong_struct="Wrong"')
        with self.assertRaisesRegex(Exception, "Unexpected struct"):
            self.install("mock", "stamp")

    def test_nonfinite_location_blocks_allocation(self):
        self.install("mock", "stamp")
        self.run_lua('''
            H.player.K2_GetActorLocation=function() return {X=math.huge,Y=2,Z=3} end
            H.spawn_ready(); H.press("F7"); assert(H.spawn_calls==nil)
        ''')


if __name__ == "__main__":
    unittest.main(verbosity=2)
