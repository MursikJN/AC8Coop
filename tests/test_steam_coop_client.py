"""The guest must never acknowledge an absent/unverified replica world."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts'
class SteamCoopClientTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.globals().SOURCE=SOURCE.as_posix()
  self.l.execute("""
   ACK=0;INPUT=0;C={token='123',now=1000,role='guest',snapshot={phase='1',scene='1',epoch='2',generation='1',revision='2',mission='6'}}
   C.view=function()return {connected=true,phase=tonumber(C.snapshot.phase),scene=tonumber(C.snapshot.scene)}end
   C.loaded=function()ACK=ACK+1 end
   N={pilot_start=function()error('Native start must require a real scene')end,pilot_capture_input=function()INPUT=INPUT+1 end}
   M=assert(loadfile(SOURCE..'/steam_coop_client.lua'))()
  """)
 def test_no_provider_never_fakes_loaded_or_input(self):
  self.l.execute("S=M.new(C,'missing-output',SOURCE,N,function()end);S.update();C.snapshot.phase='5';S.update();assert(ACK==0 and INPUT==0 and not S.ready and not S.error)")
 def test_stage_ack_requires_current_room_and_is_once_per_epoch(self):
  self.l.execute("""
   TOKEN='old';P={prepare_stage=function()return {ready=true,session_token=TOKEN}end}
   S=M.new(C,'missing-output',SOURCE,N,function()end,P);S.update();assert(ACK==0)
   TOKEN='123';S.update();S.update();assert(ACK==1)
   C.snapshot.epoch='3';C.pending=true;S.update();assert(ACK==1)
   C.pending=nil;S.update();assert(ACK==2)
  """)
 def test_ordinary_local_mission_without_isolation_is_not_loaded(self):
  self.l.execute("""
   C.snapshot.phase='5';P={prepare_flight=function()return {session_token='123',generation=1,revision=2,isolated_world_verified=false}end,verify=function()return false end}
   S=M.new(C,'missing-output',SOURCE,N,function()end,P);S.update();assert(ACK==0 and INPUT==0 and not S.engine and not S.ready)
  """)
 def test_previous_sortie_context_is_rejected_before_rendering(self):
  self.l.execute("""
   C.snapshot.phase='5';P={prepare_flight=function()return {session_token='123',generation=99,revision=2,isolated_world_verified=true}end,verify=function()error('Must reject generation first')end}
   S=M.new(C,'missing-output',SOURCE,N,function()end,P);S.update();assert(ACK==0 and not S.error and not S.engine)
  """)
 def test_active_local_owner_keeps_ticking_when_host_visuals_are_stale(self):
  self.l.execute("""
   local original=loadfile;UPDATES=0;local fake={active=true,update=function()UPDATES=UPDATES+1 end,stop=function()end}
   loadfile=function(p)if p:find('steam_coop_pilot.lua',1,true)then return function()return {new=function()return fake end}end end;return original(p)end
   C.snapshot.phase='6';N.pilot_prepare=function()end
   local ctx={session_token='123',generation=1,revision=2,isolated_world_verified=true,local_owner_verified=true,world={GetFullName=function()return 'World'end}}
   local p={role=1,alive=true,position={0,0,0},rotation={0,0,0,1}}
   local provider={prepare_flight=function()return ctx end,verify=function()return true end}
   S=M.new(C,'missing-output',SOURCE,N,function()end,provider);S.context=ctx;S.camera={active=true}
   S.engine={ready=true,assets_ready=true,guest_pose=p,nodes={one={}},entities={p},core={active=false,current={},sequence=1},pump=function()end,render=function()return false end}
   S.update();assert(not S.error and S.ready and UPDATES==1)
  """)
if __name__=='__main__':unittest.main()
