"""Read-only collector contracts with fake UE wrappers; no game/physics validation."""
from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = r'''
ROWS={}; FOUND={}; CLOCK=0
function fname(s)return {ToString=function()return s end}end
function prop(n,t,offset)return {GetFName=function()return fname(n)end,
 GetClass=function()return {GetFName=function()return fname(t)end}end,
 GetOffset_Internal=function()return offset or 0 end}end
function meta(n,fields)return {IsValid=function()return true end,GetFullName=function()return n end,
 ForEachProperty=function(_,cb)for _,p in ipairs(fields)do if cb(p)then break end end end,
 GetSuperStruct=function()return nil end}end
function obj(n,fields,id,t)
 local m=meta('Class /Script/Live.Test',fields)
 return {IsValid=function()return true end,GetFullName=function()return n end,
 GetAddress=function()return id or 1 end,GetClass=function()return m end,
 type=function()return t or 'UObject'end,IsA=function(_,q)return t=='UDataTable'and q=='/Script/Engine.DataTable'end}
end
function array(values)return setmetatable({type=function()return 'TArray'end,
 GetArrayNum=function()return #values end},{__index=function(_,i)return values[i]end})end
function map(entries)return setmetatable({type=function()return 'TMap'end,
 ForEach=function(_,cb)for _,pair in ipairs(entries)do
  if cb({get=function()return pair[1]end},{get=function()return pair[2]end})then break end
 end end},{__len=function()return #entries end})end
function struct(n,fields,values)
 local s=meta(n,fields);s.type=function()return 'UScriptStruct'end
 for k,v in pairs(values)do s[k]=v end;return s
end
API={clock=function()CLOCK=CLOCK+0.00001;return CLOCK end,
 find=function(q)return FOUND[q]or{}end,
 emit=function(...)ROWS[#ROWS+1]={...}end}
L={objects=20,entries=20,rows=2000,depth=8,seconds=1}
function has(kind,part,value)
 for _,r in ipairs(ROWS)do if r[1]==kind and tostring(r[2]):find(part,1,true)and (value==nil or tostring(r[4])==value)then return true end end
 return false
end
'''

class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FIXTURE)
        self.lua.globals().C = self.lua.execute((ROOT/'probe/Mission6Capture/Scripts/capture.lua').read_text())

    def check(self, code):
        self.lua.execute(code)

    def test_ordered_keys_and_row_values(self):
        self.check('''
        local o=obj('LiveIndexSavedDataTable /Game/Mission007.Actions', {prop('KeyIndexData','ArrayProperty')},1,'UDataTable')
        o.KeyIndexData=array({fname('B'),fname('A')})
        -- Real FName wrappers expose type().
        for i=1,2 do o.KeyIndexData[i].type=function()return 'FName'end end
        local row=struct('ScriptStruct /Script/Live.LiveAIActionEventTable',{prop('ActionClass','ClassProperty')},{ActionClass=obj('Class Action',{},3,'UClass')})
        o.GetRowStruct=function()return row end
        o.ForEachRow=function(_,cb)cb('B',row)end
        FOUND.LiveIndexSavedDataTable={o}
        R=C.capture(API,'test',L)
        assert(R.ok and R.gaps==0)
        assert(has('value','KeyIndexData[0]','B')and has('value','KeyIndexData[1]','A'))
        assert(has('table_row','Actions','B')and has('reference','rows[B].ActionClass','Class Action'))
        ''')

    def test_map_values_and_cycles(self):
        self.check('''
        local o=obj('LiveEventContainer Mission007', {prop('ExecutionCollection','MapProperty'),prop('Self','ObjectProperty')})
        o.Self=o;o.ExecutionCollection=map({{12,struct('LiveEventData',{prop('EventHash','IntProperty')},{EventHash=77})}})
        FOUND.LiveEventContainer={o}
        R=C.capture(API,'test',L)
        assert(R.ok and R.objects==1)
        assert(has('value','{entry1}.key','12')and has('value','EventHash','77'))
        ''')

    def test_cdo_and_unsupported_wrapper_are_not_data(self):
        self.check('''
        local o=obj('LiveEventContainer Mission007',{prop('Map','MapProperty')})
        o.Map={type=function()return 'TrivialObject'end}
        FOUND.LiveEventContainer={obj('LiveEventContainer Default__LiveEventContainer',{}),o}
        R=C.capture(API,'test',L)
        assert(R.objects==1 and R.gaps==1 and has('gap','.Map','TrivialObject'))
        ''')

    def test_array_and_global_budgets_explicit(self):
        self.check('''
        local o=obj('LiveEventContainer Mission007',{prop('Items','ArrayProperty')})
        o.Items=array({1,2,3});FOUND.LiveEventContainer={o};L.entries=1
        R=C.capture(API,'test',L);assert(R.gaps>0 and has('gap','.Items','3'))
        ROWS={};L.rows=3;R=C.capture(API,'test',L)
        assert(not R.ok and ROWS[#ROWS][1]=='summary'and ROWS[#ROWS][3]=='aborted')
        ''')

    def test_time_budget_and_read_error(self):
        self.check('''
        L.seconds=0;R=C.capture(API,'test',L);assert(not R.ok)
        L.seconds=1;ROWS={}
        local o=obj('LiveEventContainer Mission007',{prop('Missing','IntProperty')})
        FOUND.LiveEventContainer={o};R=C.capture(API,'test',L)
        assert(R.ok and R.gaps>0)
        ''')

    def test_snapshot_reacquires_objects(self):
        self.check('''
        FOUND.LiveEventContainer={obj('LiveEventContainer Old',{},1)}
        R=C.capture(API,'first',L);assert(R.objects==1)
        FOUND.LiveEventContainer={obj('LiveEventContainer New',{},2)};ROWS={}
        R=C.capture(API,'second',L)
        assert(has('object','New')and not has('object','Old'))
        ''')

    def test_context_change_marks_inconsistent_sample(self):
        self.check('''
        local n=0
        API.find=function(q)if q=='World'then n=n+1;return {obj('World '..n,{},n)}end return {}end
        R=C.capture(API,'test',L);assert(R.context_changed and R.gaps>0)
        ''')

    def test_old_table_wrapper_is_gap(self):
        self.check('''
        local o=obj('LiveIndexSavedDataTable /Game/Mission007.Actions',{},1)
        o.IsA=function()return true end;FOUND.LiveIndexSavedDataTable={o}
        R=C.capture(API,'test',L);assert(R.ok and has('gap','Actions','UObject'))
        ''')

    def test_false_and_zero_are_preserved(self):
        self.check('''
        local o=obj('LiveEventContainer Mission007',{prop('Active','BoolProperty'),prop('Count','IntProperty')})
        o.Active=false;o.Count=0;FOUND.LiveEventContainer={o}
        R=C.capture(API,'test',L)
        assert(has('value','.Active','false')and has('value','.Count','0'))
        ''')

    def test_bootstrap_coalesces_and_stops_on_wrong_thread(self):
        source=(ROOT/'probe/Mission6Capture/Scripts/main.lua').read_text()
        self.lua.globals().MAIN=source
        self.check('''
        local files={};local timers={};local keys={};local pending={}
        os.getenv=function(k)if k=='AC8_MISSION6_CAPTURE'then return '25201480'end return 'out'end
        loadfile=function()return function()return C end end
        io.open=function(path,mode)return {write=function(_,...)files[path]=(files[path]or'')..table.concat({...});return true end,close=function()end}end
        Key={F8=8,F10=10};RegisterKeyBind=function(k,cb)keys[k]=cb end
        LoopAsync=function(_,cb)timers[1]=cb end
        ExecuteInGameThread=function(cb)pending[#pending+1]=cb end
        IsInGameThread=function()return false end;FindAllOf=API.find
        assert(load(MAIN))();timers[1]();timers[1]();keys[8]()
        assert(#pending==1);pending[1]();assert(timers[1]()==true)
        assert(files['out/timeline.tsv']:find('wrong_thread',1,true))
        ''')

    def test_partition_reads_one_root_without_query_starvation_or_following_refs(self):
        self.check('''
        local a=obj('LiveEventContainer A',{prop('Peer','ObjectProperty')},1)
        local b=obj('LiveEventContainer B',{prop('Count','IntProperty')},2);b.Count=42;a.Peer=b
        FOUND.LiveEventContainer={b,a,obj('LiveEventContainer Default__X',{},3)}
        local original=API.find
        API.find=function(q)
         if q=='LiveIndexSavedDataTable'then error('unrelated query must not run')end
         return original(q)
        end
        local names=C.discover(API.find,'LiveEventContainer')
        assert(#names==2 and names[1]=='LiveEventContainer A' and type(names[1])=='string')
        R=C.capture(API,'slice',L,{query='LiveEventContainer',name=names[1]})
        assert(R.ok and R.objects==1 and has('reference','.Peer','LiveEventContainer B'))
        assert(not has('object','LiveEventContainer B'))
        -- Simulate destruction/travel before the next tick: no stale object reuse.
        FOUND.LiveEventContainer={};ROWS={}
        R=C.capture(API,'slice',L,{query='LiveEventContainer',name=names[2]})
        assert(R.objects==0 and R.gaps>0)
        ''')

    def test_partition_reacquires_replaced_object_by_name(self):
        self.check('''
        local o=obj('LiveEventContainer A',{prop('Count','IntProperty')},1);o.Count=1
        FOUND.LiveEventContainer={o};local names=C.discover(API.find,'LiveEventContainer')
        local replacement=obj(names[1],{prop('Count','IntProperty')},2);replacement.Count=2
        FOUND.LiveEventContainer={replacement}
        R=C.capture(API,'slice',L,{query='LiveEventContainer',name=names[1]})
        assert(R.ok and has('value','.Count','2'))
        ''')

    def test_scheduler_progresses_slices_and_discards_queue_on_world_change(self):
        self.lua.globals().MAIN=(ROOT/'probe/Mission6Capture/Scripts/main.lua').read_text()
        self.check('''
        local files,timers,keys,calls={},{},{},{}
        local world='A'
        C.context=function()return world end
        C.discover=function(_,q)calls[#calls+1]='discover:'..q;return {'one','two'}end
        C.capture=function(_,_,_,s)calls[#calls+1]='read:'..s.query..':'..s.name end
        os.getenv=function(k)if k=='AC8_MISSION6_CAPTURE'then return '25201480'end return 'out'end
        loadfile=function()return function()return C end end
        io.open=function(path)return {write=function(_,...)files[path]=(files[path]or'')..table.concat({...})end,close=function()end}end
        Key={F8=8,F10=10};RegisterKeyBind=function(k,cb)keys[k]=cb end
        LoopAsync=function(_,cb)timers[1]=cb end
        ExecuteInGameThread=function(cb)cb()end
        IsInGameThread=function()return true end;FindAllOf=function()return {}end
        assert(load(MAIN))()
        timers[1]();timers[1]();timers[1]();timers[1]()
        assert(calls[1]=='discover:LiveEventSubsystem')
        assert(calls[2]=='read:LiveEventSubsystem:one'and calls[3]=='read:LiveEventSubsystem:two')
        assert(calls[4]=='discover:LiveEventContainer')
        world='B';timers[1]()
        assert(calls[5]=='discover:LiveEventSubsystem')
        keys[10]();assert(timers[1]()==true)
        ''')

if __name__ == '__main__':
    unittest.main()
