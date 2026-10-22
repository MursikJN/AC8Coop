"""Exercise the actual scheduled entry point across a destroyed MainTop."""
import tempfile,unittest
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
class SteamMainHandoffTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
  self.l=LuaRuntime(unpack_returned_tuples=True)
  self.l.globals().SOURCE=(ROOT/'probe/AC8CoopRecon/Scripts').as_posix()
  self.l.globals().OUT=Path(self.temp.name).as_posix()
  self.l.execute(r'''
   ENV={AC8_STEAM_LOBBY='25201480',AC8_STEAM_COOP='25201480',AC8_LOBBY_SCRIPTS=SOURCE,AC8_COOP_RECON_OUTPUT=OUT,AC8_LOBBY_DLL='fake',AC8_LOBBY_ROLE='host'}
   os.getenv=function(k)return ENV[k]end
   package.loadlib=function()return function()end end
   ExecuteInGameThreadWithDelay=function(_,fn)TICK=fn end
   VISIBLE_CALLS=0;ATTACHES=0;CLOSES=0;ADAPTER_CALLS=0
   OBJ={IsValid=function()return not DEAD end,IsVisible=function()assert(not DEAD,'native AV sentinel');VISIBLE_CALLS=VISIBLE_CALLS+1;return true end}
   UI={main=OBJ,refresh=function()assert(not DEAD,'refresh destroyed');return true end,
       close=function()assert(not DEAD,'close destroyed');CLOSES=CLOSES+1 end}
   C={snapshot={phase='0'},role='host',active=true,token='1',now=1000,join_notice=0,invite_status={}}
   C.set_menu_available=function()end
   C.view=function()return {connected=true}end
   C.poll=function()if NEXT_PHASE then C.snapshot.phase=NEXT_PHASE;NEXT_PHASE=nil end end
   local normal=loadfile
   loadfile=function(path)
    local n=path:match('([^/]+)%.lua$')
    if n=='coop_main_menu'then return function()return {attach=function()ATTACHES=ATTACHES+1;_G.AC8MainMenuEntry=UI;return UI end}end end
    if n=='coop_menu_catalog'then return function()return {}end end
    if n=='steam_lobby_services'then return function()return {new=function()return C end}end end
    if n=='mission_sync_adapter'then return function()return {new=function()return {update=function()ADAPTER_CALLS=ADAPTER_CALLS+1;if C.snapshot.phase=='1'then assert(not _G.AC8MainMenuEntry,'Must retire before native route');DEAD=true end end}end}end end
    if n=='steam_coop_pilot'then return function()return {new=function()return {update=function()end}end}end end
    if n=='scene_host'then return function()return {new=function()return {update=function()end}end}end end
    return normal(path)
   end
  ''')
 def start(self):self.l.execute((ROOT/'probe/AC8CoopRecon/Scripts/steam_lobby_main.lua').read_text(encoding='utf-8'))
 def test_handoff_precedes_native_route_and_never_polls_dead_menu(self):
  self.start();self.l.execute("TICK();NEXT_PHASE='1';TICK();for i=1,10 do TICK()end;assert(CLOSES==1 and VISIBLE_CALLS==2 and ATTACHES==1 and ADAPTER_CALLS==12)")
  self.assertNotIn('tick_error',(Path(self.temp.name)/'steam-menu.log').read_text())
 def test_first_available_snapshot_already_in_transition(self):
  self.l.execute("C.snapshot.phase='1';DEAD=true");self.start();self.l.execute("TICK();TICK();assert(CLOSES==0 and VISIBLE_CALLS==0 and ATTACHES==0)")
  self.assertNotIn('tick_error',(Path(self.temp.name)/'steam-menu.log').read_text())
 def test_no_menu_refresh_or_reschedule_after_quitgame(self):
  self.l.execute('SCHEDULES=0;ExecuteInGameThreadWithDelay=function(_,fn)TICK=fn;SCHEDULES=SCHEDULES+1 end')
  self.start()
  self.l.execute("C.lifecycle={quitting=false};C.recovery_ui={update=function()C.lifecycle.quitting=true;DEAD=true end};TICK();local calls=VISIBLE_CALLS;TICK();assert(SCHEDULES==1 and VISIBLE_CALLS==calls)")
  self.assertNotIn('tick_error',(Path(self.temp.name)/'steam-menu.log').read_text())
if __name__=='__main__':unittest.main()
