from pathlib import Path
import unittest
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]

class OrdersTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        F={};R={};P={};THREAD=true
        API={find=function(q)return F[q]or{}end,
          register=function(p)P[#P+1]=p end,types={ByteProperty=1,IntProperty=2,NameProperty=3,StrProperty=4},
          is_game_thread=function()return THREAD end}
        function emit(...)R[#R+1]={...}end
        function obj(q,n)
         local o={};o.IsValid=function()return true end;o.GetFullName=function()return n end
         o.IsA=function(_,c)return c=='/Script/Live.'..q end;o.GetAddress=function()return 123 end
         o.GetWorld=function()return obj('World','World /Game/Maps/Ingame/Mission007/PL_Mission007.X')end
         return o
        end
        CTX='/Mission007/PL_Mission007'
        ''')
        self.lua.globals().M=self.lua.execute((ROOT/'probe/Mission6Capture/Scripts/orders.lua').read_text())
        self.lua.execute('S=M.new(API)')

    def test_manager_zero_and_repeat(self):
        self.lua.execute('''
        local o=obj('LiveWingmanManager','LiveWingmanManager /Engine/Transient.X')
        o.AC8Observe_LiveWingmanManager_Mode=0;o.AC8Observe_LiveWingmanManager_RepeatFlag=0
        o.AC8Observe_LiveWingmanManager_RepeatCount=2;F.LiveWingmanManager={o}
        S.sample(CTX,emit);assert(#R==4 and #P==#M.fields)
        o.AC8Observe_LiveWingmanManager_RepeatCount=3;S.sample(CTX,emit);assert(#P==#M.fields)
        assert(R[3][4]==2 and R[7][4]==3)
        ''')

    def test_wrong_context_or_thread(self):
        self.lua.execute('''S.sample('MainMenu',emit);assert(#R==0 and #P==0)
        THREAD=false;assert(not pcall(S.sample,CTX,emit));assert(#P==0)''')

    def test_cdo_class_and_map_filtered(self):
        self.lua.execute('''
        local q='LiveAIWingmanStateComponent'
        F[q]={obj(q,'Default__LiveAIWingmanStateComponent'),obj(q,q..' /OtherMap.X'),
        obj('WrongClass',q..' '..CTX..'.X')}
        S.sample(CTX,emit);assert(#R==1 and R[1][4]==0)
        ''')

    def test_bad_value_and_identity_are_not_emitted(self):
        self.lua.execute('''
        local q='LiveAIWingmanStateComponent';local o=obj(q,q..' '..CTX..'.X')
        F[q]={o};o.AC8Observe_LiveAIWingmanStateComponent_State=256
        assert(not pcall(S.sample,CTX,emit));assert(#R==0)
        o.AC8Observe_LiveAIWingmanStateComponent_State=1
        local n=0;o.GetAddress=function()n=n+1;return n end
        assert(not pcall(S.sample,CTX,emit));assert(#R==0)
        ''')

    def test_target_name_and_leave_zero(self):
        self.lua.execute('''
        local q='LiveWingmanJoinOrLeaveExecution';local o=obj(q,q..' '..CTX..'.LiveEventSubsystem.X')
        o.AC8Observe_LiveWingmanJoinOrLeaveExecution_Target={ToString=function()return 'Joker2'end}
        o.AC8Observe_LiveWingmanJoinOrLeaveExecution_Leave=0;F[q]={o}
        S.sample(CTX,emit);assert(R[1][4]=='Joker2'and R[2][4]==0)
        ''')

    def test_transient_execution_is_not_mission_evidence(self):
        self.lua.execute('''local q='LiveWingmanJoinOrLeaveExecution'
        F[q]={obj(q,q..' /Engine/Transient.X')};S.sample(CTX,emit)
        assert(#R==1 and R[1][4]==0)''')

    def test_budget(self):
        self.lua.execute('''F.LiveWingmanManager={};for i=1,65 do
        F.LiveWingmanManager[i]=obj('LiveWingmanManager','Default__X')end
        assert(not pcall(S.sample,CTX,emit));assert(#R==0)''')

    def test_invincibility_selector_names_and_false(self):
        self.lua.execute('''local q='LiveSetIsInvincibleFromWingman';local o=obj(q,q..' '..CTX..'.Event.X')
        o.AC8Observe_LiveSetIsInvincibleFromWingman_ObjectName={ToString=function()return 'None'end}
        o.AC8Observe_LiveSetIsInvincibleFromWingman_UnitName={ToString=function()return 'Wingman_Baxter_0'end}
        o.AC8Observe_LiveSetIsInvincibleFromWingman_GroupName={ToString=function()return 'None'end}
        o.AC8Observe_LiveSetIsInvincibleFromWingman_RequestedFlag=0;F[q]={o}
        S.sample(CTX,emit);assert(#R==5 and R[2][4]=='Wingman_Baxter_0'and R[4][4]==0)''')

    def test_input_string_forms_and_budget(self):
        self.lua.execute('''local q='LiveInputWingmanStateStatement';local o=obj(q,q..' '..CTX..'.Event.X');F[q]={o}
        o.AC8Observe_LiveInputWingmanStateStatement_ExpectedInput='Support';S.sample(CTX,emit);assert(R[1][4]=='Support')
        R={};o.AC8Observe_LiveInputWingmanStateStatement_ExpectedInput={ToString=function()return 'Arbitrary'end}
        S.sample(CTX,emit);assert(R[1][4]=='Arbitrary')
        R={};o.AC8Observe_LiveInputWingmanStateStatement_ExpectedInput=string.rep('X',513)
        assert(not pcall(S.sample,CTX,emit));assert(#R==0)''')

if __name__=='__main__':unittest.main()
