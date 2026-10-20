"""Read-only Lua boundary tests. No live engine or native lifetime validation."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, r"D:\projects\unreal-mod-tools\packages\python-analysis")
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "probe/AC8CoopRecon/Scripts/network_lifecycle_probe.lua"

FIXTURE = r'''
H={files={},closed={},queries={},reads={},writes=0,calls=0,serial=1000,classes={},instances={}}
local function forbidden() H.calls=H.calls+1; error("forbidden operation") end
AC8ManualControl=setmetatable({}, {__index=forbidden,__pairs=forbidden,__newindex=forbidden})
RegisterKeyBind=forbidden; RegisterHook=forbidden; LoopAsync=forbidden
ExecuteWithDelay=forbidden; RegisterCustomProperty=forbidden; ExecuteInGameThread=forbidden
function H.name(value) return {ToString=function() return value end} end
function H.field(name,typ)
    return {GetFName=function() return H.name(name) end,
        GetClass=function() return {GetFName=function() return H.name(typ) end} end,
        GetOffset_Internal=function() return 32 end}
end
function H.each(values,callback)
    for _,value in ipairs(values) do if callback(value)==true then break end end
end
function H.fn(name,args)
    H.serial=H.serial+1; local address=H.serial
    return {IsValid=function() return true end,GetFullName=function() return "Function "..name end,
        GetAddress=function() return address end,GetFunctionFlags=function() return 1024 end,
        ForEachProperty=function(_,callback) H.each(args or {},callback) end}
end
function H.class(name,parent,fields,funcs,path)
    H.serial=H.serial+1; local address=H.serial
    local class={IsValid=function() return true end,
        GetFullName=function() return "Class "..(path or "/Script/Live.")..name end,
        GetFName=function() return H.name(name) end,
        GetAddress=function() return address end,GetSuperStruct=function() return parent end,
        ForEachProperty=function(_,callback) H.each(fields or {},callback) end,
        ForEachFunction=function(_,callback) H.each(funcs or {},callback) end}
    H.classes[#H.classes+1]=class
    return class
end
function H.obj(name,class,values)
    H.serial=H.serial+1
    local data={alive=true,address=H.serial,values=values or {}}
    local methods={IsValid=function() return data.alive end,GetFullName=function() return name end,
        GetAddress=function() return data.address end,GetClass=function() return class end}
    local obj=setmetatable({}, {
        __index=function(_,key)
            if methods[key] then return methods[key] end
            H.reads[#H.reads+1]=name..":"..key
            assert(data.alive,"stale instance")
            assert(data.values[key]~=nil,"absent property read "..key)
            return data.values[key]
        end,
        __newindex=function() H.writes=H.writes+1; error("instance write") end})
    return obj,data
end
function FindAllOf(name)
    H.queries[#H.queries+1]=name
    if H.query_error==name then error("query failed "..name) end
    if name=="Class" and H.empty_class_query then return nil end
    return name=="Class" and H.classes or H.instances[name]
end
function StaticFindObject(path)
    for _,class in ipairs(H.classes) do
        if class.GetFullName and class:GetFullName()=="Class "..path then return class end
    end
    return H.invalid
end
io.open=function(path,mode)
    if H.open_error and path:find(H.open_error,1,true) then return nil end
    assert(mode=="w"); H.files[path]=""
    return {write=function(_,...) for i=1,select('#',...) do H.files[path]=H.files[path]..tostring(select(i,...)) end end,
        close=function() H.closed[path]=true; return true end}
end
H.base=H.class("LiveGameObject",nil,{H.field("ObjectId","IntProperty")})
H.network=H.class("LiveNetworkPlayerObject",nil,
    {H.field("bReady","BoolProperty"),H.field("Ownership","IntProperty")},
    {H.fn("/Script/Live.LiveNetworkPlayerObject.OnMovement",{H.field("Value","FloatProperty")})})
H.player=H.class("LivePlayerPlane",H.base,
    {H.field("NetworkObject","ObjectProperty"),H.field("Controller","ObjectProperty"),
     H.field("PlaneTypeId","IntProperty"),H.field("CallsignId","NameProperty"),
     H.field("UnrelatedValue","FloatProperty"),H.field("NetworkData","StructProperty")})
H.net,H.net_data=H.obj("net",H.network,{bReady=true,Ownership=2})
H.invalid={IsValid=function() return false end}
H.plane,H.plane_data=H.obj("plane",H.player,
    {NetworkObject=H.net,Controller=H.invalid,PlaneTypeId=23010,CallsignId=H.name("Joker1"),ObjectId=42})
H.instances.LiveNetworkPlayerObject={H.net}; H.instances.LivePlayerPlane={H.plane}
'''


class NetworkLifecycleProbe(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(FIXTURE)
        self.capture = self.lua.execute(SOURCE.read_text(encoding="utf-8"))

    def run_lua(self, code):
        self.lua.execute(code)

    def report(self, stamp="one"):
        return self.lua.globals().H.files[f"mock/network-lifecycle-{stamp}.tsv"]

    def test_empty_class_query_uses_known_native_types(self):
        self.run_lua('H.empty_class_query=true')
        self.capture("mock", "one")
        self.assertIn("property\tClass /Script/Live.LivePlayerPlane\tNetworkObject", self.report())
        self.assertIn("value\tplane\tPlaneTypeId\t23010", self.report())

    def test_no_available_types_does_not_claim_complete(self):
        self.run_lua('H.classes={}; H.empty_class_query=true')
        self.capture("mock", "one")
        self.assertIn("no_selected_classes", self.report())
        self.assertNotIn("\tcomplete\ttrue", self.report())

    def test_empty_class_query_finds_real_network_class_and_function(self):
        self.run_lua('''
            H.empty_class_query=true
            local cls=H.class("LiveNetworkPlayerPlane",nil,{H.field("Actor","ObjectProperty")},
                {H.fn("/Script/Live.LiveNetworkPlayerPlane.OnMovement",{})})
            H.instances.LiveNetworkPlayerPlane={(H.obj("realnet",cls,{Actor=H.plane}))}
        ''')
        self.capture("mock", "one")
        self.assertIn("reference\trealnet\tActor\tplane address=", self.report())
        self.assertIn("Function /Script/Live.LiveNetworkPlayerPlane.OnMovement",
                      self.lua.globals().H.files["mock/network-native-addresses-one.tsv"])

    def test_standalone_metadata_schema_first_and_no_mutation(self):
        self.capture("mock", "one")
        text = self.report()
        self.assertIn("property\tClass /Script/Live.LivePlayerPlane\tNetworkObject", text)
        self.assertIn("value\tplane\tPlaneTypeId\t23010", text)
        self.assertIn("value\tplane\tObjectId\t42", text)
        self.assertIn("value\tplane\tCallsignId\tJoker1", text)
        self.assertIn("reference\tplane\tController\tinvalid", text)
        self.assertIn("argument\tFunction /Script/Live.LiveNetworkPlayerObject.OnMovement", text)
        self.assertNotIn("\nerror\t", text)
        self.run_lua('assert(H.writes==0 and H.calls==0); for _,r in ipairs(H.reads) do assert(not r:find("Unrelated") and not r:find("NetworkData")) end')

    def test_native_address_contract_and_output_files_closed(self):
        self.capture("mock", "one")
        text = self.lua.globals().H.files["mock/network-native-addresses-one.tsv"]
        self.assertTrue(text.startswith("kind\tname\taddress\nufunction\tFunction "))
        self.assertRegex(text, r"\t0x[0-9A-F]+\n$")
        self.run_lua('assert(H.closed["mock/network-lifecycle-one.tsv"] and H.closed["mock/network-native-addresses-one.tsv"])')

    def test_recapture_reacquires_instances_and_does_not_touch_stale_handles(self):
        self.capture("mock", "one")
        self.run_lua('''
            H.plane_data.alive=false; H.net_data.alive=false
            H.instances.LiveNetworkPlayerObject={}
            H.instances.LivePlayerPlane={H.obj("replacement",H.player,
                {NetworkObject=H.invalid,Controller=H.invalid,PlaneTypeId=100,CallsignId=H.name("New"),ObjectId=43})}
            H.reads={}
        ''')
        self.capture("mock", "two")
        self.assertIn("value\treplacement\tPlaneTypeId\t100", self.report("two"))
        self.run_lua('for _,r in ipairs(H.reads) do assert(not r:match("^plane:") and not r:match("^net:")) end')

    def test_missing_and_invalid_instances_do_not_read_fields(self):
        self.run_lua('H.instances.LivePlayerPlane={H.invalid}; H.instances.LiveNetworkPlayerObject=nil; H.reads={}')
        self.capture("mock", "one")
        self.assertIn("invalid_handle", self.report())
        self.run_lua('assert(#H.reads==0)')

    def test_query_failure_reported_and_outputs_closed(self):
        self.run_lua('H.query_error="LivePlayerPlane"')
        self.capture("mock", "one")
        self.assertIn("instances_query\t", self.report())
        self.run_lua('assert(H.closed["mock/network-lifecycle-one.tsv"] and H.closed["mock/network-native-addresses-one.tsv"])')

    def test_open_second_output_failure_closes_first(self):
        self.run_lua('H.open_error="network-native-addresses"')
        with self.assertRaises(Exception):
            self.capture("mock", "one")
        self.run_lua('assert(H.closed["mock/network-lifecycle-one.tsv"])')

    def test_subclasses_selected_but_generic_gameobject_descendants_excluded(self):
        self.run_lua('''
            H.class("BP_PlayerPlane_F14D_C",H.player,{}, {},"/Game/")
            H.class("UnrelatedActor",H.base,{}, {},"/Game/")
        ''')
        self.capture("mock", "one")
        self.run_lua('''
            local yes=false
            for _,q in ipairs(H.queries) do
                if q=="BP_PlayerPlane_F14D_C" then yes=true end
                assert(q~="UnrelatedActor")
            end
            assert(yes)
        ''')

    def test_unrelated_class_hierarchy_is_never_queried(self):
        self.run_lua('''
            H.ancestry_reads=0
            for i=1,100 do
                local cls=H.class("UnrelatedActor"..i,H.base,{},{},"/Game/")
                cls.GetSuperStruct=function() H.ancestry_reads=H.ancestry_reads+1; error("unrelated hierarchy") end
            end
        ''')
        self.capture("mock", "one")
        self.run_lua('assert(H.ancestry_reads==0)')
        self.assertNotIn("unrelated hierarchy", self.report())

    def test_network_actor_owner_links_and_string_identity(self):
        self.run_lua('''
            local cls=H.class("LiveNetworkLinks",nil,
                {H.field("Actor","ObjectProperty"),H.field("Owner","ObjectProperty"),
                 H.field("Manager","ObjectProperty"),H.field("SessionId","StrProperty")})
            H.instances.LiveNetworkLinks={(H.obj("links",cls,
                {Actor=H.plane,Owner=H.net,Manager=H.invalid,SessionId=H.name("session-123")}))}
        ''')
        self.capture("mock", "one")
        text = self.report()
        self.assertIn("reference\tlinks\tActor\tplane address=", text)
        self.assertIn("reference\tlinks\tOwner\tnet address=", text)
        self.assertIn("reference\tlinks\tManager\tinvalid", text)
        self.assertIn("value\tlinks\tSessionId\tsession-123", text)
        self.assertNotIn("\nerror\t", text)

    def test_property_function_argument_and_instance_caps(self):
        self.run_lua('''
            local fields,args,funcs={}, {}, {}
            for i=1,300 do fields[i]=H.field("State"..i,"IntProperty") end
            for i=1,40 do args[i]=H.field("Arg"..i,"FloatProperty") end
            for i=1,270 do funcs[i]=H.fn("/Script/Live.LiveNetworkBig.Fn"..i,args) end
            H.class("LiveNetworkBig",nil,fields,funcs)
            H.instances.LiveNetworkPlayerObject={}
            for i=1,10 do H.instances.LiveNetworkPlayerObject[i]=H.obj("net"..i,H.network,{bReady=true,Ownership=2}) end
        ''')
        self.capture("mock", "one")
        text = self.report()
        for token in ("\tproperty\t256", "\tfunctions\t256", "\targument\t32", "\tinstances_per_class\t8"):
            self.assertIn(token, text)
        self.assertNotIn("\tState257\t", text)
        self.assertNotIn("\tArg33\t", text)
        self.assertNotIn("instance\tnet9\t", text)

    def test_class_match_and_total_instance_caps(self):
        self.run_lua('''
            for i=1,140 do
                local name="LiveNetworkExtra"..i
                local cls=H.class(name,nil,{},{})
                H.instances[name]={(H.obj("extra"..i,cls,{}))}
            end
        ''')
        self.capture("mock", "one")
        self.assertIn("limit\tClass\tmatched\t128", self.report())
        count = sum(line.startswith("instance\t") for line in self.report().splitlines())
        self.assertLessEqual(count, 128)

    def test_hierarchy_cycles_and_metadata_error_are_reported(self):
        self.run_lua('''
            local cls=H.class("LiveNetworkBroken",nil,{},{})
            cls.GetSuperStruct=function() return cls end
            cls.ForEachProperty=function() error("broken properties") end
        ''')
        self.capture("mock", "one")
        self.assertIn("hierarchy\tcycle", self.report())
        self.assertIn("broken properties", self.report())

    def test_total_instances_and_hierarchy_depth_are_bounded(self):
        self.run_lua('''
            for i=1,20 do
                local name="LiveNetworkMany"..i
                local cls=H.class(name,nil,{},{})
                H.instances[name]={}
                for j=1,8 do H.instances[name][j]=H.obj(name.."instance"..j,cls,{}) end
            end
            local cls=H.player
            for i=1,20 do cls=H.class("DeepPlayerPlane"..i,cls,{},{},"/Game/") end
        ''')
        self.capture("mock", "one")
        text = self.report()
        self.assertIn("\tinstances_total\t128", text)
        self.assertIn("\thierarchy\t16", text)
        self.assertEqual(sum(line.startswith("instance\t") for line in text.splitlines()), 128)

    def test_class_query_failure_still_closes_outputs(self):
        self.run_lua('H.query_error="Class"')
        self.capture("mock", "one")
        self.assertIn("error\tClass\tquery", self.report())
        self.assertNotIn("\tcomplete\ttrue", self.report())
        self.run_lua('assert(H.closed["mock/network-lifecycle-one.tsv"] and H.closed["mock/network-native-addresses-one.tsv"])')

    def test_visited_class_bound(self):
        self.run_lua('''
            local invalid={IsValid=function() return false end}
            H.classes={}
            for i=1,50001 do H.classes[i]=invalid end
        ''')
        self.capture("mock", "one")
        self.assertIn("limit\tClass\tvisited\t50000", self.report())


if __name__ == "__main__":
    unittest.main()
