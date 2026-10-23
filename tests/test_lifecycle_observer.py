"""Observer regressions, not claims about actual UE object availability."""
from pathlib import Path
import unittest
from lupa import LuaRuntime

SOURCE=Path(__file__).resolve().parents[1]/'probe/LifecycleLab/Scripts/main.lua'

class ObserverTests(unittest.TestCase):
    def run_observer(self,visibility):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
        files={}; scheduled=nil; start_count=0
        os.getenv=function(k)if k=='AC8_LIFECYCLE_LAB'then return '25201480' else return 'test'end end
        os.time=function()return 100 end
        package.loadlib=function()return function()start_count=start_count+1 end end
        io.open=function(path,mode)
          if mode~='a'then files[path]=''end
          return {write=function(self,...)local t={...};for _,v in ipairs(t)do files[path]=(files[path]or'')..tostring(v)end end,close=function()end}
        end
        IsInGameThread=function()return true end
        ExecuteInGameThreadWithDelay=function(_,fn)scheduled=fn end
        widget={IsValid=function()return true end,GetFullName=function()return 'Widget MenuInstance'end,IsVisible=function()return true end,IsInViewport=function()return false end}
        FindAllOf=function(q)if q=='LiveMenuMainTopWidget'then return {widget}else return {}end end
        ''')
        lua.globals().widget.Visibility=visibility
        lua.execute(SOURCE.read_text());lua.globals().scheduled()
        return lua
    def test_nested_visible_menu_does_not_require_viewport(self):
        lua=self.run_observer(0)
        self.assertIn('main_menu\t1\n',lua.globals().files['test/game-observation.tsv'])
    def test_hidden_menu_not_admitted(self):
        lua=self.run_observer(2)
        self.assertIn('main_menu\t0\n',lua.globals().files['test/game-observation.tsv'])
    def test_history_written_only_on_change(self):
        lua=self.run_observer(0);first=lua.globals().files['test/game-transitions.tsv']
        lua.globals().scheduled()
        self.assertEqual(first,lua.globals().files['test/game-transitions.tsv'])
        self.assertEqual(1,lua.globals().start_count)
    def test_game_thread_error_does_not_publish_ready(self):
        lua=self.run_observer(0)
        lua.execute("files={};IsInGameThread=function()return false end")
        lua.globals().scheduled()
        self.assertIsNone(lua.globals().files['test/game-observation.tsv'])
        self.assertIn('wrong_thread',lua.globals().files['test/game-observation-errors.log'])

if __name__=='__main__':unittest.main()
