"""Recovery UI authority and input ownership, using stock-widget stand-ins."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
from test_coop_main_menu import FIXTURE
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts/session_recovery_ui.lua'
class SessionRecoveryUITests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(FIXTURE)
  self.l.execute('''
   H.main.RootPanel=H.canvas;H.main.AddToViewport=function()H.viewport=true end
   H.canvas.GetChildrenCount=function()return #H.canvas.children end
   H.pc.GetWorld=function()return {}end;H.pc.GetAddress=function()return 1 end
   H.library.Create=function()return H.main end
   local original=StaticFindObject;StaticFindObject=function(path)if path=='/Script/Engine.Default__GameplayStatics'then return {IsGamePaused=function()return H.paused end}end;return original(path)end
   LoadAsset=function()return {IsValid=function()return true end}end
   V={phase=5,session_policy=true,can_cancel=true,can_restart=false,can_quit=true};C={role='host',snapshot={cinema_state='2'}}
   C.view=function()return V end;C.status=function()return 'current state'end
   C.cancel=function()H.cancels=(H.cancels or 0)+1 end;C.restart=function()H.restarts=(H.restarts or 0)+1 end;C.lifecycle={quit=function()H.quits=(H.quits or 0)+1 end}
  ''')
  self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'));self.l.execute('R=M.new(C,function()end)')
 def test_no_controls_or_input_capture_during_ordinary_flight(self):
  self.l.execute("V.phase=6;H.paused=false;R.update();assert(not H.viewport and H.mode=='original')")
 def test_cancel_remains_clickable_while_an_ordinary_command_is_pending(self):
  self.l.execute("V.pending=true;R.update();H.hover.AC8_Recovery_Cancel=true;AC8MainMenuClickSerial=1;R.update();assert(H.cancels==1)")
 def test_host_can_restart_paused_flight_and_guest_cannot(self):
  self.l.execute("V.phase=6;V.can_cancel=false;V.can_restart=true;H.paused=true;R.update();assert(H.created.AC8_Recovery_Restart.bIsEnabled and H.mode=='game_and_ui');C.role='guest';V.can_restart=false;R.update();assert(R.widget.Visibility==1)")
 def test_manual_hangar_does_not_take_over_native_input(self):
  self.l.execute("V.phase=3;R.update();assert(H.mode=='original'and H.created.AC8_Recovery_Status.Visibility==1 and H.created.AC8_Recovery_Quit.Visibility==1)")
 def test_leaving_wait_restores_input_and_cursor(self):
  self.l.execute("R.update();assert(H.mode=='ui_only'and H.pc.bShowMouseCursor);V.phase=6;R.update();assert(H.mode=='game_and_ui'and not H.pc.bShowMouseCursor and R.widget.Visibility==1)")
if __name__=='__main__':unittest.main()
