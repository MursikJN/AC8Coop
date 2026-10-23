"""Request gate tests only; no claim about engine screenshot/input behavior."""
from pathlib import Path
import unittest
from lupa import LuaRuntime

class AutomationTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.module=self.lua.execute((Path(__file__).resolve().parents[1]/'probe/Mission6Capture/Scripts/automation.lua').read_text())
    def test_valid_request(self):
        self.assertEqual(self.module.parse('id\t1\ncreated\t100\noperation\tscreenshot\n',100,0)['id'],1)
    def test_reject_replay_expired_arbitrary_commands(self):
        for text,last in [('id\t1\ncreated\t100\noperation\tscreenshot',1),
                          ('id\t2\ncreated\t1\noperation\tscreenshot',0),
                          ('id\t2\ncreated\t100\noperation\texec',0),
                          ('id\t2\nid\t3\ncreated\t100\noperation\tquit',0),
                          ('id\t2\ncreated\t100\noperation\tscreenshot\ncommand\tquit',0)]:
            with self.subTest(text=text),self.assertRaises(Exception):
                self.module.parse(text,100,last)
    def test_default_disabled(self):
        self.assertIn("os.getenv('AC8_CAPTURE_AUTOMATION')=='1'",(Path(__file__).resolve().parents[1]/'probe/Mission6Capture/Scripts/main.lua').read_text())
