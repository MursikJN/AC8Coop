"""Exercise the real Lua file protocols at a fake native boundary, no game process."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
FIXTURE=r'''
FILES={};CALLS=0;CONFIRMS=0;PAUSE_CALLS=0;MODE='good';NOW=100
os.time=function()return NOW end
os.getenv=function()return 'fixture.dll'end
os.remove=function(path)FILES[path]=nil;return true end
io.open=function(path,mode)
 if mode=='r'and not FILES[path]then return nil,'fixture missing'end
 local value=mode=='r'and FILES[path]or'';local f={}
 function f:write(...)for _,v in ipairs({...})do value=value..tostring(v)end;return self end
 function f:close()if mode~='r'then FILES[path]=value end;return true end
 function f:read(n)return value:sub(1,n)end
 return f
end
O={Visibility=0,IsValid=function()return VALID~=false end,GetAddress=function()return 4096 end}
GI={PauseManager_=O,IsValid=function()return GI_VALID~=false end}
require=function()return {GetGameInstance=function()return GI_PRESENT==false and nil or GI end}end
FindAllOf=function()return {O}end
local function fields(text)local f={};for k,v in text:gmatch('([^\t\r\n]+)\t([^\r\n]*)')do f[k]=v end;return f end
package.loadlib=function(_,symbol)return function()
 CALLS=CALLS+1
 local menu=symbol=='luaopen_ac8_menu_route';local prefix=menu and'menu-route'or'mission-pause'
 local r=fields(assert(FILES['out/'..prefix..'-request.tsv']))
 local op=r.operation or r.op
 if op=='confirm'then CONFIRMS=CONFIRMS+1 end
 if op=='acquire'then PAUSE_CALLS=PAUSE_CALLS+1 end
 if MODE=='missing'then return end
 local stamp=MODE=='stale'and'old-nonce'or r.stamp
 local format=MODE=='wrong_format'and'old-protocol'or(menu and'ac8-menu-route-v1'or'ac8-mission-pause-v2')
 local text='format\t'..format..'\nstamp\t'..stamp..'\n'
 if menu then
  local status=op=='confirm'and'returned'or op=='select'and'selected'or'verified'
  local reason=op=='bootstrap'and'bootstrap_ready'or'target_selected'
  if MODE=='refused'then status='refused';reason='bootstrap_environment'end
  if MODE=='transition'then status='refused';reason='widget_or_selection_contract'end
  text=text..'status\t'..status..'\nreason\t'..reason..'\nreturned\t1\n'
 else
  local object=MODE=='wrong_object'and'0x2000'or r.object
  text=text..'ok\t'..(MODE=='refused'and'0'or'1')..'\nreason\t'..(MODE=='refused'and'bootstrap_fingerprint'or'bootstrap_ready')..'\nobject\t'..object..'\nheld\t'..(op=='acquire'and'1'or'0')..'\npaused\t'..(op=='acquire'and'1'or'0')..'\n'
 end
 if MODE=='duplicate'then text=text..'stamp\tduplicate\n'end
 if MODE=='malformed'then text=text..'not-a-field\n'end
 if MODE=='oversize'then text=string.rep('x',2049)end
 FILES['out/'..prefix..'-status.tsv']=text
end end
'''
class NativeAdapterChannelTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(FIXTURE)
  self.l.globals().Menu=self.l.execute((ROOT/'probe/AC8CoopRecon/Scripts/local_menu_native.lua').read_text(encoding='utf-8'))
  self.l.globals().Pause=self.l.execute((ROOT/'probe/AC8CoopRecon/Scripts/mission_sync_pause.lua').read_text(encoding='utf-8'))
  self.l.execute("N=Menu.new('out');P=Pause.new('out','source')")
 def test_bootstraps_do_not_require_game_objects(self):
  self.l.execute("GI_PRESENT=false;VALID=false;assert(N.bootstrap().reason=='bootstrap_ready');assert(P.bootstrap().ok=='1');assert(PAUSE_CALLS==0 and CONFIRMS==0)")
 def test_menu_select_and_confirm_use_fresh_nonces(self):
  self.l.execute("N.command('inspect','main_campaign',O);local first=FILES['out/menu-route-request.tsv'];N.command('confirm','main_campaign',O);assert(FILES['out/menu-route-request.tsv']~=first and CONFIRMS==1)")
 def test_pause_acquire_release_and_two_consumers_have_unique_requests(self):
  self.l.execute("assert(P.command('acquire').held=='1');local first=FILES['out/mission-pause-request.tsv'];local second=Pause.new('out','source');assert(second.command('release').held=='0');assert(first~=FILES['out/mission-pause-request.tsv'])")
 def test_menu_lost_reply_never_repeats_confirm(self):
  self.l.execute("MODE='missing';assert(not pcall(N.command,'confirm','main_campaign',O));assert(N.error:find('menu_native_response_missing',1,true));assert(not pcall(N.command,'confirm','main_campaign',O));assert(CONFIRMS==1 and CALLS==1)")
 def test_pause_lost_reply_does_not_repeat_native_acquire(self):
  self.l.execute("MODE='missing';assert(not pcall(P.command,'acquire'));assert(P.error:find('pause_native_response_missing',1,true));assert(not pcall(P.command,'acquire'));assert(CALLS==1)")
 def test_old_success_file_is_removed_before_new_request(self):
  self.l.execute("N.bootstrap();P.bootstrap();MODE='missing';assert(not pcall(N.bootstrap));assert(not pcall(P.bootstrap));assert(CALLS==4)")
 def test_menu_setup_refusal_preserves_specific_reason(self):
  self.l.execute("MODE='refused';assert(not pcall(N.bootstrap));assert(N.error:find('bootstrap_environment',1,true));assert(not pcall(N.bootstrap));assert(CALLS==1)")
 def test_pause_setup_refusal_preserves_specific_reason(self):
  self.l.execute("MODE='refused';assert(not pcall(P.bootstrap));assert(P.error:find('bootstrap_fingerprint',1,true));assert(not pcall(P.bootstrap));assert(CALLS==1)")
 def test_widget_transition_is_nonfatal_and_can_be_rechecked(self):
  self.l.execute("MODE='transition';assert(not N.step('main_campaign','Menu'));assert(not N.error);MODE='good';assert(N.step('main_campaign','Menu'));assert(CONFIRMS==1)")
 def test_invalid_object_never_calls_native(self):
  self.l.execute("VALID=false;assert(not pcall(P.command,'acquire'));assert(not pcall(N.command,'confirm','main_campaign',O));assert(CALLS==0)")
 def test_pause_rejects_response_for_another_manager(self):
  self.l.execute("MODE='wrong_object';assert(not pcall(P.command,'acquire'));assert(P.error and CALLS==1)")
 def test_malformed_or_stale_replies_fail_closed_for_both_protocols(self):
  for mode in ['stale','duplicate','malformed','oversize','wrong_format']:
   with self.subTest(mode=mode):
    self.setUp();self.l.globals().MODE=mode
    self.l.execute("assert(not pcall(N.bootstrap));assert(not pcall(P.bootstrap));assert(N.error and P.error and CALLS==2);assert(not pcall(N.bootstrap));assert(not pcall(P.bootstrap));assert(CALLS==2)")
if __name__=='__main__':unittest.main()
