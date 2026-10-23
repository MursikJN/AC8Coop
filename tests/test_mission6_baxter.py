import unittest
from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]

class BaxterWatchTests(unittest.TestCase):
    def test_watch_reacquires_filters_and_rotates_names(self):
        lua=LuaRuntime()
        lua.globals().SOURCE=(ROOT/'probe/Mission6Capture/Scripts/baxter.lua').read_text()
        lua.execute('''
        local B=assert(load(SOURCE))()
        local names={'LiveAIWingmanStateComponent /Mission007/PL_Mission007:A',
                     'LiveAIWingmanStateComponent /Other:B',
                     'LiveAIWingmanStateComponent /Mission007/PL_Mission007:C'}
        local w=B.new({discover=function()return names end})
        assert(w.next_watch(nil,'menu')==nil)
        assert(w.next_watch(nil,'/Mission007/PL_Mission007').name:sub(-1)=='A')
        assert(w.next_watch(nil,'/Mission007/PL_Mission007').name:sub(-1)=='C')
        names={'LiveAIWingmanStateComponent /Mission007/PL_Mission007:NEW'}
        assert(w.next_watch(nil,'/Mission007/PL_Mission007').name:sub(-3)=='NEW')
        names={};assert(w.next_watch(nil,'/Mission007/PL_Mission007')==nil)
        names={};for i=1,13 do names[i]='/Mission007/PL_Mission007:'..i end
        assert(not pcall(w.next_watch,nil,'/Mission007/PL_Mission007'))
        ''')

if __name__=='__main__':unittest.main()
