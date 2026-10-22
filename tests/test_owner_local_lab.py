"""Lab orchestration against fake UE/native boundaries; not a physics test."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
FIXTURE=r'''
FILES={};CALLS={start=0,prepare=0,stop=0,capture=0,gc=0};NOW=1000;CAMERA={active=false}
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
 camera={attach=function(_,_,options)assert(options.verify_replica());CAMERA.active=true end,stop=function()CAMERA.active=false end},
 preparation={request=function(c,x,rows)assert(x.context==CONTEXT and x.camera.active);if BAD_REQUEST then error('missing_manager')end;REQUEST_ROWS=table.concat(rows,'\n')end,seed=function(frame)assert(frame.generation==1);return 'test-seed' end},
 diagnostic={context=function()end,log=function()end,observe=function()end},
 native={start=function()CALLS.start=CALLS.start+1;status()end,tick=function()end,
 stop=function()CALLS.stop=CALLS.stop+1;status('owner_cleanup_complete\t0\n')end,
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
 def test_waits_for_world_before_start(self):
  self.lua.execute('NOT_READY=true;S.step();S.step();assert(CALLS.start==0 and not S.error)')
 def test_preflight_failure_restores_camera_without_native_spawn(self):
  self.lua.execute('BAD_REQUEST=true;S.step();assert(S.error:find("missing_manager",1,true)and CALLS.start==0 and not CAMERA.active and STOPPED)')
 def test_native_prepare_refusal_never_marks_ready(self):
  self.seed();self.lua.execute('FAIL_PREPARE=true;S.step();assert(S.error and CALLS.stop==1 and not S.prepared and not CAMERA.active)')
 def test_stop_waits_for_native_retirement_and_is_idempotent(self):
  self.seed();self.lua.execute(r"S.step();S.stop('test');S.stop('again');S.step();assert(CALLS.stop==1 and S.active and not S.complete and CALLS.gc==1);FILES['out/guest-pilot-status.tsv']='owner_cleanup_complete\t1\n';S.step();assert(S.complete and not S.active)")
if __name__=='__main__':unittest.main()
