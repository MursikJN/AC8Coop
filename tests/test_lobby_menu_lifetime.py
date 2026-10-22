"""Run the real Lua menu with destroyed MainTop and a campaign handoff."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
from test_coop_main_menu import FIXTURE

ROOT=Path(__file__).resolve().parents[1]
class MenuLifetimeTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute(FIXTURE)
  self.lua.globals().MENU=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/coop_main_menu.lua').read_text(encoding='utf-8'))
  self.lua.globals().L=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/lobby_menu_lifetime.lua').read_text(encoding='utf-8'))
  self.lua.execute("""
   CALLS=0;EVENTS={};C={snapshot={phase='0'}}
   H.main.IsVisible=function(self)assert(not self.invalid,'native AV sentinel');CALLS=CALLS+1;return true end
   R=L.new(MENU,OPTIONS,function(name)EVENTS[#EVENTS+1]=name end)
  """)
 def test_old_unguarded_poll_reproduces_destroyed_receiver(self):
  self.lua.execute("assert(R.poll());local old=R.ui;H.main.invalid=true;assert(not pcall(function()old.main:IsVisible()end));assert(not R.poll());assert(CALLS==1)")
 def test_handoff_closes_open_ui_once_and_never_touches_old_world(self):
  self.lua.execute("""
   assert(R.poll());R.ui.show();assert(H.mode=='ui_only')
   C.snapshot.phase='1';R.handoff(C);assert(R.retired and not R.ui and not _G.AC8MainMenuEntry and H.mode=='game_and_ui')
   H.main.invalid=true;FindAllOf=function()error('No menu scan after handoff')end
   for _,phase in ipairs({'1','2','3','4','5','6','8','9','10','0'})do
    C.snapshot.phase=phase;assert(not R.poll());R.handoff(C);R.refresh()
   end
   assert(CALLS==1 and #EVENTS==1)
  """)
 def test_destroyed_ui_at_handoff_is_forgotten_without_close(self):
  self.lua.execute("R.poll();R.ui.close=function()error('Cannot close destroyed menu')end;H.main.invalid=true;C.snapshot.phase='1';R.handoff(C);assert(R.retired and not R.ui)")
 def test_lobby_stays_usable_before_mission(self):
  self.lua.execute("for i=1,3 do assert(R.poll());R.handoff(C);R.refresh()end;assert(not R.retired and R.ui and CALLS==3)")
 def test_failed_close_is_not_retried(self):
  self.lua.execute("R.poll();R.ui.close=function()error('partial close')end;C.snapshot.phase='1';assert(not pcall(R.handoff,C));R.handoff(C);assert(not R.poll()and not R.ui)")
 def test_stale_global_is_not_reused_after_handoff(self):
  self.lua.execute("R.poll();local old=R.ui;C.snapshot.phase='1';R.handoff(C);assert(_G.AC8MainMenuEntry==nil);assert(old~=nil and R.ui==nil)")

if __name__=='__main__':unittest.main()
