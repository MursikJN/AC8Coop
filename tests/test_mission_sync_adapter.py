"""Engine boundary tests: authoritative phases must hold actual playback and launch only once."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'probe/AC8CoopRecon/Scripts/mission_sync_adapter.lua'
FIXTURE=r'''
PAUSED=false;TIME=42;LOADED=0;VOTES=0;ENDS=0;SORTIES=0;HANGARS=0;GUARDS={};LOGS={};VISIBLE={};PLANE=false;SKIP=false
function valid()return true end
WORLD={IsValid=valid,GetFullName=function()return '/Game/Mission007'end}
PLAYER={IsValid=valid,GetWorld=function()return WORLD end}
PAWN={IsValid=valid,IsA=function()return true end,K2_GetActorLocation=function()return {X=1,Y=2,Z=3}end,GetClass=function()return {GetFullName=function()return '/PP0007_fa18c/BP_Player'end}end,bIsActivated=true,bIsIGCActor=false};PLAYER.Pawn=PAWN
GAME={IsGamePaused=function()return PAUSED end,SetGamePaused=function(_,_,value)PAUSED=value;return true end,GetTimeSeconds=function()return TIME end}
OBJ={IsValid=valid}
N={find=function(q)return VISIBLE[q]and OBJ or nil end,
 command=function()return {status='verified',selected=HOST_PLANE or '7010',value=GUEST_PLANE or '23010'}end,
 step=function(k,q)if VISIBLE[q]then if k=='sortie'then SORTIES=SORTIES+1 end;return true end;return false end}
G={poll=function(o,scene,voting,authorize)
 GUARDS[#GUARDS+1]={scene=scene,voting=voting,authorize=authorize}
 return {threshold='0.4',treat='0.3',requested=REQUESTED and '1'or'0',consumed='0'}
end}
P={command=function(op)
 if op=='acquire'then PAUSED=true;return {held='1',paused='1',flags='24'}end
 PAUSED=OTHER_PAUSE==true;return {held='0',paused=PAUSED and '1'or'0',flags=PAUSED and '16'or'0'}
end}
U={attach=function()return {refresh=function()end,close=function()end}end}
loadfile=function(path)return function()
 if path:find('local_menu_native',1,true)then return {new=function()return N end}
 elseif path:find('mission_sync_cinema_guard',1,true)then return {new=function()return G end}
 elseif path:find('mission_sync_pause',1,true)then return {new=function()return P end}
 elseif path:find('mission_sync_status_ui',1,true)then return {new=function()return {template=function()end,update=function()end}end}
 else return U end
end end
require=function()return {GetPlayerController=function()return PLAYER end}end
StaticFindObject=function()return GAME end
FindAllOf=function(q)if q=='LivePlayerController'then return PLANE and{PLAYER}or{}end;if q=='LiveSkipOperationPressHoldSkipStrategy'then return SKIP and{SKIP}or{}end;return{}end
function make_skip(name)
 local o={IsValid=valid,GetFullName=function()return name end,GetAddress=function()return 100+#name end}
 local owner={IsValid=valid,IsA=function()return true end,SkipOperationStrategy=o};o.GetOuter=function()return owner end;return o
end
C={snapshot={mission='6',difficulty='1',guest_aircraft='23',host_aircraft='7',phase='0',scene='1',scene_exit='0'},now=1000}
C.view=function()return {connected=CONNECTED~=false,phase=tonumber(C.snapshot.phase),scene=tonumber(C.snapshot.scene),votes=tonumber(C.snapshot.vote_mask)or 0,can_start_flight=C.snapshot.phase=='4'and C.snapshot.ready_mask=='3'}end
C.loaded=function()LOADED=LOADED+1 end
C.vote_skip=function()VOTES=VOTES+1;C.snapshot.vote_mask='1'end
C.scene_segment=function(id)C.snapshot.scene=tostring(id);C.snapshot.vote_mask='0';C.snapshot.scene_exit='0'end
C.scene_ended=function()ENDS=ENDS+1 end
C.hangar_verified=function()HANGARS=HANGARS+1 end
C.start_flight=function()C.snapshot.phase='5'end
C.flight_verified=function()LOADED=LOADED+1 end
C.flight_scene=function(id)C.snapshot.phase='2';C.snapshot.scene=tostring(id);C.snapshot.scene_return='6'end
C.status=function()return 'status'end
io.open=function()return {write=function()end,close=function()end}end
'''
class MissionAdapterTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(FIXTURE);self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'));self.l.execute("A=M.new(C,'output','source',function(event,detail)LOGS[#LOGS+1]={event,detail}end)")
 def runlua(self,s):self.l.execute(s)
 def val(self,s):return self.l.eval(s)
 def test_no_loaded_ack_until_real_scene_exists(self):
  self.runlua("C.snapshot.phase='1';A.step=6;A.update();A.update()")
  self.assertEqual(self.val('LOADED'),0);self.assertFalse(self.val('PAUSED'))
 def test_stale_authority_never_advances_route(self):
  self.runlua("CONNECTED=false;C.snapshot.phase='5';VISIBLE.LiveMenuHangarStandbyWidget=true;A.update()")
  self.assertEqual(self.val('SORTIES'),0)
 def test_world_is_held_until_authority_changes_phase(self):
  self.runlua("C.snapshot.phase='1';A.step=6;SKIP=make_skip('first');A.update();A.update()")
  self.assertEqual(self.val('LOADED'),1);self.assertTrue(self.val('PAUSED'))
  self.runlua("C.snapshot.phase='2';A.update()")
  self.assertFalse(self.val('PAUSED'));self.assertIsNone(self.val('A.error'))
 def test_one_vote_does_not_authorize_stock_skip(self):
  self.runlua("C.snapshot.phase='2';SKIP=make_skip('first');REQUESTED=true;A.update();A.update()")
  self.assertEqual(self.val('VOTES'),1);self.assertFalse(self.val('GUARDS[#GUARDS].authorize'));self.assertEqual(self.val('ENDS'),0)
  self.runlua("C.snapshot.vote_mask='3';C.snapshot.scene_exit='1';A.update()")
  self.assertTrue(self.val('GUARDS[#GUARDS].authorize'));self.assertEqual(self.val('ENDS'),0)
 def test_new_scene_does_not_inherit_authorization(self):
  self.runlua("C.snapshot.phase='2';SKIP=make_skip('first');A.update();C.snapshot.vote_mask='3';C.snapshot.scene_exit='1';SKIP=make_skip('second');A.update()")
  self.assertEqual(self.val('C.snapshot.scene'),'2');self.assertFalse(self.val('GUARDS[#GUARDS].authorize'))
 def test_sortie_is_once_and_world_waits_for_guest(self):
  self.runlua("C.snapshot.phase='5';VISIBLE.LiveMenuHangarStandbyWidget=true;A.update();PLANE=true;A.update();A.update()")
  self.assertEqual(self.val('SORTIES'),1);self.assertEqual(self.val('LOADED'),1);self.assertTrue(self.val('PAUSED'))
  self.runlua("C.snapshot.phase='6';A.update();A.update()")
  self.assertFalse(self.val('PAUSED'));self.assertEqual(self.val('SORTIES'),1)
 def test_faster_world_must_not_advance_while_held(self):
  self.runlua("C.snapshot.phase='5';A.sortie=true;PLANE=true;A.update();TIME=43;A.update()")
  self.assertIsNotNone(self.val('A.error'));self.assertTrue(self.val('PAUSED'))
 def test_stock_unpause_is_reasserted_before_next_world_tick(self):
  self.runlua("C.snapshot.phase='5';A.sortie=true;PLANE=true;A.update();PAUSED=false;A.update()")
  self.assertIsNone(self.val('A.error'));self.assertTrue(self.val('PAUSED'))
 def test_release_preserves_stock_cinematic_pause(self):
  self.runlua("C.snapshot.phase='5';A.sortie=true;PLANE=true;A.update();OTHER_PAUSE=true;C.snapshot.phase='6';A.update()")
  self.assertIsNone(self.val('A.error'));self.assertTrue(self.val('PAUSED'));self.assertIsNone(self.val('A.held_context'))
 def test_start_requires_two_fresh_ready_flags(self):
  self.runlua("C.snapshot.phase='4';VISIBLE.LiveMenuHangarStandbyWidget=true;C.snapshot.ready_mask='1'")
  self.assertRaises(Exception,self.runlua,'A.start()');self.assertEqual(self.val('SORTIES'),0)
  self.runlua("C.snapshot.ready_mask='3';A.start();A.update();A.update()")
  self.assertEqual(self.val('SORTIES'),1)
 def test_natural_scene_end_uses_real_end_screen_once(self):
  self.runlua("C.snapshot.phase='2';VISIBLE.LiveMenuBriefingProgressWidget=true;A.update();A.update()")
  self.assertEqual(self.val('ENDS'),1)
 def test_r28_never_uses_host_end_screen_as_guest_completion(self):
  self.runlua("C.cinema={update=function()end,can_end=function()return BOTH end,authorize_skip=function()return BOTH end,playing=true};C.snapshot.phase='2';VISIBLE.LiveMenuBriefingProgressWidget=true;A.update();A.update()")
  self.assertEqual(self.val('ENDS'),0)
  self.runlua('BOTH=true;A.update();A.update()');self.assertEqual(self.val('ENDS'),1)
 def test_r28_skip_waits_for_cinematic_commit_as_well_as_votes(self):
  self.runlua("C.cinema={update=function()end,can_end=function()return false end,authorize_skip=function()return ALLOWED end,playing=true};C.snapshot.phase='2';C.snapshot.scene_exit='1';C.snapshot.vote_mask='3';SKIP=make_skip('clip');A.update()")
  self.assertFalse(self.val('GUARDS[#GUARDS].authorize'))
  self.runlua('ALLOWED=true;A.update()');self.assertTrue(self.val('GUARDS[#GUARDS].authorize'))
 def test_r28_missing_local_player_cannot_ack_initial_loading(self):
  self.runlua("C.cinema={update=function()end,ready=false};C.snapshot.phase='1';A.step=6;SKIP=make_skip('first');A.update()")
  self.assertEqual(self.val('LOADED'),0)
 def test_r29_leaving_standby_invalidates_readiness_before_editing(self):
  self.runlua("C.session_policy=true;C.snapshot.phase='4';C.snapshot.ready_mask='3';C.invalidate_ready=function()C.snapshot.ready_mask='0';INVALIDATED=(INVALIDATED or 0)+1 end;A.update();A.update()")
  self.assertEqual(self.val('INVALIDATED'),1)
 def test_r29_changed_host_aircraft_requires_new_readiness_snapshot(self):
  self.runlua("C.session_policy=true;C.snapshot.phase='4';VISIBLE.LiveMenuHangarStandbyWidget=true;HOST_PLANE='9010';C.host_loadout=function(a)NEW_AIRCRAFT=a end;A.update()")
  self.assertEqual(self.val('NEW_AIRCRAFT'),9)
if __name__=='__main__':unittest.main()
