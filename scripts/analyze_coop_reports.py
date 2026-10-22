"""Read bounded debug ZIPs as data; produce evidence, never a flight acceptance."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

MAX_TOTAL=128*1024*1024
MAX_MEMBER=8*1024*1024
PHASES={0:'lobby',1:'intro_loading',2:'cutscene',3:'hangar_loading',4:'hangar',5:'flight_loading',6:'flight',7:'result',8:'stopped',9:'restart_loading',10:'restart_exit'}
REJECTS={0:'none',1:'role',2:'stage',3:'stale',4:'value',5:'not_ready',6:'exhausted'}
OPS={1:'ready',2:'select_mission',3:'loadout',4:'assign_wingman',5:'vote_skip',6:'start_sortie',7:'loaded',8:'scene_ended',9:'begin_intro',10:'open_local_hangar',11:'local_hangar_arrived',12:'local_flight_arrived',13:'commit',14:'scene_segment',15:'abort',16:'begin_flight_scene',19:'cinema_prepared',20:'cinema_finished',21:'cinema_commit',22:'restart',23:'cancel',24:'fault',25:'restart_ack',26:'mission_result',27:'invalidate_ready'}

def number(value, default=0):
 try:return int(value)
 except (TypeError,ValueError,OverflowError):return default

def analyze(path):
 events=[];warnings=[];record={};manifest={};summary={};total=0
 with zipfile.ZipFile(path) as z:
  if len(z.infolist())>4096:raise ValueError('ZIP file count exceeds budget')
  seen=set()
  for info in z.infolist():
   pure=PurePosixPath(info.filename)
   if pure.is_absolute()or'..'in pure.parts or'\\'in info.filename:raise ValueError('Unsafe ZIP member name')
   if info.filename in seen:raise ValueError('Duplicate ZIP member')
   seen.add(info.filename)
   if info.is_dir():continue
   if pure.name not in ('session.json','report-manifest.json','diagnostics-summary.json','diagnostics-start.json')and not(pure.name.startswith('diagnostics-')and pure.suffix=='.jsonl'):continue
   if info.file_size>MAX_MEMBER or total+info.file_size>MAX_TOTAL:raise ValueError('Diagnostic data exceeds read budget')
   data=z.read(info);total+=len(data)
   if pure.name=='report-manifest.json':manifest=json.loads(data.decode('utf-8-sig'));continue
   if pure.name=='session.json':record=json.loads(data.decode('utf-8-sig'));continue
   if pure.name=='diagnostics-summary.json':summary=json.loads(data.decode('utf-8-sig'));continue
   if pure.suffix!='.jsonl':continue
   # A live archive can end between writes. Keep prior complete events.
   for index,line in enumerate(data.splitlines(),1):
    if len(line)>65536:warnings.append(f'{pure.name}:{index}: oversized event');continue
    try:
     row=json.loads(line.decode('utf-8'))
     if row.get('format')!='ac8-diagnostic-event-v1'or not isinstance(row.get('context'),dict)or not isinstance(row.get('detail'),dict):raise ValueError('Unsupported event shape')
     if len(events)>=100000:raise ValueError('Event count exceeds budget')
     row['_source']=info.filename;events.append(row)
    except (ValueError,UnicodeError,AttributeError) as e:
     warnings.append(f'{pure.name}:{index}: invalid/partial event ({type(e).__name__})')
  for item in manifest.get('files',[]):
   name=item.get('path','')
   if name in seen and (name.endswith('.jsonl')or PurePosixPath(name).name=='session.json'):
    info=z.getinfo(name)
    if info.file_size>MAX_MEMBER:raise ValueError('Manifest entry exceeds budget')
    if hashlib.sha256(z.read(info)).hexdigest().upper()!=item.get('sha256','').upper():raise ValueError('Report hash mismatch: '+name)
 events.sort(key=lambda r:(str(r.get('session_id','')),number(r.get('sequence'))))
 commands={};rejects=[];timeline=[];phases=[];metrics={};signals=[];counts=Counter();host_ids=set();identities=set();attempts=set();last_error=None;first_error=None
 for row in events:
  event=row.get('event');detail=row['detail'];context=row['context'];counts[event]+=1
  identities.add(row.get('session_id','unknown'))
  role=row.get('role',record.get('role','unknown'))
  if context.get('attempt_id'):attempts.add(str(context['attempt_id']))
  host=context.get('self')if role=='host'else context.get('peer')
  if host and host!='0':host_ids.add(str(host))
  key=(row.get('session_id'),context.get('config_token'),number(detail.get('request')))
  if event in ('command_sent','emergency_sent'):
   commands[key]={'request':detail.get('request'),'op':OPS.get(number(detail.get('op')),detail.get('op')),'sent_sequence':row.get('sequence'),'confirmed':False,'supersedes':detail.get('supersedes')}
   superseded=detail.get('supersedes')
   if superseded is not None:
    prior=commands.get((key[0],key[1],number(superseded)))
    if prior:prior['superseded']=True
  elif event=='command_confirmed':
   command=commands.get(key)
   if command:command['confirmed']=True
   reject=number(detail.get('reject'))
   if reject:rejects.append({'request':detail.get('request'),'code':reject,'reason':REJECTS.get(reject,'unknown')})
  elif event=='session_state':
   phase=number(detail.get('phase'),-1)
   if phase>=0 and(not phases or phases[-1]!=phase):phases.append(phase)
   if detail.get('error')or detail.get('local_failure'):
    last_error=detail.get('local_failure')or detail.get('error')
    if first_error is None:first_error={'sequence':row.get('sequence'),'error':last_error,'phase':PHASES.get(phase,str(phase))}
  elif event=='health_sample':
   status=detail.get('status')or{};pilot=status.get('guest-pilot-status.tsv')or{}
   for name in ('accepted_inputs','native_steps','state_sequence','peer_loaded','spectating','last_roll_input','engine_detail','state','owner_ready','owner_pointer','owner_index','owner_serial','owner_detail','owner_native_steps','owner_cleanup','owner_cleanup_reason','owner_cleanup_complete','owner_endplay_graph_verified','owner_world_objects_checked','owner_world_objects_ready','owner_world_objects_reason','owner_combat_zone_pointer','owner_actor_mapper_pointer'):
    if name in pilot:metrics[name]=pilot[name]
   components=detail.get('components')or{};client=(components.get('client')or{}).get('metrics')or{}
   metrics.update(client)
   clock=detail.get('clock')or{};metrics['clock_ready']=clock.get('clock_ready');metrics['clock_rtt_ms']=clock.get('clock_rtt_ms');metrics['status_age_s']=clock.get('status_age_s')
   signal=None
   if number(clock.get('status_age_s'))>=5:signal='local_status_stale'
   elif number(context.get('phase'))==6 and number(client.get('scene_age_ms'))>500:signal='client_scene_stale'
   if signal and len(signals)<100:
    signals.append({'kind':signal,'sequence':row.get('sequence'),'host_tick_ms':context.get('host_tick_ms')if context.get('clock_ready')=='1'else None,'scene_age_ms':client.get('scene_age_ms'),'status_age_s':clock.get('status_age_s')})
  if event in ('session_state','command_sent','emergency_sent','command_confirmed','invite_received','scene_frame_ignored','component_event','component_state','observation_gap'):
   clock=context.get('clock_ready')=='1'and context.get('host_tick_ms')is not None
   timeline.append({'role':role,'session_id':row.get('session_id'),'sequence':row.get('sequence'),'host_tick_ms':number(context.get('host_tick_ms'))if clock else None,'utc':row.get('utc'),'event':event,'phase':PHASES.get(number(context.get('phase'),-1),'unknown'),'scene':context.get('scene'),'generation':context.get('generation'),'detail':detail})
 if not events:warnings.append('No structured diagnostics: use the same diagnostic kit on both PCs.')
 if summary.get('rotations'):warnings.append('Older command/event history has rotated; this report is not the complete run.')
 if summary.get('health_rotations'):warnings.append('Older periodic telemetry has rotated; the event journal is separate.')
 if summary.get('write_errors'):warnings.append('Recorder reported write errors; some events may be missing.')
 if summary.get('truncated'):warnings.append('Oversized diagnostic events were truncated.')
 if manifest.get('skipped'):warnings.append('Collector omitted files; see report-manifest.json.')
 if manifest.get('live_snapshot'):warnings.append('Session was not finalized by the launcher; the last event or log may be partial.')
 pending=[v for v in commands.values()if not v['confirmed']and not v.get('superseded')]
 if pending:warnings.append('Some commands have no observed confirmation; this can also be an incomplete/rotated recording.')
 if last_error:warnings.append('Last controller error: '+str(last_error)[:500])
 if number(metrics.get('scene_age_ms'))>500:warnings.append('Last client scene sample is older than 500 ms; inspect pause/transport context.')
 if metrics.get('owner_cleanup_complete')=='0':warnings.append('Native owner cleanup is unconfirmed; inspect identity/retirement logs. This may be an active live capture.')
 return {'archive':str(path),'role':record.get('role'),'package':record.get('revision'),'session_ids':sorted(identities),'attempt_ids':sorted(attempts),'host_ids':sorted(host_ids),'first_recorded_error':first_error,'exit_code':record.get('exit_code'),'phases':[PHASES.get(x,str(x))for x in phases],'events':len(events),'event_counts':dict(counts),'commands':list(commands.values()),'rejects':rejects,'metrics':metrics,'signals':signals,'warnings':warnings,'timeline':timeline,'shared_flight_verified':False}

def combined(paths):
 reports=[analyze(Path(p))for p in paths];hosts=set().union(*(set(r['host_ids'])for r in reports))
 warnings=[]
 if len(hosts)>1:warnings.append('Reports identify different hosts. Do not interpret their host ticks as a shared timeline.')
 if not {'host','guest'}<=set(r['role']for r in reports):warnings.append('Both host and guest reports are needed to compare peers.')
 if len({r['package']for r in reports})>1:warnings.append('Packages differ between supplied reports.')
 attempts=[set(r['attempt_ids'])for r in reports];matched=bool(attempts and all(attempts)and set.intersection(*attempts))
 if any(attempts)and not matched:warnings.append('Reports do not share a confirmed attempt_id; do not merge timelines.')
 common=[p for p in reports[0]['phases']if all(p in r['phases']for r in reports)]if reports else[]
 if any(attempts)and not matched:common=[]
 # Per-side errors retain local order. Do not infer cross-PC causality from UTC.
 for r in reports:r['last_common_phase_candidate']=common[-1]if common else None;r['attempt_match_confirmed']=matched
 return {'format':'ac8-diagnostic-analysis-v1','warnings':warnings,'reports':reports,'shared_flight_verified':False,'clock_note':'Host ticks are sampled and approximate; compare only a matched host/guest attempt with clock_ready=1. UTC clocks may differ. A phase flag alone is not proof of a working flight.'}

def markdown(result):
 lines=['# AC8 — разбор диагностических отчётов','',result['clock_note'],'']
 lines.extend('- '+x for x in result['warnings'])
 for r in result['reports']:
  if r.get('first_recorded_error'):lines+=['','Первый зарегистрированный отказ этой стороны: '+json.dumps(r['first_recorded_error'],ensure_ascii=False)]
  lines+=['',f"## {r['role']} · {r['package']}",'',f"Архив: `{Path(r['archive']).name}`",f"Событий: {r['events']}; код выхода: {r['exit_code']}.",'',"Этапы: "+' → '.join(r['phases']),'',"Отклонённые команды: "+json.dumps(r['rejects'],ensure_ascii=False),'',"Последние показатели:",'','```json',json.dumps(r['metrics'],ensure_ascii=False,indent=2),'```','']
  lines.extend('- '+x for x in r['warnings'])
  if r['signals']:lines+=['','Сигналы задержек (требуют проверки контекста):','',json.dumps(r['signals'][:20],ensure_ascii=False)]
  lines+=['','### Последние события','', '| Host tick (ms) | Seq | Event | Phase / scene | Detail |','| --- | --- | --- | --- | --- |']
  for e in r['timeline'][-120:]:
   detail=json.dumps(e['detail'],ensure_ascii=False,separators=(',',':'))[:600].replace('|','\\|').replace('\n',' ')
   lines.append(f"| {e['host_tick_ms'] if e['host_tick_ms'] is not None else '?'} | {e['sequence']} | {e['event']} | {e['phase']} / {e['scene']} | {detail} |")
 return '\n'.join(lines)+'\n'

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('reports',nargs='+',type=Path);parser.add_argument('--output',type=Path,required=True)
 args=parser.parse_args();result=combined(args.reports);args.output.mkdir(parents=True,exist_ok=True)
 (args.output/'analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 (args.output/'analysis.md').write_text(markdown(result),encoding='utf-8')
 print(json.dumps({'output':str(args.output.resolve()),'reports':len(result['reports']),'shared_flight_verified':False}))

if __name__=='__main__':main()
