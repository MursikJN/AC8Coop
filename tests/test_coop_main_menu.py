"""Stock widget-tree adapter: short clicks, input release and fail-closed attachment."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
FIXTURE=r'''
H={created={},keys={},hover={},down={},configured=0,ready=0,mode='original'}
FText=function(x)return x end;FName=function(x)return x end;Key={LEFT_MOUSE_BUTTON=1}
RegisterKeyBind=function(k,fn)H.keys[k]=fn end
local object
local function slot()
 return {IsValid=function()return true end,SetPadding=function()end,SetHorizontalAlignment=function()end,
 GetPosition=function()return {X=0,Y=0}end,GetAnchors=function()return {Minimum={X=0,Y=0},Maximum={X=0,Y=0}}end,
 GetAlignment=function()return {X=0,Y=0}end,SetAnchors=function()end,SetAlignment=function()end,
 SetPosition=function()end,SetSize=function()end}
end
object=function(name,kind)
 local o={name=name,kind=kind,Font={},Visibility=0,bIsEnabled=true,children={},Slot=slot(),text='',selected=0}
 function o:IsValid()return not self.invalid end
 function o:GetFullName()return self.name end
 function o:IsA(path)return self.kind==path end
 function o:SetText(t)self.text=t end
 function o:GetText()local s=self.text;return {ToString=function()return s end}end
 function o:SetColorAndOpacity()end;function o:SetBackgroundColor()end;function o:SetAutoWrapText()end
 function o:SetForegroundColor()end
 function o:SetVisibility(v)self.Visibility=v end;function o:SetIsEnabled(v)self.bIsEnabled=v end
 function o:SetIsReadOnly(v)self.readonly=v end;function o:SetHintText()end
 function o:GetParent()return self.parent end
 function o:RemoveFromParent()self.parent=nil end
 function o:AddChild(c)c.parent=self;self.children[#self.children+1]=c;return slot()end
 o.AddChildToGrid=o.AddChild;o.AddChildToCanvas=o.AddChild;o.AddChildToVerticalBox=o.AddChild
 function o:GetChildAt(i)return self.children[i+1]end
 function o:ForceLayoutPrepass()end
 function o:AddOption()end;function o:SetSelectedIndex(i)self.selected=i end;function o:GetSelectedIndex()return self.selected end
 function o:IsPressed()return H.down[self.name]==true end;function o:IsHovered()return H.hover[self.name]==true end
 return o
end
H.pc=object('pc','');H.pc.bShowMouseCursor=false
H.library=object('library','')
H.library.SetInputMode_UIOnlyEx=function()H.mode='ui_only'end
H.library.SetInputMode_GameAndUIEx=function()H.mode='game_and_ui'end
package.preload.UEHelpers=function()return {GetPlayerController=function()return H.pc end}end
H.canvas=object('canvas','/Script/UMG.CanvasPanel')
H.grid=object('WidgetTree.GridPanelMain','/Script/UMG.GridPanel');H.grid.parent=H.canvas;H.grid.Visibility=4
H.spacer=object('spacer','/Script/UMG.Spacer');H.spacer.Size={Y=300};H.grid.children={H.spacer}
H.exit=object('exit','');H.exit.parent=H.grid
H.hidden=object('reserved','');H.hidden.Visibility=1
H.list=object('list','');H.list.WBP_Menu_Text_Focus_000_06=H.exit;H.list.WBP_Menu_Text_Focus_000_07=H.hidden
H.main=object('main','');H.main.CommandList=H.list;H.main.WidgetTree=object('tree','')
H.main.GetClass=function()return {GetFullName=function()return 'WidgetBlueprintGeneratedClass /Game/Blueprints/UI/Menu/Main/WBP_Menu_MainTop_000.WBP_Menu_MainTop_000_C'end}end
FindAllOf=function()return {H.main}end
StaticFindObject=function(path)
 if path=='/Script/UMG.Default__WidgetBlueprintLibrary'then return H.library end
 if path:find(':',1,true)then
  local fields=path:find('AddChildToGrid',1,true)and {{'Content','ObjectProperty'},{'InRow','IntProperty'},{'InColumn','IntProperty'},{'ReturnValue','ObjectProperty'}}or
    path:find('SetText',1,true)and {{'InText','TextProperty'}}or{{'ReturnValue','BoolProperty'}}
  return {IsValid=function()return true end,ForEachProperty=function(_,fn)
   for _,p in ipairs(fields)do fn({GetFName=function()return {ToString=function()return H.bad_signature and 'Changed'or p[1]end}end,
    GetClass=function()return {GetFName=function()return {ToString=function()return p[2]end}end}end})end end}
 end
 return {IsValid=function()return true end,path=path}
end
StaticConstructObject=function(cls,outer,name)local key=name:gsub('_AC8UI%d+$','');local o=object(key,cls.path);o.native_name=name;H.created[key]=o;return o end
OPTIONS={configure=function(role,peer)assert(#peer==17,'Enter 17 digits');H.configured=H.configured+1 end,
ready=function()H.ready=H.ready+1 end,status=function()return 'waiting'end}
'''
class MainMenuTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE)
        self.lua.globals().M=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/coop_main_menu.lua').read_text(encoding='utf-8'))
    def runlua(self,s):self.lua.execute(s)
    def get(self,s):return self.lua.eval(s)
    def attach(self):self.runlua('UI=M.attach(OPTIONS)')
    def open(self):self.attach();self.runlua("H.hover.AC8_Coop_Entry=true;H.keys[1]();UI.refresh();H.hover.AC8_Coop_Entry=false")
    def click(self,name):self.runlua(f"H.hover['{name}']=true;H.keys[1]();UI.refresh();H.hover['{name}']=false")
    def test_short_click_opens_inside_original_widget_tree(self):
        self.open();self.assertTrue(self.get('UI.open'));self.assertEqual(self.get('UI.page.parent==H.canvas'),True)
        self.assertEqual(self.get('H.grid.Visibility'),2);self.assertEqual(self.get('H.mode'),'ui_only')
    def test_changed_signature_or_used_reserved_row_blocks_construction(self):
        self.runlua('H.bad_signature=true');self.assertRaises(Exception,self.attach)
        self.assertEqual(self.get('next(H.created)==nil'),True)
        self.runlua('H.bad_signature=false;H.hidden.Visibility=0');self.attach();self.assertIsNone(self.get('UI'))
        self.assertEqual(self.get('next(H.created)==nil'),True)
    def test_empty_peer_does_not_enable_ready_or_run(self):
        self.open();self.click('AC8_Coop_Configure');self.click('AC8_Coop_Ready')
        self.assertEqual(self.get('H.configured'),0);self.assertEqual(self.get('H.ready'),0)
        self.assertIn('17 digits',self.get('UI.status.text'))
    def test_success_freezes_settings_and_ready_requires_own_click(self):
        self.open();self.runlua("UI.peer.text='76561198000000002'");self.click('AC8_Coop_Configure')
        self.assertEqual(self.get('H.configured'),1);self.assertEqual(self.get('H.ready'),0);self.assertTrue(self.get('UI.peer.readonly'))
        self.click('AC8_Coop_Configure');self.assertEqual(self.get('H.configured'),1)
        self.click('AC8_Coop_Ready');self.click('AC8_Coop_Ready');self.assertEqual(self.get('H.ready'),1)
    def test_back_restores_native_grid_and_releases_ui_input(self):
        self.open();self.click('AC8_Coop_Back');self.assertFalse(self.get('UI.open'))
        self.assertEqual(self.get('H.grid.Visibility'),4);self.assertEqual(self.get('H.mode'),'game_and_ui');self.assertFalse(self.get('H.pc.bShowMouseCursor'))
    def test_old_menu_loop_stops_when_its_owner_is_replaced(self):
        self.attach();self.runlua('AC8MainMenuEntry=nil');self.assertFalse(self.get('UI.refresh()'))
    def lobby(self):
        self.runlua("OPTIONS.lobby=true;H.host=true;H.can_ready=false;H.can_start=false;H.launches=0;OPTIONS.start=function()H.launches=H.launches+1 end;OPTIONS.view=function()return {host=H.host,can_ready=H.can_ready,can_start=H.can_start,ready=false}end")
        self.open()
    def test_lobby_ready_waits_for_connected_peer(self):
        self.lobby();self.click('AC8_Coop_Ready');self.assertEqual(self.get('H.ready'),0)
        self.runlua('H.can_ready=true;UI.refresh()');self.click('AC8_Coop_Ready')
        self.assertEqual(self.get('H.ready'),1);self.assertTrue(self.get('UI.open'))
    def test_lobby_launch_waits_for_both_ready(self):
        self.lobby();self.click('AC8_Coop_Launch');self.assertEqual(self.get('H.launches'),0)
        self.runlua('H.can_start=true;UI.refresh()');self.click('AC8_Coop_Launch');self.assertEqual(self.get('H.launches'),1)
    def test_guest_does_not_see_launch_control(self):
        self.lobby();self.runlua('H.host=false;UI.refresh()');self.assertEqual(self.get('UI.launch_button.Visibility'),2)
    def test_explicit_join_button_selects_guest_before_configuration(self):
        self.open();self.click('AC8_Coop_Join');self.assertEqual(self.get('UI.role.selected'),1)
        self.runlua("UI.peer.text='76561198000000002'");self.click('AC8_Coop_Configure')
        self.assertFalse(self.get('UI.join_button.bIsEnabled'))
        self.assertFalse(self.get('UI.host_button.bIsEnabled'))
    def test_host_button_restores_host_selection(self):
        self.open();self.click('AC8_Coop_Join');self.click('AC8_Coop_Host')
        self.assertEqual(self.get('UI.role.selected'),0)
    def simple(self):
        self.runlua("OPTIONS.simple=true;OPTIONS.lobby=true;H.phase='idle';OPTIONS.configure=function(role,peer)H.configured=H.configured+1;H.role=role;H.phase='room'end;OPTIONS.reset=function()H.phase='idle';H.role=nil end;OPTIONS.view=function()return {phase=H.phase,host=H.role=='host',can_ready=false,can_start=false}end")
        self.open();self.runlua('UI.refresh()')
    def test_simple_has_no_duplicate_controls_and_connects_directly(self):
        self.simple();self.assertIsNone(self.get('UI.role'));self.assertIsNone(self.get('UI.configure_button'))
        self.runlua("UI.peer.text='76561198000000002'");self.click('AC8_Coop_Join')
        self.assertEqual(self.get('H.role'),'guest');self.assertEqual(self.get('H.configured'),1)
        self.assertEqual(self.get('UI.host_button.Visibility'),1)
    def test_simple_invalid_peer_keeps_choices_usable(self):
        self.simple();self.click('AC8_Coop_Host');self.assertEqual(self.get('H.phase'),'idle')
        self.assertFalse(self.get('UI.peer.readonly'));self.assertEqual(self.get('UI.host_button.Visibility'),0)
    def test_back_leaves_lobby_and_unlocks_peer_for_next_open(self):
        self.simple();self.runlua("UI.peer.text='76561198000000002'");self.click('AC8_Coop_Host');self.click('AC8_Coop_Back')
        self.assertEqual(self.get('H.phase'),'idle');self.assertFalse(self.get('UI.open'))
        self.runlua('UI.show();UI.refresh()');self.assertFalse(self.get('UI.peer.readonly'))
    def test_one_click_never_triggers_two_overlapping_controls(self):
        self.simple();self.runlua("UI.peer.text='76561198000000002';H.hover.AC8_Coop_Host=true;H.hover.AC8_Coop_Join=true;H.keys[1]();UI.refresh()")
        self.assertEqual(self.get('H.configured'),1);self.assertEqual(self.get('H.role'),'host')
if __name__=='__main__':unittest.main()
