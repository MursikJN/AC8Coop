"""Offline lifecycle checks only: these mocks cannot prove Unreal compatibility."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, r"D:\projects\unreal-mod-tools\packages\python-analysis")
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class ManualControlLifecycle(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / "tests/manual_control_fixture.lua").read_text(encoding="utf-8"))
        install = self.lua.execute((ROOT / "probe/AC8CoopRecon/Scripts/manual_control.lua").read_text(encoding="utf-8"))
        install("mock", "stamp")

    def run_lua(self, source):
        self.lua.execute(source)

    def test_no_game_state_writes_without_f7_and_exact_token(self):
        self.run_lua('''
            assert(#H.writes==0 and #H.cameras==0)
            H.press("F6"); assert(#H.writes==0)
            H.press("F7"); assert(#H.writes==0 and AC8ManualControl.active==nil)
            H.files["mock/manual-ready.txt"]="stale"
            H.press("F7"); assert(#H.writes==0)
            H.ready(); assert(#H.writes==0)
        ''')

    def test_take_and_f9_restore_original_fields_camera(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            assert(AC8ManualControl.active and H.components[1].AC8ManualEnable==0)
            for _,key in ipairs(H.gates) do assert(H.player[key]==false) end
            for _,key in ipairs(H.axes) do assert(H.player[key]==0) end
            assert(H.pc:GetViewTarget()==H.cameras[1])
            H.press("F9"); H.assert_restored()
        ''')

    def test_live_lowercase_pitch_conversion_keeps_chase_camera_aim(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            assert(AC8ManualControl.active,"take failed with live lowercase pitch conversion")
            local camera=AC8ManualControl.active.camera
            local forward=camera:GetActorForwardVector()
            local expected_z=-400/math.sqrt(2000*2000+400*400)
            assert(math.abs(forward.Z-expected_z)<1e-9,"camera lost pitch during reflected conversion")
            H.press("F9"); H.assert_restored()
        ''')

    def test_15_second_return(self):
        self.run_lua('''
            H.ready(); H.press("F7"); H.advance(14999)
            assert(AC8ManualControl.active)
            H.advance(1); H.assert_restored()
            local writes=#H.writes
            H.advance(1000); H.frame(); assert(#H.writes==writes)
        ''')

    def test_old_timer_cannot_end_new_acquisition(self):
        self.run_lua('''
            H.ready(); H.press("F7"); H.advance(1000); H.press("F9")
            H.press("F7"); local newer=AC8ManualControl.active
            H.advance(14000); assert(AC8ManualControl.active==newer)
            H.advance(1000); H.assert_restored()
        ''')

    def test_partial_restore_keeps_owner_and_allows_retry(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            H.fail("player","bEnableMovmentInput",true)
            H.press("F9")
            assert(AC8ManualControl.active and not AC8ManualControl.active.applying)
            assert(H.components[1].AC8ManualEnable==1)
            assert(H.pc:GetViewTarget()==H.view)
            local writes=#H.inputs; H.frame(); assert(#H.inputs==writes)
            H.press("F9"); H.assert_restored()
        ''')

    def test_camera_spawn_failure_restores(self):
        self.run_lua('H.ready(); H.spawn_failure=true; H.press("F7"); H.assert_restored()')

    def test_camera_orientation_failure_restores_and_destroys(self):
        self.run_lua('''
            H.ready(); H.orientation_failure=true; H.press("F7")
            H.assert_restored(); assert(H.destroyed==1)
        ''')

    def test_selection_releases_old_owner_before_next_take(self):
        self.run_lua('''
            H.ready(); H.press("F7"); H.press("F6"); H.assert_restored()
            assert(AC8ManualControl.selection==2)
            H.press("F7")
            assert(H.components[1].AC8ManualEnable==1 and H.components[2].AC8ManualEnable==0)
            H.press("F9"); H.assert_restored()
        ''')

    def test_keys_reach_target_and_no_writes_after_restore(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            H.keys.Up=true; H.keys.Right=true; H.keys.NumPadSix=true; H.frame()
            assert(#H.inputs==3)
            for _,input in ipairs(H.inputs) do assert(input.plane==H.planes[1] and input.power==0.25) end
            local queued=H.loops[1].fn
            H.press("F9"); H.assert_restored()
            local writes=#H.writes; local inputs=#H.inputs
            H.frame(); queued(); H.advance(16000)
            assert(#H.writes==writes and #H.inputs==inputs)
        ''')

    def test_escape_restores_without_steering(self):
        self.run_lua('''
            H.ready(); H.press("F7"); H.keys.Escape=true; H.frame()
            H.assert_restored(); assert(#H.inputs==0)
        ''')

    def test_gamepad_full_stick_reaches_target_and_restores(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            H.analog.Gamepad_LeftX=1; H.analog.Gamepad_LeftY=-1; H.frame()
            assert(#H.inputs==3)
            local axes={}
            for _,input in ipairs(H.inputs) do
                assert(input.plane==H.planes[1]); axes[input.axis]=input.power
            end
            assert(axes.Roll==1 and axes.Pitch==-1 and axes.Yaw==0)
            H.press("F9"); H.assert_restored()
            local count=#H.inputs; H.frame(); assert(#H.inputs==count)
        ''')

    def test_gamepad_partial_stick_matches_recorded_player_mapping(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            H.analog.Gamepad_LeftX=-0.575; H.analog.Gamepad_LeftY=0.575; H.frame()
            local axes={}; for _,input in ipairs(H.inputs) do axes[input.axis]=input.power end
            assert(math.abs(axes.Roll+0.575)<1e-9)
            assert(math.abs(axes.Pitch-0.575)<1e-9)
            H.press("F9"); H.assert_restored()
        ''')

    def test_gamepad_does_not_add_a_second_deadzone(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            for _,value in ipairs({0,0.1,-0.1,0.149,-0.149,0.15,-0.15}) do
                H.analog.Gamepad_LeftX=value; H.analog.Gamepad_LeftY=-value; H.frame()
                local axes={}; for _,input in ipairs(H.inputs) do axes[input.axis]=input.power end
                assert(axes.Roll==value and axes.Pitch==-value)
            end
            H.press("F9"); H.assert_restored()
        ''')

    def test_gamepad_dpad_shoulders_and_combination_caps(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            H.keys.Gamepad_DPad_Up=true; H.keys.Gamepad_DPad_Left=true
            H.keys.Gamepad_RightShoulder=true; H.frame()
            local axes={}; for _,input in ipairs(H.inputs) do axes[input.axis]=input.power end
            assert(axes.Pitch==0.25 and axes.Roll==-0.25 and axes.Yaw==0.25)
            H.keys.Up=true; H.keys.Left=true; H.keys.NumPadSix=true
            H.analog.Gamepad_LeftX=-1; H.analog.Gamepad_LeftY=1; H.frame()
            for _,input in ipairs(H.inputs) do axes[input.axis]=input.power end
            assert(axes.Pitch==1 and axes.Roll==-1 and axes.Yaw==0.25)
            H.keys.Gamepad_LeftShoulder=true; H.frame()
            assert(H.inputs[#H.inputs].axis=="Yaw" and H.inputs[#H.inputs].power==0)
            H.press("F9"); H.assert_restored()
        ''')

    def test_fire_permission_is_exclusive_and_restores_original_false(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            assert(H.planes[1].bPermissionToFire==false)
            assert(H.planes[3].bPermissionToFire==true)
            H.press("F6"); H.assert_restored()
            H.press("F7"); assert(H.planes[2].bPermissionToFire==false)
            H.press("F9"); H.assert_restored()
        ''')

    def test_fire_permission_restore_failure_retains_retry_owner(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            H.fail("Joker2","bPermissionToFire",true)
            H.press("F9"); assert(AC8ManualControl.active)
            assert(H.components[1].AC8ManualEnable==1)
            local count=#H.inputs; H.frame(); assert(#H.inputs==count)
            H.press("F9"); H.assert_restored()
        ''')

    def test_fire_permission_reenabled_by_game_aborts_manual_control(self):
        self.run_lua('''
            H.ready(); H.press("F7"); H.planes[1].bPermissionToFire=true
            H.frame(); H.assert_restored(); assert(#H.inputs==0)
        ''')

    def test_temporary_camera_copies_player_fov_without_changing_source(self):
        self.run_lua('''
            H.ready(); H.press("F7")
            assert(AC8ManualControl.active.camera.CameraComponent.FieldOfView==61.927513122559)
            assert(H.player.ThirdPersonCamera.FieldOfView==61.927513122559)
            H.press("F9"); H.assert_restored()
        ''')


if __name__ == "__main__":
    unittest.main(verbosity=2)
