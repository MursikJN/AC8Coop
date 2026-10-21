"""Two-peer cinematic orchestration with fake native playback; no game launch."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'probe/AC8CoopRecon/Scripts/cinema_playback.lua'
FIXTURE=r'''
FILES={};PLAYS=0;PAUSES=0;SKIPS=0;CLOSES=0;PREPARES=0;FINISHES=0;SEGMENTS=0
READY=true;REMAINING=10000;SOURCE_ASSET='/Game/Movies/Briefing.Briefing';FOUND=true;NATIVE_ERROR=false
io.open=function(path,mode)
 if mode=='rb'then if not FILES[path]then return end;return {read=function()return FILES[path]end,close=function()end}end
 return {write=function(_,s)FILES[path]=s;return true end,close=function()return true end}
end
os.rename=function(a,b)FILES[b]=FILES[a];FILES[a]=nil;return true end
os.remove=function(a)FILES[a]=nil;return true end
C={token='123',role='host',now=1000,snapshot={phase='1',epoch='2',revision='1',scene='1',cinema_prepared='0',cinema_finished='0',cinema_state='0',vote_mask='0',clock_ready='1'}}
C.view=function()return {connected=CONNECTED~=false}end
C.cinema_prepared=function()PREPARES=PREPARES+1 end
C.cinema_finished=function()FINISHES=FINISHES+1 end
C.scene_segment=function(id)SEGMENTS=SEGMENTS+1;NEXT_SCENE=id end
E={discover=function()if not FOUND then return end;return {descriptor={kind=1,duration_ms=10000,asset=SOURCE_ASSET,viewer='/Game/UI/Movie.Movie_C',options=''}}end,
 open=function(d)OPENED=d;return {descriptor=d}end,
 sample=function()return {ready=READY,remaining_ms=REMAINING,ended=false,error=NATIVE_ERROR and 'native movie open failed'or nil}end,
 pause=function()PAUSES=PAUSES+1 end,play=function()PLAYS=PLAYS+1 end,skip=function()SKIPS=SKIPS+1 end,close=function()CLOSES=CLOSES+1 end}
function stage(n)C.snapshot.phase=tostring(n)end
function masks(ready,finished,state,votes)C.snapshot.cinema_prepared=tostring(ready);C.snapshot.cinema_finished=tostring(finished);C.snapshot.cinema_state=tostring(state);C.snapshot.vote_mask=tostring(votes or 0)end
function playing()stage(2);masks(3,0,2);R.update()end
function receipt(token,epoch,revision,scene)
 FILES['out/cinema-client.tsv']='config_token\t'..token..'\nepoch\t'..epoch..'\nrevision\t'..revision..'\nscene\t'..scene..'\nkind\t1\nduration_ms\t10000\nasset\t/Game/Movies/Briefing.Briefing\nviewer\t/Game/UI/Movie.Movie_C\noptions\t\n'
end
'''
class CinemaPlaybackTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(FIXTURE)
  self.l.globals().M=self.l.execute(SOURCE.read_text(encoding='utf-8'))
  self.l.execute("R=M.new(C,'out','source',function()end,E)")
 def runlua(self,s):self.l.execute(s)
 def test_missing_media_never_reports_prepared(self):
  self.runlua('FOUND=false;R.update();assert(PREPARES==0 and PLAYS==0 and not R.ready)')
 def test_decoder_preparation_must_really_finish(self):
  self.runlua('READY=false;R.update();assert(PREPARES==0);READY=true;R.update();assert(PREPARES==1 and PLAYS==0)')
 def test_loaded_and_armed_wait_for_shared_start(self):
  self.runlua('stage(2);masks(3,0,1);R.update();R.update();assert(PLAYS==0);masks(3,0,2);R.update();R.update();assert(PLAYS==1)')
 def test_stale_clock_keeps_player_paused(self):
  self.runlua("stage(2);masks(3,0,2);C.snapshot.clock_ready='0';R.update();assert(PLAYS==0)")
 def test_fast_host_waits_for_slow_guest(self):
  self.runlua('playing();REMAINING=200;R.update();assert(FINISHES==1 and R.waiting and not R.can_end());masks(3,1,2);for i=1,100 do C.now=C.now+100;R.update()end;assert(PLAYS==1 and SEGMENTS==0 and not R.can_end())')
 def test_fast_guest_waits_for_host(self):
  self.runlua("C.role='guest';receipt('123','2','1','1');playing();REMAINING=100;R.update();masks(3,2,2);R.update();assert(FINISHES==1 and PLAYS==1 and R.waiting and not R.can_end())")
 def test_terminal_is_observed_not_a_wall_clock_timeout(self):
  self.runlua('playing();C.now=100000;R.update();assert(FINISHES==0 and not R.terminal)')
 def test_both_finished_still_wait_for_shared_release(self):
  self.runlua('playing();REMAINING=200;R.update();masks(3,3,3);R.update();assert(PLAYS==1 and not R.can_end());masks(3,3,4);R.update();R.update();assert(PLAYS==2 and R.can_end())')
 def test_one_vote_never_skips(self):
  self.runlua('playing();masks(3,0,2,1);R.update();R.update();assert(SKIPS==0 and not R.authorize_skip())')
 def test_two_votes_need_commit_deadline_before_skip(self):
  self.runlua('playing();masks(3,0,3,3);R.update();assert(SKIPS==0 and not R.authorize_skip());masks(3,0,4,3);R.update();masks(3,3,4,3);R.update();R.update();assert(SKIPS==1 and R.authorize_skip() and R.can_end())')
 def test_guest_opens_only_current_authenticated_descriptor(self):
  self.runlua("C.role='guest';receipt('old','2','1','1');R.update();assert(not OPENED);receipt('123','1','1','1');R.update();assert(not OPENED);receipt('123','2','2','1');R.update();assert(not OPENED);receipt('123','2','1','1');R.update();assert(OPENED and PREPARES==1)")
 def test_next_asset_is_held_until_both_finished(self):
  self.runlua("playing();REMAINING=200;R.update();SOURCE_ASSET='/Game/Movies/Next.Next';R.update();assert(SEGMENTS==0 and not R.playing);masks(3,3,4);R.update();assert(SEGMENTS==1 and NEXT_SCENE==2)")
 def test_new_clip_clears_terminal_and_does_not_inherit_skip(self):
  self.runlua("playing();masks(3,0,4,3);R.update();C.snapshot.scene='2';C.snapshot.epoch='3';masks(0,0,0);R.update();assert(not R.terminal and not R.authorize_skip() and PREPARES==1 and SKIPS==1)")
 def test_error_never_becomes_completion_or_readiness(self):
  self.runlua('NATIVE_ERROR=true;R.update();assert(R.error and PREPARES==0 and FINISHES==0 and not R.can_end())')
 def test_disconnect_pauses_without_reporting_finished(self):
  self.runlua('playing();CONNECTED=false;R.update();assert(not R.playing and FINISHES==0)')
 def test_departure_closes_owned_surface(self):
  self.runlua("C.role='guest';receipt('123','2','1','1');playing();stage(3);R.update();R.update();assert(CLOSES==1 and not R.ready)")
 def test_common_clock_deadline_can_start_without_mutating_host_snapshot(self):
  self.runlua("stage(2);masks(3,0,1);C.snapshot.cinema_commit_mask='3';C.snapshot.cinema_at='1500';R.update();assert(PLAYS==0);C.now=1500;R.update();assert(PLAYS==1 and C.snapshot.cinema_state=='1')")
 def test_clock_recovery_resumes_the_existing_player(self):
  self.runlua("playing();C.snapshot.clock_ready='0';R.update();assert(not R.playing);C.snapshot.clock_ready='1';R.update();assert(R.playing and PLAYS==2)")
 def test_unexpected_native_travel_fails_without_an_end_receipt(self):
  self.runlua("playing();SOURCE_ASSET='/Game/Movies/Unexpected.Unexpected';R.update();assert(R.error and FINISHES==0 and SEGMENTS==0)")
if __name__=='__main__':unittest.main()
