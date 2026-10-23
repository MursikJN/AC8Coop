"""Lab orchestration against fake UE/native boundaries; not a physics test."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
FIXTURE=r'''
FILES={};CALLS={start=0,prepare=0,preflight=0,stop=0,capture=0,gc=0};NOW=1000;CAMERA={active=false}
local function status(extra)FILES['out/guest-pilot-status.tsv']='active\t1\n'..(extra or'')end
FILES['out/owner-lab-peer.tsv']='port\t1234\ntoken\t4567\n'
io.open=function(path,mode)
 if mode=='rb'and not FILES[path]then return end
 if mode=='wb'then FILES[path]=''end
 return {read=function()return FILES[path]end,write=function(_,...)local v={...};for i,x in ipairs(v)do v[i]=tostring(x)end;FILES[path]=(FILES[path]or'')..table.concat(v);return true end,close=function()return true end}
end
local yes=function()return true end
WORLD={GetAddress=function()return 2 end}
PAWN={K2_GetActorLocation=function()return {X=10,Y=20,Z=30}end}
CONTEXT={isolated_world_verified=true,pc={},pawn=PAWN,world=WORLD}
OWNER={IsValid=yes,GetAddress=function()return 55 end,GetWorld=function()return WORLD end,SetActorEnableCollision=function()end,SetActorHiddenInGame=function()end}
PROVIDER={requested=false,verify=yes,prepare_flight=function()PROVIDER.requested=true;if NOT_READY then return nil end;return CONTEXT end,stop=function()STOPPED=true end}
API={now=function()NOW=NOW+100;return NOW end,provider=PROVIDER,
 static=function()return {CollectGarbage=function()CALLS.gc=CALLS.gc+1 end}end,
 find=function(kind)if kind=='LiveMenuMainTopWidget'then return {{IsValid=yes,IsVisible=yes}}else return {OWNER}end end,
 camera={updates=0,camera={GetAddress=function()return 77 end},attach=function(_,source,options)assert(options.verify_replica());CAMERA.source=source;CAMERA.active=true end,stop=function()if FAIL_CAMERA_STOP then error('camera_stop_failure')end;CAMERA.active=false end},
 preparation={request=function(c,x,rows)assert(x.context==CONTEXT and x.camera.active);if BAD_REQUEST then error('missing_manager')end;REQUEST_ROWS=table.concat(rows,'\n')end,seed=function(frame)assert(frame.generation==1);return 'test-seed' end},
 diagnostic={context=function()end,log=function()end,observe=function()end},
 native={retain_template=function()CALLS.retain=(CALLS.retain or 0)+1;status('owner_template_retained\t'..(REFUSE_ROOT and'0'or'1')..'\n')end,track_camera=function()status('owner_camera_tracked\t1\n')end,start=function()CALLS.start=CALLS.start+1;status()end,tick=function()if not CAMERA_STALLED then CAMERA.updates=CAMERA.updates+1 end end,
 preflight=function()CALLS.preflight=CALLS.preflight+1;status('owner_preflight_ready\t'..(PENDING and'0'or'1')..'\nowner_detail\tdependency_wait\n')end,
 stop=function()CALLS.stop=CALLS.stop+1;status('owner_cleanup_complete\t0\nowner_gc_safe\t1\n')end,
 prepare=function()CALLS.prepare=CALLS.prepare+1;status('owner_ready\t'..(FAIL_PREPARE and'0'or'1')..'\nowner_pointer\t0x37\nowner_detail\ttest\n')end,
 loaded=function()status('state\tguest_world_loaded_sent\n')end,capture_input=function()CALLS.capture=CALLS.capture+1 end}}
CAMERA=API.camera;CAMERA.active=false
'''
class OwnerLabTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE)
  self.lua.globals().M=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/owner_local_lab.lua').read_text())
  self.lua.globals().SOURCE=(ROOT/'probe/AC8CoopRecon/Scripts').as_posix()
  self.lua.execute("S=M.new(SOURCE,'out','dll',API)")
 def seed(self):
  # Exact shape of AC8P v3, four test poses; no real world is represented.
  self.lua.execute(r'''local bytes=string.pack('<c4I2I2I4I4I8I8I8I8I8I8I4I4I4I4I4I4','AC8P',3,392,25201480,1,1,4567,4567,1,1,1000,1,7,1,23,4,4)..string.rep('\0',16)
   for role=0,3 do bytes=bytes..string.pack('<I4I4dddfffffffI4',role,23,10,20,150030,0,0,0,1,250,100,100,0)end
   FILES['out/guest-pilot-state.ac8p']=bytes..string.rep('\0',32)'''.replace(r"'\\0'",r"'\0'"))
 def test_uses_loopback_request_and_real_backend_export_once(self):
  self.seed();self.lua.execute("S.step();assert(CALLS.start==1 and CALLS.prepare==1 and S.prepared and not S.error);assert(REQUEST_ROWS:find('transport\tloopback',1,true));S.step();assert(CALLS.start==1 and CALLS.prepare==1 and CALLS.capture==2)")
 def test_template_is_retained_before_start_or_yield(self):
  self.lua.execute(r"local old=API.native.start;API.native.start=function()assert(CALLS.retain==1 and FILES['out/guest-owner-template.tsv']:find('created_unix',1,true));old()end;S.step();S.step();assert(CALLS.retain==1 and CALLS.start==1)")
 def test_template_refusal_cleans_camera_without_start(self):
  self.lua.execute("REFUSE_ROOT=true;S.step();assert(S.error:find('template retention refused',1,true)and CALLS.retain==1 and CALLS.start==0 and CALLS.stop==1 and not CAMERA.active)")
 def test_template_lease_kept_through_pending_preparation(self):
  self.seed();self.lua.execute("PENDING=true;S.step();NOW=NOW+31000;S.step();assert(CALLS.retain==1 and CALLS.stop==0 and not S.error and not S.prepared);NOW=NOW+16000;S.step();assert(CALLS.stop==1 and not S.complete)")
 def test_waits_for_world_before_start(self):
  self.lua.execute('NOT_READY=true;S.step();S.step();assert(CALLS.start==0 and not S.error)')
 def test_preflight_failure_restores_camera_without_native_spawn(self):
  self.lua.execute('BAD_REQUEST=true;S.step();assert(S.error:find("missing_manager",1,true)and CALLS.start==0 and CALLS.stop==1 and not CAMERA.active and STOPPED)')
 def test_native_prepare_refusal_never_marks_ready(self):
  self.seed();self.lua.execute('FAIL_PREPARE=true;S.step();assert(S.error and CALLS.stop==1 and not S.prepared and not CAMERA.active)')
 def test_stop_waits_for_native_retirement_and_is_idempotent(self):
  self.seed();self.lua.execute(r"S.step();S.stop('test');S.stop('again');NOW=NOW+300;S.step();assert(CALLS.stop==1 and S.active and not S.complete and CALLS.gc==1);FILES['out/guest-pilot-status.tsv']='owner_cleanup_complete\t1\n';S.step();assert(S.complete and not S.active)")
 def test_gc_waits_for_safe_native_receipt_and_grace(self):
  self.seed();self.lua.execute(r"S.step();S.stop('test');S.step();assert(CALLS.gc==0);FILES['out/guest-pilot-status.tsv']='owner_gc_safe\t0\n';NOW=NOW+2000;S.step();assert(CALLS.gc==0);FILES['out/guest-pilot-status.tsv']='owner_gc_safe\t1\n';S.step();assert(CALLS.gc==1);S.step();assert(CALLS.gc==1)")
 def test_gc_missing_receipt_and_camera_error_are_refused(self):
  self.seed();self.lua.execute(r"S.step();FAIL_CAMERA_STOP=true;S.stop('test');NOW=NOW+2000;S.step();assert(CALLS.gc==0);FILES['out/guest-pilot-status.tsv']='';S.step();assert(CALLS.gc==0 and not S.complete)")
 def test_late_f9_uses_fresh_cleanup_clock(self):
  self.seed();self.lua.execute("S.step();NOW=NOW+5000;S.stop('late_f9');S.step();assert(CALLS.gc==0);NOW=NOW+300;S.step();assert(CALLS.gc==1)")
 def test_dependency_wait_never_spawns_and_times_out(self):
  self.seed();self.lua.execute("PENDING=true;S.step();S.step();assert(S.phase=='waiting_dependencies'and CALLS.prepare==0 and CALLS.preflight==1);NOW=NOW+46000;S.step();assert(S.error:find('preparation timed out',1,true)and CALLS.prepare==0 and CALLS.stop==1)")
 def test_pending_dependency_can_become_ready_without_second_start(self):
  self.seed();self.lua.execute("PENDING=true;S.step();PENDING=false;NOW=NOW+1100;S.step();assert(S.prepared and CALLS.start==1 and CALLS.prepare==1 and CALLS.preflight==2)")
 def test_missing_peer_state_has_deadline(self):
  self.lua.execute("S.step();NOW=NOW+46000;S.step();assert(S.error and CALLS.prepare==0 and CALLS.stop==1)")
 def test_camera_failure_revokes_physics(self):
  self.seed();self.lua.execute("S.step();CAMERA.active=false;S.step();assert(S.error:find('camera stopped',1,true)and CALLS.stop==1)")
 def test_stalled_camera_and_cleanup_deadline(self):
  self.seed();self.lua.execute("S.step();CAMERA_STALLED=true;S.step();NOW=NOW+2100;S.step();assert(S.error:find('camera update stalled',1,true));NOW=NOW+31000;S.step();assert(S.phase=='cleanup_unconfirmed'and not S.complete and not S.active)")
 def test_camera_cleanup_exception_does_not_skip_native_stop(self):
  self.seed();self.lua.execute("S.step();FAIL_CAMERA_STOP=true;S.stop('test');assert(CALLS.stop==1 and S.cleanup_error and STOPPED);NOW=NOW+31000;S.step();assert(not S.complete)")
 def test_pause_keeps_world_isolated_and_stops_motion_clock(self):
  self.seed();self.lua.execute("S.step();S.pause();S.step();assert(S.paused and S.phase=='local_model_paused'and FILES['out/guest-pilot-clock.tsv']:find('paused\t1',1,true));S.pause();S.step();assert(not S.paused)")
 def test_missing_local_pose_is_not_success(self):
  self.seed();self.lua.execute("S.step();NOW=NOW+5100;CAMERA.updates=50;S.step();assert(S.error:find('no fresh pose',1,true)and not S.complete)")
 def test_world_loading_timeout_before_native_start(self):
  self.lua.execute("NOT_READY=true;S.step();NOW=NOW+121000;S.step();assert(S.error:find('world preparation timed out',1,true)and CALLS.start==0)")
 def owner_pose(self,sequence=1,generation=1):
  self.lua.globals().SEQ=sequence;self.lua.globals().GEN=generation
  self.lua.execute(r"""FILES['out/guest-owner-local.ac8p']=string.pack('<c4I2I2I4I4I8I8I8I8I8I8I4I4I4I4I4I4','AC8P',3,392,25201480,5,1,4567,4567,SEQ,GEN,1000,1,7,1,23,0,1)..string.rep('\0',16)..string.pack('<I4I4dddfffffffI4',1,23,900,800,700,0,0,0,1,251,0,0,0)..string.rep('\0',200)..string.pack('<ddd',251,0,0)""")
 def test_camera_uses_local_pose_without_waiting_for_host_echo(self):
  self.seed();self.lua.execute('S.step()');self.owner_pose();self.lua.execute("S.step();assert(S.phase=='local_model_running'and S.pose_updates==1 and CAMERA.source().position[1]==900);S.step();assert(S.pose_updates==1)")
  self.owner_pose(2);self.lua.execute("S.step();assert(S.sequence==2 and S.pose_updates==2);assert(FILES['out/owner-lab-status.tsv']:find('NOT_ACCEPTED_AUTOMATICALLY',1,true))")
 def test_foreign_local_generation_stops_native_simulation(self):
  self.seed();self.lua.execute('S.step()');self.owner_pose(1,2);self.lua.execute("S.step();assert(S.error:find('Foreign/replayed local pose',1,true)and CALLS.stop==1)")
 def test_local_sequence_regression_stops_native_simulation(self):
  self.seed();self.lua.execute('S.step()');self.owner_pose(2);self.lua.execute('S.step()');self.owner_pose(1);self.lua.execute('S.step();assert(S.error and CALLS.stop==1)')
 def test_default_native_clock_stall_aborts_world_wait(self):
  self.lua.execute(r"API.now=nil;WALL=100;API.wall_now=function()return WALL end;API.native.clock=function()FILES['out/owner-lab-clock.tsv']='monotonic_ms\t1000\n'end;NOT_READY=true;S=M.new(SOURCE,'out','dll',API);S.step();WALL=104;S.step();assert(S.error:find('clock stopped updating',1,true)and CALLS.start==0)")
 def test_run_constructs_native_and_engine_dependencies_on_game_thread(self):
  self.lua.execute("""QUEUED={};KEYS={};Key={F9=9,F10=10};GT=false;CREATED=0
   RegisterKeyBind=function(k,f)KEYS[k]=f end
   ExecuteInGameThread=function(f)table.insert(QUEUED,f)end
   ExecuteInGameThreadWithDelay=function(_,f)table.insert(QUEUED,f)end
   M.new=function()assert(GT);CREATED=CREATED+1;return {active=false,step=function()assert(GT)end}end
   H=M.run(SOURCE,'out','dll');assert(CREATED==0 and H.state==nil)
   GT=true;table.remove(QUEUED,1)();assert(CREATED==1 and H.state)""")
 def test_stop_before_scheduled_initialization_never_creates_world(self):
  self.lua.execute("""QUEUED={};KEYS={};Key={F9=9,F10=10};RegisterKeyBind=function(k,f)KEYS[k]=f end
   ExecuteInGameThread=function(f)f()end;ExecuteInGameThreadWithDelay=function(_,f)table.insert(QUEUED,f)end
   M.new=function()error('must not initialize')end;H=M.run(SOURCE,'out','dll');KEYS[9]();QUEUED[1]();assert(H.cancelled and not H.error)""")
 def test_initialization_failure_is_visible_in_status(self):
  self.lua.execute("""QUEUED={};Key={F9=9,F10=10};RegisterKeyBind=function()end
   ExecuteInGameThreadWithDelay=function(_,f)table.insert(QUEUED,f)end
   M.new=function()error('clock init failure')end;H=M.run(SOURCE,'out','dll');QUEUED[1]();assert(H.error and FILES['out/owner-lab-status.tsv']:find('initialization_failed',1,true))""")
 def test_slow_asset_load_timestamps_only_final_submission(self):
  self.seed();self.lua.execute(r"""WALL=100;API.wall_now=function()return WALL end
   local original=API.preparation.request;API.preparation.request=function(...)original(...);WALL=WALL+13;NOW=NOW+13000 end
   API.native.start=function()CALLS.start=CALLS.start+1;local stamp=tonumber(FILES['out/guest-pilot-request.tsv']:match('created_unix\t(%d+)'));assert(stamp==WALL);FILES['out/guest-pilot-status.tsv']='active\t1\n'end
   S=M.new(SOURCE,'out','dll',API);S.step();assert(not S.error and S.prepared and S.started_at>13000)
   assert(not REQUEST_ROWS:find('created_unix',1,true))""")
 def test_early_start_refusal_waits_for_camera_retirement(self):
  self.lua.execute(r"""API.native.start=function()CALLS.start=CALLS.start+1;FILES['out/guest-pilot-status.tsv']='active\t0\nrole\thost\n'end
   S.step();assert(S.error and CALLS.prepare==0 and CALLS.stop==1 and not CAMERA.active)
   NOW=NOW+300;S.step();assert(not S.complete and CALLS.gc==1)
   FILES['out/guest-pilot-status.tsv']='owner_cleanup_complete\t1\nowner_camera_retired\t1\n';S.step();assert(S.complete and S.phase=='failed_cleaned')""")
 def test_asset_failure_also_waits_for_tracked_camera(self):
  self.lua.execute(r"""BAD_REQUEST=true;S.step();S.step();assert(CALLS.start==0 and CALLS.stop==1 and not S.complete)
   FILES['out/guest-pilot-status.tsv']='owner_cleanup_complete\t1\n';S.step();assert(S.complete and S.phase=='failed_cleaned')""")
 def test_missing_camera_receipt_never_reports_cleanup_complete(self):
  self.lua.execute(r"""API.native.track_camera=function()FILES['out/guest-pilot-status.tsv']='owner_camera_tracked\t0\n'end
   S.step();assert(S.cleanup_error and CALLS.start==0 and CALLS.stop==1)
   FILES['out/guest-pilot-status.tsv']='owner_cleanup_complete\t1\n';S.step();assert(not S.complete)
   NOW=NOW+31000;S.step();assert(S.phase=='cleanup_unconfirmed')""")
if __name__=='__main__':unittest.main()
