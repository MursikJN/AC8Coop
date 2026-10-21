"""Automatic UI intent -> real session controller, with a model native boundary."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
FIXTURE=r'''
H={time=0,supported=false,preflights=0,runs=0,stops=0,arms=0,reports=0,seq=1,ready=false,native='ready'}
API={now=function()return H.time end,configure=function(role,peer)H.role=role;H.peer=peer end,
log=function()end,report=function()H.reports=H.reports+1 end,
flight_supported=function()return H.supported,'wrong mission/plane' end,
preflight=function()H.preflights=H.preflights+1;return {stamp='fresh',
run=function()H.runs=H.runs+1;assert(H.arms==1,'unarmed');H.native='waiting_peer' end,
stop=function()H.stops=H.stops+1 end}end,
arm=function(stamp)assert(stamp=='fresh');H.arms=H.arms+1 end,
status=function()return {status=H.native,attempted=H.attempted or '0',module_revision=H.revision or 'r8',native_detail='preflight_verified',dispatcher_verified='1',stamp='fresh',reason='fixture'},
{revision='r8',stamp='fresh',stopped=H.stopped and '1' or '0',transport_ready='1',peer_ready=H.ready and '1'or'0',has_peer='1',local_armed='0',epoch='123',peer_age_ms=H.age or '0',peer_sequence=tostring(H.seq)}end}
'''
class MenuSessionTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(FIXTURE)
        self.lua.globals().M=self.lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/coop_menu_session.lua').read_text(encoding='utf-8'))
        self.lua.execute('S=M.new(API)')
    def runlua(self,text):self.lua.execute(text)
    def get(self,text):return self.lua.eval(text)
    def configure(self):self.runlua("S.configure('host','76561198000000002')")
    def prepare(self):self.configure();self.runlua('S.ready();H.supported=true;S.update()')
    def test_no_native_action_without_explicit_menu_intent(self):
        self.configure();self.runlua('H.supported=true;H.ready=true;S.update()');self.assertEqual(self.get('H.preflights'),0)
    def test_wrong_mission_waits_without_preflight(self):
        self.configure();self.runlua('S.ready();S.update()');self.assertEqual(self.get('H.preflights'),0)
    def test_fresh_advancing_peer_auto_arms_exactly_once(self):
        self.prepare();self.runlua('H.ready=true;S.update();S.update()');self.assertEqual(self.get('H.runs'),0)
        self.runlua('H.seq=2;S.update();S.update()');self.assertEqual(self.get('H.runs'),1);self.assertEqual(self.get('H.arms'),1)
    def test_stale_or_unready_peer_never_arms(self):
        self.prepare();self.runlua("H.ready=true;H.age='1001';S.update();H.seq=2;S.update()");self.assertEqual(self.get('H.arms'),0)
    def test_status_revision_mismatch_fails_closed(self):
        self.prepare();self.runlua("H.revision='r7';S.update()");self.assertEqual(self.get('S.phase'),'error');self.assertEqual(self.get('H.arms'),0)
    def test_stop_before_connection_never_allocates(self):
        self.prepare();self.runlua("S.stop();H.ready=true;H.seq=3;S.update()");self.assertEqual(self.get('H.runs'),0);self.assertGreater(self.get('H.stops'),0)
    def test_peer_stop_is_terminal(self):
        self.prepare();self.runlua('H.stopped=true;S.update()');self.assertEqual(self.get('S.phase'),'stopped')
    def test_preflight_timeout_never_retries(self):
        self.prepare();self.runlua('H.time=90;S.update();H.time=95;S.update()');self.assertEqual(self.get('S.phase'),'stopped');self.assertEqual(self.get('H.preflights'),1)
    def test_finish_verifies_cleanup_and_requests_report(self):
        self.prepare();self.runlua("H.ready=true;S.update();H.seq=2;S.update();H.native='active';S.update();H.native='retired';S.update();H.time=1;S.update();H.time=2;S.update()")
        self.assertEqual(self.get('S.phase'),'stopped');self.assertEqual(self.get('H.stops'),3);self.assertEqual(self.get('H.reports'),1)
    def test_invalid_peer_or_configuration_change_rejected(self):
        self.assertRaises(Exception,self.runlua,"S.configure('host','123')")
        self.configure();self.assertRaises(Exception,self.runlua,"S.configure('guest','76561198000000003')")
    def continuous(self,lifetime='0'):
        self.runlua("API.continuous=true;local old=API.status;API.status=function()local n,c=old();n.module_revision='r10';n.lifetime_ms='"+lifetime+"';c.revision='r10';return n,c end;S=M.new(API)")
    def test_continuous_requires_unlimited_native_contract(self):
        self.continuous('15000');self.prepare();self.runlua('H.ready=true;S.update()')
        self.assertEqual(self.get('S.phase'),'error');self.assertEqual(self.get('H.arms'),0)
    def test_continuous_session_stays_running_after_old_deadline(self):
        self.continuous();self.prepare();self.runlua("H.ready=true;S.update();H.seq=2;S.update();H.native='active';H.time=3600;S.update()")
        self.assertEqual(self.get('S.phase'),'running');self.assertEqual(self.get('H.runs'),1)
if __name__=='__main__':unittest.main()
