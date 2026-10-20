"""Exercise actual Lua glue with queued UE4SS substitutes; no game is started."""
from pathlib import Path
import os
import unittest
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'connection-test/main.lua').read_text(encoding='utf-8')


class GlueTests(unittest.TestCase):
    def runtime(self, armed=True):
        lua = LuaRuntime()
        lua.execute('''
            calls = {}; queued = {}; keys = {}; loops = {}
            Key = {F8=8, F9=9, F6=6}
            function RegisterKeyBind(k, f) keys[k] = f end
            function ExecuteInGameThread(f) table.insert(queued, f) end
            function LoopAsync(ms, f) assert(ms == 100); loops[1] = f end
            function flush() local q=queued; queued={}; for _,f in ipairs(q) do f() end end
            package.loadlib = function(path, symbol)
                assert(path == 'test.dll')
                return function() table.insert(calls, symbol) end
            end
            print = function() end
        ''')
        lua.globals().armed = armed
        lua.execute('os.getenv = function(k) if not armed then return nil end; if k == "AC8_CONNECTION_TEST" then return "25201480" else return "test.dll" end end')
        lua.execute(SOURCE)
        return lua

    def test_unarmed_has_no_bindings(self):
        lua = self.runtime(False)
        self.assertTrue(lua.eval('next(keys) == nil and next(loops) == nil'))

    def test_keys_dispatch_on_game_thread(self):
        lua = self.runtime()
        lua.execute('keys[8](); keys[9](); keys[6]()')
        self.assertEqual(lua.eval('#calls'), 0)
        lua.execute('flush()')
        self.assertEqual([lua.globals().calls[i] for i in range(1, 4)], [
            'luaopen_ac8_connection_start', 'luaopen_ac8_connection_stop', 'luaopen_ac8_connection_status'])

    def test_pump_does_not_build_backlog(self):
        lua = self.runtime()
        lua.execute('for i=1,100 do loops[1]() end')
        self.assertEqual(lua.eval('#queued'), 1)
        lua.execute('flush(); loops[1](); flush()')
        self.assertEqual(lua.eval('#calls'), 2)

    def test_dispatch_failure_stops_loop(self):
        lua = self.runtime()
        lua.execute('ExecuteInGameThread = function() error("test") end; keys[8]()')
        self.assertTrue(lua.eval('loops[1]()'))

    def test_native_exports_load_unarmed(self):
        self.assertNotIn('AC8_CONNECTION_TEST', os.environ)
        lua = LuaRuntime()
        lua.globals().dll = 'D:/projects/unreal-mod-tools/build/connection-test/ac8_connection_test.dll'
        lua.execute('''for _,name in ipairs({'start','stop','pump','status'}) do
            local f, err = package.loadlib(dll, 'luaopen_ac8_connection_' .. name)
            assert(f, err); assert(select('#', f()) == 0)
        end''')


if __name__ == '__main__':
    unittest.main()
