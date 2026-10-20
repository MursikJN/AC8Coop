"""Menu capture boundaries; mock UE only, not native engine validation."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0, r'D:\projects\unreal-mod-tools\packages\python-analysis')
from lupa import LuaRuntime

SOURCE = Path(__file__).resolve().parents[1] / 'probe/AC8CoopRecon/Scripts/menu_probe.lua'
FIXTURE = r'''
H={rows={},closed=false,reads={},count=1,fail=false,writes=0}
print=function() end
io.open=function() return {write=function(_,...) H.rows[#H.rows+1]=table.concat({...}) end,
 close=function() H.closed=true end} end
local function name(s) return {ToString=function() return s end} end
local props={{'Visibility','ByteProperty'},{'CurrentMenu','StrProperty'},{'AccessToken','StrProperty'}}
local cls={IsValid=function() return true end,GetFullName=function() return 'Class /Script/Live.LiveMenuBase' end,
 GetSuperStruct=function() return nil end,ForEachFunction=function() end}
cls.ForEachProperty=function(_,fn) for _,p in ipairs(props) do fn({GetFName=function() return name(p[1]) end,
 GetClass=function() return {GetFName=function() return name(p[2]) end} end,GetOffset_Internal=function() return 0 end}) end end
function FindAllOf(query)
 if H.fail then error('read query failure') end
 local result={}
 for i=1,H.count do
  result[i]=setmetatable({IsValid=function() return true end,GetFullName=function() return 'Widget Menu'..i end,
   GetAddress=function() return i end,GetClass=function() return cls end},{
   __index=function(_,k) H.reads[k]=true; if k=='Visibility' then return 0 elseif k=='CurrentMenu' then return 'Campaign' else error('unexpected field '..k) end end,
   __newindex=function() H.writes=H.writes+1;error('write forbidden') end})
 end
 return result
end
'''

class MenuProbeTests(unittest.TestCase):
    def capture(self, setup=''):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute(FIXTURE); lua.execute(setup)
        lua.execute(SOURCE.read_text(encoding='utf-8'))('out','sample')
        h=lua.globals().H
        return h, ''.join(h.rows.values())

    def test_readonly_deduplicates_and_does_not_read_secret(self):
        h,text=self.capture()
        self.assertTrue(h.closed); self.assertEqual(h.writes,0)
        self.assertIsNone(h.reads.AccessToken)
        self.assertIn('value\tWidget Menu1\tCurrentMenu\tCampaign',text)
        self.assertIn('instances\t1\n',text)
        self.assertIn('complete_within_queries\ttrue',text)

    def test_empty_inventory_never_complete(self):
        _,text=self.capture('H.count=0')
        self.assertIn('empty_inventory',text)
        self.assertIn('complete_within_queries\tfalse',text)

    def test_query_failure_still_closes_report(self):
        h,text=self.capture('H.fail=true')
        self.assertTrue(h.closed)
        self.assertIn('read query failure',text)
        self.assertIn('complete_within_queries\tfalse',text)

    def test_budget_limit_reported(self):
        _,text=self.capture('H.count=800')
        self.assertIn('instances\t768',text)
        self.assertIn('query_budget',text)
        self.assertIn('complete_within_queries\tfalse',text)

    def test_campaign_after_many_unrelated_widgets_is_still_captured(self):
        _,text=self.capture(r'''
local old=FindAllOf
local template=old('fixture')[1]
local base=template:GetClass()
local noise=old('fixture')[1]
noise.GetClass=function() return setmetatable({GetFullName=function() return 'Class /Game/Music/WaveBar' end},{__index=base}) end
template.GetClass=function() return setmetatable({GetFullName=function() return 'Class /Game/Campaign/Top' end},{__index=base}) end
FindAllOf=function(q)
 if q~='UserWidget' then return {} end
 local result={}; for i=1,799 do result[i]=noise end; result[800]=template; return result
end
''')
        self.assertIn('value\tWidget Menu1\tCurrentMenu\tCampaign',text)
        self.assertIn('instances\t1\n',text)
        self.assertIn('complete_within_queries\ttrue',text)

if __name__ == '__main__': unittest.main()
