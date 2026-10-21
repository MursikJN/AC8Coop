"""Accepted Steam invite -> existing controller -> native join config -> room UI."""
import unittest
from lupa import LuaRuntime
from test_coop_main_menu import FIXTURE
import test_steam_lobby as fixture
SOURCE=fixture.SOURCE

class InviteTests(unittest.TestCase):
 setUp=fixture.SteamLobbyTests.setUp
 state=fixture.SteamLobbyTests.state
 host=fixture.SteamLobbyTests.host
 def receiver(self,menu=True):
  self.lua.execute('N.invites_tick=function()calls.invite_ticks=(calls.invite_ticks or 0)+1 end;N.invites_open=function()calls.open=(calls.open or 0)+1 end;C=M.new(OUTPUT,N,function()return T end)')
  self.lua.execute('C.set_menu_available('+str(menu).lower()+')')
 def invite_status(self,**fields):
  data=dict(format='ac8-invite-status-v1',instance='123456789012345678',ready=1,state='READY',overlay_enabled=1,open_seen=0,open_requested=0,join_sequence=0,join_host=0)
  data.update(fields);(self.root/'steam-invite-status.tsv').write_text(''.join(f'{k}\t{v}\n'for k,v in data.items()));self.lua.execute('C.poll()')
 def stopped(self,token=None):
  token=token or self.lua.eval('C.token');(self.root/'shared-session-control.tsv').write_text(f'format\tac8-steam-control-v1\nconfig_token\t{token}\nrunning\t0\ncan_restart\t1\n');self.lua.execute('C.poll()')
 def frontend(self):
  self.lua.globals().CAT=self.lua.execute((SOURCE/'coop_menu_catalog.lua').read_text(encoding='utf-8'))
  self.lua.globals().F=self.lua.execute((SOURCE/'coop_lobby_frontend.lua').read_text(encoding='utf-8'))
  self.lua.execute('S=F.new({is_host=true,view=C.view,create=C.create,join=C.join,leave=C.leave,invite=C.invite,select=C.select,ready=C.ready},CAT)')
 def test_receiver_is_active_without_starting_a_room(self):
  self.receiver();self.invite_status();self.lua.execute('assert(calls.invite_ticks==1 and calls.start==0 and not C.view().connected)')
 def test_host_opens_selector_without_manufacturing_invite_or_connection(self):
  self.receiver();self.invite_status();self.host();self.state(connected=0,transport='HOST_WAITING_FOR_FRIEND');self.frontend()
  self.lua.execute('assert(S.view().can_invite);S.invite();assert(calls.open==1 and not C.view().connected and not C.view().host_ready)')
  self.assertIn('config_token\t'+self.lua.eval('C.token'),(self.root/'steam-invite-command.tsv').read_text())
 def test_guest_and_idle_cannot_open_host_selector(self):
  self.receiver();self.invite_status();self.lua.execute('assert(not pcall(C.invite));C.join("76561198000000002")');self.state();self.lua.execute('assert(not C.view().can_invite and not pcall(C.invite))')
 def test_acceptance_waits_for_main_menu_then_joins_automatically(self):
  self.receiver(False);self.invite_status(join_sequence=1,join_host='76561198000000002')
  self.lua.execute('assert(calls.start==0 and C.auto_target);C.set_menu_available(true);C.poll();assert(calls.start==1 and C.role=="guest" and C.peer=="76561198000000002" and C.join_notice==1 and not C.view().connected)')
  self.assertEqual((self.root/'shared-session-config.tsv').read_text().splitlines()[:2],['guest','76561198000000002'])
 def test_auto_join_updates_room_even_when_initial_role_was_host(self):
  self.receiver();self.frontend();self.invite_status(join_sequence=1,join_host='76561198000000002')
  self.lua.execute('V=S.view();assert(V.room and not V.host and V.screen=="room" and not V.connected and not V.host_ready)')
 def test_repeated_callback_for_same_active_peer_does_not_reset_readiness(self):
  self.receiver();self.invite_status(join_sequence=1,join_host='76561198000000002');self.state(ready_mask=3);old=self.lua.eval('C.token')
  self.invite_status(join_sequence=2,join_host='76561198000000002');self.lua.execute('assert(calls.start==1 and calls.stop==0 and C.view().guest_ready)');self.assertEqual(old,self.lua.eval('C.token'))
 def test_accepting_another_host_stops_room_before_new_join(self):
  self.receiver();self.invite_status();self.host();old=self.lua.eval('C.token')
  self.invite_status(join_sequence=1,join_host='76561198000000002');self.lua.execute('assert(C.closing and calls.stop==1 and calls.start==1)')
  self.stopped();self.lua.execute('assert(not C.closing and calls.start==2 and C.role=="guest" and C.join_notice==1 and C.error==nil)');self.assertNotEqual(old,self.lua.eval('C.token'))
 def test_old_worker_status_cannot_release_new_join(self):
  self.receiver();self.invite_status();self.host();self.invite_status(join_sequence=1,join_host='76561198000000002');self.stopped('wrong')
  self.lua.execute('assert(C.closing and calls.start==1)')
 def test_explicit_leave_cancels_invite_waiting_for_menu(self):
  self.receiver(False);self.invite_status(join_sequence=1,join_host='76561198000000002');self.lua.execute('C.leave();C.set_menu_available(true);C.poll();assert(calls.start==0 and C.auto_target==nil)')
 def test_unrelated_callback_format_or_bad_host_does_not_join(self):
  self.receiver();self.invite_status(format='other',join_sequence=1,join_host='76561198000000002');self.lua.execute('assert(calls.start==0)')
  self.invite_status(join_sequence=2,join_host='not-a-steam-id');self.lua.execute('assert(calls.start==0)')
 def test_same_host_invite_reconnects_after_transport_closed(self):
  self.receiver();self.invite_status(join_sequence=1,join_host='76561198000000002');self.state(connected=0,transport='DISCONNECTED_PRESS_F8')
  self.invite_status(join_sequence=2,join_host='76561198000000002');self.lua.execute('assert(C.closing and calls.stop==1)');self.stopped();self.lua.execute('assert(calls.start==2)')
 def test_manual_leave_does_not_reopen_room_during_worker_shutdown(self):
  self.receiver();self.invite_status();self.host();self.frontend();self.lua.execute('assert(S.view().room);S.leave();assert(not S.view().room)');self.stopped();self.lua.execute('assert(not S.view().room)')
 def test_overlay_failure_is_visible_and_does_not_block_manual_connection(self):
  self.receiver();self.invite_status();self.host();self.state(connected=0,transport='HOST_WAITING_FOR_FRIEND');self.lua.execute('C.invite()')
  self.invite_status(state='OVERLAY_UNAVAILABLE',open_seen=1,overlay_enabled=0)
  self.lua.execute('assert(C.invite_request==nil and C.view().info:find("недоступен",1,true) and not C.view().connected)')
 def test_connected_snapshot_clears_transient_invite_prompt(self):
  self.receiver();self.invite_status(join_sequence=1,join_host='76561198000000002');self.state(ready_mask=3);self.lua.execute('assert(C.view().info==nil and C.view().guest_ready)')

class InviteWidgetTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE);self.lua.globals().SOURCE=SOURCE.as_posix()
  self.lua.globals().MENU=self.lua.execute((SOURCE/'coop_main_menu.lua').read_text(encoding='utf-8'))
  self.lua.execute('''V={phase=0,have_snapshot=true,lobby_only=true,can_invite=true,room_role='host'};blocked=false;calls=0
   OPTIONS.compact=true;OPTIONS.source=SOURCE;OPTIONS.catalog=assert(loadfile(SOURCE..'/coop_menu_catalog.lua'))();OPTIONS.is_host=true;OPTIONS.view=function()return V end
   OPTIONS.create=function()end;OPTIONS.invite=function()calls=calls+1 end;OPTIONS.input_blocked=function()return blocked end
   UI=MENU.attach(OPTIONS);UI.show();UI.refresh()''')
 def click(self,name):self.lua.execute(f"H.hover['{name}']=true;H.keys[1]();UI.refresh();H.hover['{name}']=false")
 def test_invite_button_only_opens_selector_for_host(self):
  self.click('AC8_Lobby_Invite');self.lua.execute('assert(calls==1);V.room_role="guest";UI.refresh();assert(H.created.AC8_Lobby_Invite.Visibility==1)')
  self.click('AC8_Lobby_Invite');self.lua.execute('assert(calls==1)')
 def test_overlay_clicks_are_not_replayed_after_it_closes(self):
  self.lua.execute('blocked=true');self.click('AC8_Lobby_Invite');self.lua.execute('assert(calls==0);blocked=false;UI.refresh();assert(calls==0)')
  self.click('AC8_Lobby_Invite');self.lua.execute('assert(calls==1)')

class InviteBootTests(unittest.TestCase):
 setUp=fixture.SteamLobbyTests.setUp
 def test_accepted_invite_waits_for_visible_menu_and_opens_guest_page(self):
  self.lua.execute(FIXTURE);self.lua.globals().SOURCE=SOURCE.as_posix()
  (self.root/'steam-invite-status.tsv').write_text('format\tac8-invite-status-v1\ninstance\t1\nready\t1\njoin_sequence\t1\njoin_host\t76561198000000002\n')
  self.lua.execute('''env={AC8_STEAM_LOBBY='25201480',AC8_STEAM_INVITES='25201480',AC8_LOBBY_SCRIPTS=SOURCE,AC8_COOP_RECON_OUTPUT=OUTPUT,AC8_LOBBY_DLL='fake',AC8_LOBBY_ROLE='host'}
   os.getenv=function(k)return env[k]end;native_calls={};package.loadlib=function(_,name)return function()native_calls[name]=(native_calls[name]or 0)+1 end end
   jobs={};ExecuteInGameThreadWithDelay=function(_,fn)jobs[#jobs+1]=fn end
   visible=false;H.main.IsVisible=function()return visible end
   assert(loadfile(SOURCE..'/steam_lobby_main.lua'))();jobs[#jobs]();assert(native_calls.luaopen_ac8_lobby24_start==nil)
   visible=true;jobs[#jobs]();assert(native_calls.luaopen_ac8_lobby24_start==1)
   assert(AC8MainMenuEntry.open and AC8MainMenuEntry.compact.view.room and not AC8MainMenuEntry.compact.view.host)
   assert(not AC8MainMenuEntry.compact.view.connected)
  ''')
  self.assertEqual((self.root/'shared-session-config.tsv').read_text().splitlines()[:2],['guest','76561198000000002'])

if __name__=='__main__':unittest.main()
