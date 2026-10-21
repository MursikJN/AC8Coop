"""Two real native DLL processes: delayed loads, expired commits, repeated commands and cutscene votes."""
import ctypes,json,os,secrets,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DLL=ROOT/'build/mission-sync-r26/ac8_local_session_r26.dll'
def read(folder):
 try:return dict(line.split('\t',1)for line in(folder/'shared-session-status.tsv').read_text().splitlines())
 except(OSError,ValueError):return{}
def wait(fn,message,timeout=7):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  value=fn()
  if value:return value
  time.sleep(.01)
 raise AssertionError(message)
def worker(role,folder,token,port):
 os.environ.update(AC8_LOCAL_SESSION='25201480',AC8_MISSION_SYNC='25201480',AC8_LOCAL_HANGAR='25201480',AC8_LOCAL_ROLE=role,AC8_LOCAL_PORT=port,AC8_LOCAL_TOKEN=token,AC8_COOP_RECON_OUTPUT=folder)
 lib=ctypes.CDLL(str(DLL));lib.luaopen_ac8_local_start(None)
 until=time.monotonic()+120
 while time.monotonic()<until and not(Path(folder)/'stop').exists():time.sleep(.01)
 lib.luaopen_ac8_local_stop(None);lib.ac8_local_wait_stopped.argtypes=[ctypes.c_ulong]
 assert lib.ac8_local_wait_stopped(5000)==1
def trial():
 output=ROOT/'build'/('mission-sync-trial-'+time.strftime('%Y%m%d-%H%M%S'));output.mkdir()
 token=str(secrets.randbelow(2**53-1)+1);children=[];counter={};folders={}
 def start(role,port):
  folder=output/role;folder.mkdir();folders[role]=folder;counter[role]=0
  p=subprocess.Popen([sys.executable,__file__,'--worker',role,str(folder),token,str(port)]);children.append(p);return folder
 def command(role,op,a=0,b=0,expected=None,reject=0):
  if role=='guest'and expected is None:
   wait(lambda:all(read(folders['guest']).get(k)==read(folders['host']).get(k)for k in('epoch','revision','changes')),'guest snapshot behind host')
  folder=folders[role];s=read(folder);counter[role]+=1;request=counter[role];epoch,revision=expected or(s['epoch'],s['revision'])
  data=dict(request=request,epoch=epoch,revision=revision,op=op,arg0=a,arg1=b)
  payload=''.join(f'{k}\t{v}\n'for k,v in data.items()).encode();(folder/'shared-session-command.tsv').write_bytes(payload)
  wait(lambda:int(read(folder).get('request_confirmed',0))>=request,'missing authoritative confirmation')
  state=read(folder);assert int(state['reject'])==reject,(role,op,state)
  return payload,state
 def release():
  s=wait(lambda:read(host)if int(read(host).get('release_at',0))else None,'release schedule missing');deadline=int(s['release_at'])
  command('host',13,deadline&0xffffffff,deadline>>32);wait(lambda:read(guest).get('release_at')==str(deadline),'guest lacks schedule')
  command('guest',13,deadline&0xffffffff,deadline>>32)
  wait(lambda:read(host).get('release_at')=='0','barrier did not release')
 def stage(value):return wait(lambda:read(host)if read(host).get('phase')==str(value)else None,'stage not reached: '+str(value))
 try:
  host=start('host',0);port=wait(lambda:read(host).get('port'),'host port missing');guest=start('guest',port)
  wait(lambda:read(guest).get('have_snapshot')=='1','guest not synchronized')
  command('host',2,6,1);command('guest',3,23);command('host',1,1);command('guest',1,1);wait(lambda:read(host).get('ready_mask')=='3','not ready')
  command('host',9,1);command('host',7);before=read(host)['changes'];command('host',7);assert read(host)['changes']==before
  time.sleep(2);assert read(host)['phase']=='1'and read(host)['loaded_mask']=='1'and read(host)['release_at']=='0'
  command('guest',7);first=int(wait(lambda:read(host).get('release_at')if int(read(host).get('release_at',0))else None,'not armed'))
  command('host',13,first&0xffffffff,first>>32)
  wait(lambda:int(read(host).get('release_at',0))>first,'missing commit must rearm');assert read(host)['phase']=='1'
  command('guest',13,first&0xffffffff,first>>32,reject=3)
  release();stage(2);command('host',5,1);before=read(host)['changes'];command('host',5,1);assert read(host)['vote_mask']=='1'and read(host)['changes']==before
  command('guest',5,1);assert read(host)['vote_mask']=='3'and read(host)['phase']=='2'
  old=(read(host)['epoch'],read(host)['revision']);command('host',14,2);assert read(host)['vote_mask']=='0'
  command('guest',5,1,expected=old,reject=3);assert read(host)['scene']=='2'and read(host)['vote_mask']=='0'
  command('host',8,2);command('guest',7);command('host',7,reject=5);command('host',11,7,23);release();stage(4);assert read(host)['ready_mask']=='0'
  command('host',6,reject=5);command('host',1,1);command('guest',1,1);payload,_=command('host',6)
  (host/'shared-session-command.tsv').write_bytes(payload);time.sleep(.2);assert read(host)['generation']=='1'and read(host)['phase']=='5'
  command('host',12);time.sleep(2);assert read(host)['phase']=='5'and read(host)['release_at']=='0'
  command('guest',7);release();stage(6);assert read(host)['generation']=='1'
  (guest/'stop').touch();wait(lambda:read(host).get('transport')=='disconnected','disconnect not detected');assert read(host)['phase']=='8'
  result=dict(result='passed',actual_native_dll=True,protocol=4,delayed_intro_seconds=2,delayed_flight_seconds=2,expired_commit_rearmed=True,old_commit_rejected=True,single_vote_holds=True,two_votes_wait_for_actual_scene_end=True,repeated_vote_inert=True,next_segment_clears_votes=True,old_scene_vote_rejected=True,hangar_requires_new_ready=True,repeated_sortie_single_generation=True,disconnect_stops_session=True,gameplay_tested=False)
  (output/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(dict(output=str(output),**result),indent=2))
 finally:
  for folder in folders.values():(folder/'stop').touch()
  for p in children:
   try:p.wait(timeout=7)
   except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=5)
  assert all(p.returncode==0 for p in children)
if __name__=='__main__':
 if len(sys.argv)>1 and sys.argv[1]=='--worker':worker(*sys.argv[2:])
 else:trial()
