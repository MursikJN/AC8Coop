"""Bounded commands for the r26 local laboratory. Does not send to Steam or a remote PC."""
import argparse,json,time,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
HOST_COMMANDS={'ready':'c.ready()','intro':'c.open_hangar()','vote':'c.vote_skip()','sortie':'assert(_G.AC8MissionSyncAdapter).start()'}
def send(session,role,action,key=None,milliseconds=None):
 session=session.resolve();session.relative_to((ROOT/'profiles/ac8-local-r26/evidence').resolve())
 d=json.loads((session/'simulator-session.json').read_text(encoding='utf-8-sig'));assert d['mission_sync']is True
 identifier='lab_'+str(time.time_ns())+'_'+uuid.uuid4().hex[:6]
 if role=='guest':
  assert action in('connect','plane','ready','vote','repeat','delay')
  job=dict(id=identifier,token=d['token'],action=action)
  if action=='delay':
   key=int(key)if str(key).isdigit()else key;assert key in(1,3,5,'commit')and milliseconds is not None and 0<=milliseconds<=60000
   job.update(key=key,milliseconds=milliseconds)
  path=Path(d['guest_output'])/'simulator-command.json';path.write_text(json.dumps(job),encoding='utf-8')
 elif role=='host':
  command=HOST_COMMANDS[action]
  code="return function(output,id,c) local ok,err=pcall(function() "+command+" end);local f=assert(io.open(output..'/sync-result-'..id..'.tsv','w'));f:write('ok\\t',ok and '1'or'0','\\nerror\\t',tostring(err or''),'\\n');f:close() end\n"
  (ROOT/'profiles/ac8-local-r26/host/runtime/Mods/AC8CoopRecon/Scripts/sync_job.lua').write_text(code,encoding='utf-8')
  (Path(d['host_output'])/'sync-job.txt').write_text(identifier,encoding='ascii')
 else:raise ValueError('Role')
 print(identifier);return identifier
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--session',type=Path,required=True);p.add_argument('role',choices=('host','guest'));p.add_argument('action');p.add_argument('--key');p.add_argument('--milliseconds',type=int);a=p.parse_args();send(a.session,a.role,a.action,a.key,a.milliseconds)
