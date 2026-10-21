"""Local lobby: guest waits for authority, own ready toggles, stock menu has no flight shortcut."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
from test_coop_main_menu import FIXTURE

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'probe/AC8CoopRecon/Scripts'


class LocalServicesTests(unittest.TestCase):
    def controller(self, host):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            files={}; io.open=function(path,mode)
                if mode=='wb' then return {write=function(_,s)files[path]=s end,close=function()end}end
                if not files[path]then return nil end
                return {read=function()return files[path]end,close=function()end}
            end
            started=0
        ''')
        lua.globals().M = lua.execute((SCRIPTS / 'shared_session_local_services.lua').read_text(encoding='utf-8'))
        lua.globals().HOST = host
        lua.execute("C=M.new('output',HOST,'123',function()started=started+1 end);C.start()")
        self.assertEqual(lua.eval('started'), 1)
        return lua

    @staticmethod
    def snapshot(lua, **overrides):
        fields = dict(format='ac8-session-status-v2', config_token='123', have_snapshot='1', connected='1',
                      transport='connected', reason='none', epoch='1', revision='2', mission='1', difficulty='2',
                      ready_mask='0', request_ack='0', reject='0')
        fields.update(overrides)
        lua.globals().STATUS = ''.join(f'{k}\t{v}\n' for k, v in fields.items())
        lua.execute("files['output/shared-session-status.tsv']=STATUS;C.poll()")

    def test_host_selects_default_once_then_waits_for_ack(self):
        lua = self.controller(True)
        self.snapshot(lua)
        self.assertIn('op\t2\narg0\t1\narg1\t2\n', lua.eval("files['output/shared-session-command.tsv']"))
        self.assertFalse(lua.eval('C.view().can_ready'))
        self.snapshot(lua, request_ack='1', revision='3')
        self.assertTrue(lua.eval('C.view().can_ready'))
        lua.execute('C.ready()')
        self.assertIn('request\t2\n', lua.eval("files['output/shared-session-command.tsv']"))

    def test_guest_does_not_select_or_write_before_click(self):
        lua = self.controller(False)
        self.snapshot(lua)
        self.assertIsNone(lua.eval("files['output/shared-session-command.tsv']"))
        self.assertRaises(Exception, lua.execute, 'C.select(6,3)')
        lua.execute('C.ready()')
        self.snapshot(lua, request_ack='1')
        self.assertFalse(lua.eval('C.view().can_ready'))  # sent is not applied
        self.snapshot(lua, request_ack='1', ready_mask='2')
        self.assertTrue(lua.eval('C.view().ready'))
        self.assertTrue(lua.eval('C.view().can_ready'))
        lua.execute('C.ready()')
        self.assertIn('arg0\t0\n', lua.eval("files['output/shared-session-command.tsv']"))

    def test_old_run_status_and_disconnect_do_not_enable_ready(self):
        lua = self.controller(False)
        self.snapshot(lua, config_token='122')
        self.assertFalse(lua.eval('C.view().can_ready'))
        self.snapshot(lua, connected='0', transport='disconnected', reason='peer_closed')
        self.assertFalse(lua.eval('C.view().can_ready'))
        self.assertIn('peer_closed', lua.eval('C.status()'))


class LocalMenuTests(unittest.TestCase):
    def ui(self, host):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(FIXTURE)
        lua.globals().M = lua.execute((SCRIPTS / 'coop_main_menu.lua').read_text(encoding='utf-8'))
        lua.globals().HOST = host
        lua.execute("""
            selected=0;ready=0
            UI=M.attach({local_session=true,is_host=HOST,status=function()return 'local'end,
              ready=function()ready=ready+1 end,select=function()selected=selected+1 end,
              view=function()return {can_ready=true,ready=false,choice='shared choice'}end})
            UI.show();UI.refresh()
        """)
        return lua

    def test_guest_has_ready_but_no_mission_or_start_controls(self):
        lua = self.ui(False)
        for name in ('AC8_Local_Mission', 'AC8_Coop_Launch', 'AC8_Coop_Peer', 'AC8_Local_Apply'):
            self.assertIsNone(lua.eval(f"H.created['{name}']"))
        lua.execute("H.hover.AC8_Local_Ready=true;H.keys[1]();UI.refresh()")
        self.assertEqual(lua.eval('ready'), 1)
        self.assertEqual(lua.eval('H.mode'), 'ui_only')

    def test_host_selection_is_manual_and_has_no_flight_shortcut(self):
        lua = self.ui(True)
        self.assertEqual(lua.eval('selected'), 0)
        lua.execute("H.hover.AC8_Local_Apply=true;H.keys[1]();UI.refresh()")
        self.assertEqual(lua.eval('selected'), 1)
        self.assertIsNone(lua.eval('H.created.AC8_Coop_Launch'))
        self.assertEqual(lua.eval('UI.choice.text'), 'shared choice')


if __name__ == '__main__':
    unittest.main()
