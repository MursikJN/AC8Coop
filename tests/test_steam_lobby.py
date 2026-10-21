"""Real controller file boundary: tokens, host acknowledgements, leave/rejoin and UI roles."""
from pathlib import Path
import shutil
import uuid
import unittest
from lupa import LuaRuntime
from test_coop_main_menu import FIXTURE

SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts'

class SteamLobbyTests(unittest.TestCase):
 def setUp(self):
  temp_root=SOURCE.parents[2]/'build/lobby-test-temp';temp_root.mkdir(parents=True,exist_ok=True)
  self.root=temp_root/uuid.uuid4().hex;self.root.mkdir();self.addCleanup(shutil.rmtree,self.root)
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.globals().OUTPUT=self.root.as_posix()
  self.lua.globals().M=self.lua.execute((SOURCE/'steam_lobby_services.lua').read_text(encoding='utf-8'))
  self.lua.execute('T=1000;calls={start=0,stop=0,tick=0};N={};for _,k in ipairs({"start","stop","tick"})do N[k]=function()calls[k]=calls[k]+1 end end;C=M.new(OUTPUT,N,function()return T end)')
  self.beat=0
 def state(self,**fields):
  self.beat+=1
  data=dict(format='ac8-session-status-v3',config_token=self.lua.eval('C.token'),heartbeat=self.beat,connected=1,have_snapshot=1,role=self.lua.eval('C.role'),epoch=1,revision=2,mission=6,difficulty=1,ready_mask=0,guest_aircraft=23,request_ack=0,request_confirmed=0,reject=0,transport='CONNECTED_TEST_OK',self='76561198000000001',peer='76561198000000002',host_name='Host',guest_name='Guest')
  data.update(fields);(self.root/'shared-session-status.tsv').write_text(''.join(f'{k}\t{v}\n'for k,v in data.items()),encoding='utf-8');self.lua.execute('C.poll()')
 def host(self):
  self.lua.execute('C.create(6,1)');self.state();self.state(request_ack=1,request_confirmed=1)
 def test_does_not_start_transport_on_boot_or_idle_poll(self):
  self.lua.execute('C.poll();assert(calls.start==0 and not C.view().connected)')
 def test_host_creation_sends_selected_difficulty_after_own_snapshot(self):
  self.lua.execute('C.create(6,4)');self.assertEqual((self.root/'shared-session-config.tsv').read_text().splitlines()[:2],['host','0'])
  self.state(connected=0,mission=0,difficulty=0);text=(self.root/'shared-session-command.tsv').read_text();self.assertIn('op\t2\narg0\t6\narg1\t4\n',text)
  self.lua.execute('assert(C.view().pending and not C.view().connected)')
 def test_guest_validates_id_before_start(self):
  self.lua.execute("assert(not pcall(C.join,'bad'));assert(calls.start==0);C.join('76561198000000002');assert(calls.start==1)")
 def test_stale_status_cannot_connect_or_confirm(self):
  self.lua.execute("C.join('76561198000000002')");self.state(config_token='old',ready_mask=3,request_confirmed=99)
  self.lua.execute('assert(not C.view().connected and C.view().pending)')
 def test_guest_request_ack_is_not_host_confirmation(self):
  self.lua.execute("C.join('76561198000000002')");self.state();self.lua.execute('C.ready()')
  self.state(request_ack=1,request_confirmed=0);self.lua.execute('assert(C.view().pending and not C.view().guest_ready)')
  self.state(request_ack=1,request_confirmed=1,ready_mask=2);self.lua.execute('assert(not C.view().pending and C.view().guest_ready)')
 def test_guest_cannot_select_host_mission(self):
  self.lua.execute("C.join('76561198000000002')");self.state();self.lua.execute('assert(not pcall(C.select,6,2))')
  self.assertFalse((self.root/'shared-session-command.tsv').exists())
 def test_loadout_change_requires_new_acknowledged_ready(self):
  self.lua.execute("C.join('76561198000000002')");self.state(ready_mask=2);self.lua.execute('C.loadout(23)')
  self.state(request_ack=1,request_confirmed=1,ready_mask=0);self.lua.execute('assert(not C.view().ready and C.view().can_ready);C.ready()')
  self.state(request_ack=2,request_confirmed=2,ready_mask=2);self.lua.execute('assert(C.view().ready)')
 def test_missing_loadout_blocks_guest_ready(self):
  self.lua.execute("C.join('76561198000000002')");self.state(guest_aircraft=0);self.lua.execute('assert(not C.view().can_ready and C.view().can_loadout and not pcall(C.ready))')
 def test_reject_clears_pending_and_reports_error(self):
  self.lua.execute("C.join('76561198000000002')");self.state();self.lua.execute('C.ready()');self.state(request_ack=1,request_confirmed=1,reject=3)
  self.lua.execute('assert(not C.view().pending and not C.view().ready and C.view().error)')
 def test_timeout_keeps_single_outstanding_command(self):
  self.lua.execute("C.join('76561198000000002')");self.state();self.lua.execute('C.ready();T=T+11');self.state(request_ack=1,request_confirmed=0)
  self.lua.execute('assert(C.view().pending and C.view().error and not pcall(C.ready))')
 def test_frozen_file_does_not_count_as_fresh_heartbeat(self):
  self.host();self.lua.execute('T=T+6;C.poll();assert(not C.view().connected and not C.view().can_ready and C.view().error)')
 def test_disconnect_removes_readiness_and_cancels_pending(self):
  self.host();self.lua.execute('C.ready()');self.state(connected=0,ready_mask=0)
  self.lua.execute('assert(not C.view().pending and not C.view().ready and not C.view().connected)')
 def test_leave_waits_for_worker_stop_then_switches_role_with_new_token(self):
  self.host();old=self.lua.eval('C.token');self.lua.execute('C.leave();assert(calls.stop==1 and C.view().pending and not pcall(C.join,"76561198000000002"))')
  (self.root/'shared-session-control.tsv').write_text(f'format\tac8-steam-control-v1\nconfig_token\t{old}\nrunning\t0\ncan_restart\t1\n')
  self.lua.execute('C.poll();assert(not C.active);C.join("76561198000000002")')
  self.assertNotEqual(old,self.lua.eval('C.token'));self.assertFalse((self.root/'shared-session-command.tsv').exists())
 def test_both_ready_never_enables_unimplemented_mission_start(self):
  self.host();self.state(ready_mask=3);self.lua.execute('assert(C.view().host_ready and C.view().guest_ready and not C.view().can_open_hangar)')
 def test_frontend_can_change_role_and_use_real_lifecycle(self):
  self.lua.globals().CAT=self.lua.execute((SOURCE/'coop_menu_catalog.lua').read_text(encoding='utf-8'))
  self.lua.globals().FRONT=self.lua.execute((SOURCE/'coop_lobby_frontend.lua').read_text(encoding='utf-8'))
  self.lua.execute('S=FRONT.new({is_host=false,view=C.view,create=C.create,join=C.join,leave=C.leave,select=C.select,ready=C.ready},CAT);S.mode("create");assert(S.view().can_enter);assert(S.enter());assert(C.role=="host");assert(S.leave());assert(calls.stop==1)')
 def test_frontend_shows_both_ready_and_exact_difficulty(self):
  self.host();self.state(ready_mask=3,difficulty=4)
  self.lua.globals().CAT=self.lua.execute((SOURCE/'coop_menu_catalog.lua').read_text(encoding='utf-8'))
  self.lua.globals().FRONT=self.lua.execute((SOURCE/'coop_lobby_frontend.lua').read_text(encoding='utf-8'))
  self.lua.execute('S=FRONT.new({is_host=true,view=C.view},CAT);S.room=true;S.role="host";S.screen="room";V=S.view();assert(V.primary=="ОБА ГОТОВЫ" and V.difficulty_caption=="НОВИЧОК (СЮЖЕТ)" and not V.can_primary)')

class SteamWidgetTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE);self.lua.globals().SOURCE=SOURCE.as_posix()
  self.lua.globals().MENU=self.lua.execute((SOURCE/'coop_main_menu.lua').read_text(encoding='utf-8'))
  self.lua.execute('''V={phase=0,have_snapshot=false,lobby_only=true};calls={};OPTIONS.compact=true;OPTIONS.source=SOURCE;OPTIONS.catalog=assert(loadfile(SOURCE..'/coop_menu_catalog.lua'))();OPTIONS.is_host=true;OPTIONS.view=function()return V end
   OPTIONS.create=function(m,d)calls.created={m,d}end;OPTIONS.join=function(peer)calls.peer=peer end;OPTIONS.leave=function()calls.left=true end;OPTIONS.loadout=function(a)calls.plane=a end
   UI=MENU.attach(OPTIONS);UI.show();UI.refresh()''')
 def click(self,name):self.lua.execute(f"H.hover['{name}']=true;H.keys[1]();UI.refresh();H.hover['{name}']=false")
 def test_create_leave_join_and_acknowledged_guest_loadout(self):
  self.click('AC8_Lobby_Enter');self.lua.execute('assert(calls.created[1]==6 and not UI.compact.view.connected)')
  self.click('AC8_Lobby_Leave');self.lua.execute('assert(calls.left and not UI.compact.view.room)')
  self.click('AC8_Lobby_JoinTab');self.lua.execute("UI.compact.peer.text='76561198000000002'")
  self.click('AC8_Lobby_Enter');self.lua.execute("assert(calls.peer=='76561198000000002' and not UI.compact.view.host);V.connected=true;V.have_snapshot=true;V.can_loadout=true;UI.refresh()")
  self.click('AC8_Lobby_Loadout');self.lua.execute('assert(calls.plane==23 and UI.compact.view.guest_aircraft=="Самолёт не выбран")')
  self.lua.execute('V.guest_aircraft=23;UI.refresh();assert(UI.compact.view.guest_aircraft=="F-14D")')
 def test_back_preserves_real_room_until_explicit_leave(self):
  self.click('AC8_Lobby_Enter');self.click('AC8_Lobby_Back');self.lua.execute('assert(calls.left==nil);UI.show();assert(UI.compact.view.room)')

if __name__=='__main__':unittest.main()
