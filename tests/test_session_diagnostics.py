"""Actual Lua recorder and controller boundaries, no game or Steam."""
import json
from pathlib import Path
import shutil
import unittest
import uuid
from lupa import LuaRuntime
import test_steam_lobby as lobby

SOURCE=Path(__file__).resolve().parents[1]/'probe/AC8CoopRecon/Scripts'

class DiagnosticRecorderTests(unittest.TestCase):
 def setUp(self):
  self.root=SOURCE.parents[2]/'build'/('diagnostic-test-'+uuid.uuid4().hex)
  self.root.mkdir(parents=True);self.addCleanup(shutil.rmtree,self.root)
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.globals().OUTPUT=self.root.as_posix()
  self.lua.execute('T=1000');self.lua.globals().M=self.lua.execute((SOURCE/'session_diagnostics.lua').read_text())
  self.start()
 def start(self,settings=''):
  self.lua.execute("D=M.new(OUTPUT,{session_id='one',role='host',package='r29-debug1'},{now=function()return T end"+settings+"});C={snapshot={phase='0',local_tick='10000',host_tick='10000',clock_ready='1'},role='host',token='123',active=true};D.context(C)")
 def rows(self):
  result=[]
  for path in self.root.glob('diagnostics-*.jsonl'):
   result.extend(json.loads(x)for x in path.read_text(encoding='utf-8').splitlines())
  return sorted(result,key=lambda r:r['sequence'])
 def test_utf8_control_characters_and_invalid_numbers_are_valid_json(self):
  self.lua.execute("D.event('text',{message='Бакстер\\n\\t\\0\\\"',nan=0/0,inf=math.huge,bad=string.char(255)})")
  row=self.rows()[-1];self.assertEqual(row['detail']['message'],'Бакстер\n\t\0"');self.assertIsNone(row['detail']['nan']);self.assertEqual(row['detail']['bad'],'?')
 def test_state_changes_are_recorded_even_inside_sample_interval(self):
  self.lua.execute("D.observe(C);C.snapshot.phase='1';D.observe(C);C.snapshot.phase='2';D.observe(C)")
  self.assertEqual([r['detail']['phase']for r in self.rows()if r['event']=='session_state'],['0','1','2'])
  self.assertEqual(sum(r['event']=='health_sample'for r in self.rows()),1)
 def test_history_retains_overwritten_status_and_nested_camera_metrics(self):
  path=self.root/'guest-pilot-status.tsv';path.write_text('active\t1\naccepted_inputs\t10\n')
  self.lua.execute("D.observe(C,{client={diagnostics=function()return {camera_updates=12,camera_active=true}end}})")
  path.write_text('active\t0\naccepted_inputs\t20\n');self.lua.execute('T=T+1;D.observe(C)')
  rows=[r['detail']for r in self.rows()if r['event']=='health_sample']
  self.assertEqual([x['status']['guest-pilot-status.tsv']['accepted_inputs']for x in rows],['10','20'])
  self.assertEqual(rows[0]['components']['client']['metrics']['camera_updates'],12)
 def test_unchanged_status_availability_does_not_spam(self):
  (self.root/'guest-pilot-status.tsv').write_text('active\t1\n')
  self.lua.execute('D.observe(C);T=T+1;D.observe(C)')
  self.assertEqual(sum(r['event']=='status_availability'and r['detail']['file']=='guest-pilot-status.tsv'for r in self.rows()),1)
 def test_rotation_is_bounded_and_sequence_remains_monotonic(self):
  self.start(',max_bytes=1800,slots=3');self.lua.execute("for i=1,60 do D.event('burst',{index=i,message=string.rep('x',500)})end;D.observe(C)")
  logs=list(self.root.glob('diagnostics-*.jsonl'));self.assertLessEqual(len(logs),6)
  rows=self.rows();self.assertEqual(len({r['sequence']for r in rows}),len(rows))
  self.assertGreater(self.lua.eval('D.rotations'),0)
  self.assertTrue((self.root/'diagnostics-start.json').exists())
 def test_telemetry_cannot_evict_command_history(self):
  self.start(',max_bytes=1800,slots=2');self.lua.execute("D.observe(C);D.event('command_sent',{request=99});for i=1,100 do T=T+1;D.observe(C)end")
  self.assertTrue(any(r['event']=='command_sent'and r['detail']['request']==99 for r in self.rows()))
  self.assertGreater(self.lua.eval('D.health_rotations'),0)
 def test_repeated_errors_are_suppressed_but_new_errors_are_preserved(self):
  self.lua.execute("D.log('error','first');for i=1,100 do D.log('error','first')end;D.log('error','second');T=T+3;D.log('error','first')")
  self.assertEqual(sum(r['event']=='component_event'for r in self.rows()),3)
  self.assertEqual(self.lua.eval('D.suppressed'),100)
 def test_disk_error_is_passive(self):
  self.lua.execute("D=M.new(OUTPUT..'/absent/deeper',{});assert(not D.event('failure'));assert(D.errors>0)")
 def test_oversized_status_is_marked_and_not_loaded(self):
  (self.root/'guest-pilot-status.tsv').write_text('x'*17000);self.lua.execute('D.observe(C)')
  self.assertTrue(any(r['event']=='status_availability'and r['detail']['status']=='oversized'for r in self.rows()))
 def test_wall_clock_regression_does_not_stop_sampling(self):
  self.lua.execute('D.observe(C);T=T-50;D.observe(C)')
  self.assertEqual(sum(r['event']=='health_sample'for r in self.rows()),2)
 def test_cycles_are_bounded(self):
  self.lua.execute("local a={};a.self=a;D.event('cyclic',a)");self.assertIn('[bounded]',json.dumps(self.rows()[-1]))
 def test_large_event_is_explicitly_truncated(self):
  self.lua.execute("local a={};for i=1,64 do a['key'..i]=string.rep('x',2048)end;D.event('large',a)")
  self.assertTrue(self.rows()[-1]['detail']['truncated'])
  self.assertTrue(all(len(x.encode())<=65536 for p in self.root.glob('diagnostics-*.jsonl')for x in p.read_text().splitlines()))
 def test_native_pipe_status_is_preserved(self):
  (self.root/'lobby-connection-status.txt').write_text('CONNECTED_TEST_OK | rtt_ms=42 | steam_end=0 | reason=none\n')
  self.lua.execute('D.observe(C)')
  sample=next(r['detail']for r in self.rows()if r['event']=='health_sample')
  self.assertEqual(sample['status']['lobby-connection-status.txt']['rtt_ms'],'42')

class DiagnosticControllerTests(unittest.TestCase):
 setUp=lobby.SteamLobbyTests.setUp
 state=lobby.SteamLobbyTests.state
 def test_send_and_reject_have_request_identity(self):
  self.lua.execute("events={};C=M.new(OUTPUT,N,function()return T end,{trace=function(e,d)events[#events+1]={name=e,detail=d}end});C.join('76561198000000002')")
  self.state();self.lua.execute('C.ready()');self.state(request_ack=1,request_confirmed=1,reject=3)
  self.lua.execute("assert(events[2].name=='command_sent'and events[2].detail.request==1 and events[2].detail.op==1);assert(events[3].name=='command_confirmed'and events[3].detail.reject=='3')")
 def test_trace_failure_never_changes_command_semantics(self):
  self.lua.execute("C=M.new(OUTPUT,N,function()return T end,{trace=function()error('disk failed')end});C.join('76561198000000002')")
  self.state();self.lua.execute('C.ready();assert(C.pending.request==1)')
  self.assertIn('op\t1\n',(self.root/'shared-session-command.tsv').read_text())
 def test_priority_cancel_records_superseded_request(self):
  self.lua.execute("events={};C=M.new(OUTPUT,N,function()return T end,{mission_sync=true,cinema_sync=true,session_policy=true,launch_role='guest',trace=function(e,d)events[#events+1]={name=e,detail=d}end});C.join('76561198000000002')")
  fields=dict(protocol=7,mission_sync=1,cinema_sync=1,session_policy=1,host_progress_only=1,phase=4,generation=1,scene=1,clock_ready=1,cinema_at=0,release_at=0)
  self.state(**fields);self.lua.execute('C.ready()');fields['phase']=5;self.state(**fields);self.lua.execute("C.cancel();local e=events[#events];assert(e.name=='emergency_sent'and e.detail.request==2 and e.detail.supersedes==1 and e.detail.op==23)")

if __name__=='__main__':unittest.main()
