import importlib.util
import json
from pathlib import Path
import shutil
import unittest
import uuid
import zipfile

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('ac8_analysis',ROOT/'scripts/analyze_coop_reports.py');analysis=importlib.util.module_from_spec(spec);spec.loader.exec_module(analysis)
class ReportAnalysisTests(unittest.TestCase):
 def setUp(self):
  self.root=ROOT/'build'/('report-analysis-'+uuid.uuid4().hex);self.root.mkdir();self.addCleanup(shutil.rmtree,self.root)
 def report(self,role='host',events=(),attempt=None,**extra):
  path=self.root/(role+'.zip')
  rows=[]
  for seq,(event,detail)in enumerate(events,1):rows.append({'format':'ac8-diagnostic-event-v1','session_id':role,'sequence':seq,'role':role,'event':event,'context':{'config_token':role,'phase':'6','scene':'1','generation':'1','clock_ready':'1','host_tick_ms':'1000','self':'HOST'if role=='host'else'GUEST','peer':'GUEST'if role=='host'else'HOST'},'detail':detail})
  if attempt:
   for row in rows:row['context']['attempt_id']=attempt
  with zipfile.ZipFile(path,'w')as z:
   z.writestr('session.json',json.dumps({'role':role,'revision':'r29-debug1-development','exit_code':0}))
   z.writestr('mod/diagnostics-01.jsonl','\n'.join(json.dumps(x)for x in rows)+'\n')
   for k,v in extra.items():z.writestr(k,v)
  return path
 def test_sent_ack_and_rejection(self):
  p=self.report(events=[('command_sent',{'request':1,'op':6}),('command_confirmed',{'request':1,'reject':3})]);r=analysis.analyze(p)
  self.assertTrue(r['commands'][0]['confirmed']);self.assertEqual(r['rejects'][0]['reason'],'stale')
 def test_superseded_request_is_not_misdiagnosed_as_unconfirmed(self):
  p=self.report(events=[('command_sent',{'request':1,'op':1}),('emergency_sent',{'request':2,'op':23,'supersedes':1}),('command_confirmed',{'request':2,'reject':0})])
  self.assertFalse(analysis.analyze(p)['warnings'])
 def test_partial_live_tail_keeps_valid_events(self):
  p=self.report(events=[('session_state',{'phase':'6'})])
  with zipfile.ZipFile(p,'a')as z:z.writestr('mod/diagnostics-02.jsonl','{"partial":')
  r=analysis.analyze(p);self.assertEqual(r['events'],1);self.assertTrue(r['warnings'])
 def test_flight_flag_is_never_acceptance(self):
  host=self.report(events=[('session_state',{'phase':'6'})]);guest=self.report('guest',[('session_state',{'phase':'6'})])
  r=analysis.combined([host,guest]);self.assertFalse(r['shared_flight_verified']);self.assertFalse(r['warnings'])
 def test_missing_peer_is_explicit(self):
  r=analysis.combined([self.report()]);self.assertIn('Both host and guest',r['warnings'][0])
 def test_rejects_traversal_names_without_extracting(self):
  p=self.report(**{'../unsafe':'data'})
  with self.assertRaises(ValueError):analysis.analyze(p)
 def test_rejects_oversized_diagnostics_before_reading(self):
  p=self.report(**{'mod/diagnostics-02.jsonl':'x'*(analysis.MAX_MEMBER+1)})
  with self.assertRaises(ValueError):analysis.analyze(p)
 def test_hash_mismatch_is_reported(self):
  p=self.report(**{'report-manifest.json':json.dumps({'files':[{'path':'mod/diagnostics-01.jsonl','sha256':'00'}]})})
  with self.assertRaisesRegex(ValueError,'hash mismatch'):analysis.analyze(p)
 def test_uncalibrated_host_tick_is_not_used(self):
  p=self.report()
  with zipfile.ZipFile(p,'a')as z:z.writestr('mod/diagnostics-02.jsonl',json.dumps({'format':'ac8-diagnostic-event-v1','sequence':1,'session_id':'host','role':'host','context':{'clock_ready':'0','host_tick_ms':'999'},'event':'session_state','detail':{'phase':'1'}}))
  self.assertIsNone(analysis.analyze(p)['timeline'][0]['host_tick_ms'])
 def test_recovered_delay_is_not_hidden_by_latest_healthy_sample(self):
  p=self.report('guest',[('health_sample',{'clock':{'status_age_s':6}}),('health_sample',{'clock':{'status_age_s':0}})])
  r=analysis.analyze(p);self.assertEqual(r['metrics']['status_age_s'],0);self.assertEqual(r['signals'][0]['kind'],'local_status_stale')
 def test_matching_attempt_retains_common_phase_without_flight_claim(self):
  h=self.report(events=[('session_state',{'phase':'6'})],attempt='room-a');g=self.report('guest',[('session_state',{'phase':'6'})],attempt='room-a')
  r=analysis.combined([h,g]);self.assertTrue(all(x['attempt_match_confirmed']for x in r['reports']));self.assertEqual(r['reports'][0]['last_common_phase_candidate'],'flight');self.assertFalse(r['shared_flight_verified'])
 def test_other_attempt_is_not_merged(self):
  h=self.report(events=[('session_state',{'phase':'6'})],attempt='room-a');g=self.report('guest',[('session_state',{'phase':'6'})],attempt='room-b')
  r=analysis.combined([h,g]);self.assertFalse(r['reports'][0]['attempt_match_confirmed']);self.assertTrue(any('attempt_id'in w for w in r['warnings']))
 def test_first_error_and_native_cleanup_are_retained(self):
  p=self.report('guest',[('session_state',{'phase':'5','error':'model_failed'}),('session_state',{'phase':'8','error':'subsequent_timeout'}),('health_sample',{'status':{'guest-pilot-status.tsv':{'owner_native_steps':'60','owner_cleanup_complete':'0','owner_cleanup_reason':'children_pending'}}})])
  r=analysis.analyze(p);self.assertEqual(r['first_recorded_error']['error'],'model_failed');self.assertEqual(r['metrics']['owner_native_steps'],'60');self.assertTrue(any('cleanup'in w for w in r['warnings']))
 def test_world_readiness_failure_and_object_pointers_survive_pair_analysis(self):
  state={'owner_world_objects_checked':'1','owner_world_objects_ready':'0','owner_world_objects_reason':'owner_world_actor_mapper_link_changed','owner_combat_zone_pointer':'0x10000','owner_actor_mapper_pointer':'0x20000'}
  p=self.report('guest',[('session_state',{'phase':'5','error':'owner_world_actor_mapper_link_changed'}),('health_sample',{'status':{'guest-pilot-status.tsv':state}})])
  r=analysis.analyze(p)
  for key,value in state.items():self.assertEqual(r['metrics'][key],value)
  self.assertEqual(r['first_recorded_error']['error'],state['owner_world_objects_reason'])
if __name__=='__main__':unittest.main()
