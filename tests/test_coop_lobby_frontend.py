"""Menu authority, readiness acknowledgements and recovery without a second PC."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
from test_coop_main_menu import FIXTURE
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts'
class FrontendTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.globals().catalog=self.lua.execute((SOURCE/'coop_menu_catalog.lua').read_text(encoding='utf-8'))
  self.lua.globals().module=self.lua.execute((SOURCE/'coop_lobby_frontend.lua').read_text(encoding='utf-8'))
  self.lua.execute("""
   V={phase=0,mission=6,difficulty=1,have_snapshot=true,connected=false,pending=false,can_ready=false};calls={}
   O={is_host=true,view=function()return V end,
    select=function(m,d)calls.select=(calls.select or 0)+1;calls.m=m;calls.d=d end,
    ready=function()calls.ready=(calls.ready or 0)+1 end,
    open_hangar=function()calls.start=(calls.start or 0)+1 end}
   S=module.new(O,catalog)
  """)
 def test_exact_stock_captions_and_easy_wire_identity(self):
  self.assertEqual([self.lua.eval(f'catalog.difficulties[{i}].caption')for i in range(1,5)],['НОВИЧОК (СЮЖЕТ)','ПИЛОТ','ВЕТЕРАН','ЭЛИТА'])
  self.assertEqual(self.lua.eval('catalog.difficulties[2].value'),1)
 def test_create_does_not_fabricate_connection_or_ready(self):
  self.lua.execute('assert(S.enter());assert(S.view().room and not S.view().connected and not S.view().can_primary and calls.ready==nil)')
 def test_draft_selection_sends_once_when_creating(self):
  self.lua.execute('S.select(6,2);assert(calls.select==nil);S.enter();assert(calls.select==1 and calls.d==2)')
 def test_host_primary_requires_new_click_after_both_ready_ack(self):
  self.lua.execute('S.enter();V.connected=true;V.can_ready=true;S.primary();assert(calls.ready==1 and calls.start==nil);V.ready=true;V.host_ready=true;assert(not S.view().can_primary);V.guest_ready=true;V.can_open_hangar=true;assert(calls.start==nil);S.primary();assert(calls.start==1)')
 def test_guest_never_changes_mission_or_starts_host_route(self):
  self.lua.execute("O.is_host=false;S.mode('join');V.connected=true;S.enter();assert(not pcall(S.select,6,2));V.can_ready=true;S.primary();assert(calls.ready==1 and calls.start==nil)")
 def test_wrong_local_role_cannot_claim_joined(self):
  self.lua.execute("S.mode('join');V.connected=true;assert(not pcall(S.enter));assert(not S.room)")
 def test_pending_command_blocks_duplicates_but_not_mode_navigation(self):
  self.lua.execute("V.pending=true;assert(not S.view().can_enter);assert(not pcall(S.enter));S.mode('join');assert(S.screen=='join')")
 def test_backend_error_is_preserved_and_readiness_not_invented(self):
  self.lua.execute("S.enter();V.can_ready=true;O.ready=function()error('Connection closed')end;assert(not S.primary());assert(S.view().detail:find('Connection closed',1,true));assert(not S.view().host_ready)")
 def test_configuration_change_remains_pending_until_host_snapshot(self):
  self.lua.execute("S.enter();S.select(6,3);assert(calls.d==3 and S.view().difficulty==1);V.difficulty=3;V.host_ready=false;V.guest_ready=false;assert(S.view().difficulty_caption=='ЭЛИТА'and not S.view().host_ready)")
 def test_join_validates_target_and_never_fabricates_peer_readiness(self):
  self.lua.execute("O.join=function(peer)calls.peer=peer end;S.mode('join');assert(not pcall(S.enter,'123'));assert(not S.room);assert(S.enter('76561198000000002'));assert(calls.peer=='76561198000000002'and not S.view().host and not S.view().connected and not S.view().host_ready and not S.view().can_primary)")
 def test_rejected_backend_connection_does_not_open_room(self):
  self.lua.execute("O.join=function()return false end;S.mode('join');assert(not S.enter('76561198000000002'));assert(not S.room and S.error:find('отклонено',1,true))")
 def test_unsupported_difficulty_does_not_pretend_guest_is_not_ready(self):
  self.lua.execute("S.enter();V.ready=true;V.host_ready=true;V.guest_ready=true;V.connected=true;V.difficulty=3;assert(S.view().primary=='ПРОДОЛЖЕНИЕ НЕДОСТУПНО'and not S.view().can_primary)")
 def test_unready_never_uses_continue_action(self):
  self.lua.execute('S.enter();V.ready=true;V.can_ready=true;V.can_open_hangar=true;S.unready();assert(calls.ready==1 and calls.start==nil)')

class CompactWidgetTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE)
  self.lua.globals().SOURCE=SOURCE.as_posix()
  self.lua.globals().M=self.lua.execute((SOURCE/'coop_main_menu.lua').read_text(encoding='utf-8'))
  self.lua.execute("""
   V={phase=0,mission=6,difficulty=1,have_snapshot=true,connected=false,can_ready=false};OPTIONS.local_session=true;OPTIONS.compact=true;OPTIONS.is_host=true;OPTIONS.source=SOURCE
   OPTIONS.catalog=assert(loadfile(SOURCE..'/coop_menu_catalog.lua'))();OPTIONS.view=function()return V end;OPTIONS.select=function()end;OPTIONS.open_hangar=function()H.launches=(H.launches or 0)+1 end
   UI=M.attach(OPTIONS);UI.show();UI.refresh()
  """)
 def click(self,name):self.lua.execute(f"H.hover['{name}']=true;H.keys[1]();UI.refresh();H.hover['{name}']=false")
 def test_new_page_is_inside_stock_canvas_and_has_no_apply_button(self):
  self.assertTrue(self.lua.eval('UI.page.parent==H.canvas'))
  self.assertIsNone(self.lua.eval('H.created.AC8_Local_Apply'))
 def test_hidden_ready_control_cannot_consume_same_click_as_create(self):
  self.lua.execute('H.hover.AC8_Lobby_Enter=true;H.hover.AC8_Lobby_Primary=true;H.keys[1]();UI.refresh();assert(H.ready==0 and UI.compact.view.room)')
 def test_back_always_releases_input_during_pending_action(self):
  self.lua.execute('V.pending=true;UI.refresh()');self.click('AC8_Lobby_Back')
  self.assertFalse(self.lua.eval('UI.open'));self.assertEqual(self.lua.eval('H.mode'),'game_and_ui')
 def test_ready_then_continue_needs_two_separate_clicks(self):
  self.click('AC8_Lobby_Enter');self.lua.execute('V.connected=true;V.can_ready=true;UI.refresh()');self.click('AC8_Lobby_Primary')
  self.assertEqual(self.lua.eval('H.ready'),1)
  self.lua.execute('V.ready=true;V.host_ready=true;V.guest_ready=true;V.can_open_hangar=true;UI.refresh()');self.assertIsNone(self.lua.eval('H.launches'))
  self.click('AC8_Lobby_Primary');self.assertEqual(self.lua.eval('H.launches'),1)
 def test_reattachment_never_reconstructs_old_named_widgets(self):
  self.lua.execute("old_name=UI.entry.native_name;UI.close();UI.entry:RemoveFromParent();UI.page:RemoveFromParent();AC8MainMenuEntry=nil;UI=M.attach(OPTIONS);UI.show();assert(UI.entry.native_name~=old_name)")
 def test_failed_page_construction_leaves_native_grid_and_input_available(self):
  self.lua.execute("UI.close();UI.page:RemoveFromParent();UI.page=nil;OPTIONS.source='missing-path';assert(not pcall(UI.show));assert(UI.page==nil and not UI.open and H.grid.Visibility==4 and H.mode=='game_and_ui')")
if __name__=='__main__':unittest.main()
