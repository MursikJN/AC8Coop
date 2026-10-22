"""Run only our native DLL refusal paths inside Python, never a game process."""
from pathlib import Path
import argparse, ctypes, hashlib, json, os, time, uuid
ROOT=Path(__file__).resolve().parents[1]
def run(kit,output,with_lua=False):
 scratch=ROOT/'build'/('adapter-native-smoke-'+uuid.uuid4().hex);scratch.mkdir(parents=True)
 original={k:v for k,v in os.environ.items()if k.startswith('AC8_')}
 for k in list(original):os.environ.pop(k)
 os.environ['AC8_COOP_RECON_OUTPUT']=str(scratch)
 os.environ['AC8_LOCAL_SCRIPTS']=str(kit/'runtime/Mods/AC8CoopRecon/Scripts')
 checks=[]
 try:
  for prefix,dll,symbol in [('menu-route','ac8_menu_route_r13.dll','luaopen_ac8_menu_route'),('mission-pause','ac8_mission_pause_r26.dll','luaopen_ac8_mission_pause')]:
   # Match Lua's actual mixed-separator, parent-relative load path.
   loaded=ctypes.CDLL(str(kit/'runtime/Mods/AC8CoopRecon/Scripts')+'/../../../'+dll);call=getattr(loaded,symbol);call.argtypes=[ctypes.c_void_p];call.restype=ctypes.c_int
   for mode in ['missing','wrong','valid']:
    gate='AC8_MENU_ROUTE'if prefix=='menu-route'else'AC8_MISSION_SYNC'
    if mode=='missing':os.environ.pop(gate,None)
    else:os.environ[gate]='bad'if mode=='wrong'else'25201480'
    stamp='smoke-'+uuid.uuid4().hex
    text=f'format\t'+('ac8-menu-route-v1'if prefix=='menu-route'else'ac8-mission-pause-v2')+f'\nstamp\t{stamp}\ncreated_unix\t{int(time.time())}\nobject\t0x0\n'
    text+=('operation\tbootstrap\nkind\tbootstrap\n'if prefix=='menu-route'else'op\tbootstrap\n')
    (scratch/(prefix+'-request.tsv')).write_text(text,encoding='ascii')
    response=scratch/(prefix+'-status.tsv');response.unlink(missing_ok=True)
    assert call(None)==0
    data=dict(line.split('\t',1)for line in response.read_text().splitlines())
    assert data['stamp']==stamp
    assert data['reason']==('bootstrap_process'if mode=='valid'else'bootstrap_environment'),data
    assert data.get('status','refused')=='refused'and data.get('ok','0')=='0'
    checks.append(dict(adapter=prefix,mode=mode,reason=data['reason'],stamp_correlated=True))
  if with_lua:
   from lupa import LuaRuntime
   lua=LuaRuntime(unpack_returned_tuples=True)
   lua.globals().Menu=lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/local_menu_native.lua').read_text(encoding='utf-8'))
   lua.globals().Pause=lua.execute((ROOT/'probe/AC8CoopRecon/Scripts/mission_sync_pause.lua').read_text(encoding='utf-8'))
   lua.globals().OUT=str(scratch);lua.globals().SOURCE=str(kit/'runtime/Mods/AC8CoopRecon/Scripts')
   lua.execute("AC8LocalMenuDll=SOURCE..'/../../../ac8_menu_route_r13.dll';N=Menu.new(OUT);P=Pause.new(OUT,SOURCE)")
   for obj,prefix in [('N','menu'),('P','pause')]:
    ok,why=lua.eval('pcall('+obj+'.bootstrap)');assert not ok and prefix+'_native_bootstrap_process' in str(why),why
    checks.append(dict(adapter=prefix,mode='real_lua_native_boundary',reason='bootstrap_process',stamp_correlated=True))
  report=dict(format='ac8-native-adapter-refusal-test-v1',checks=checks,dll_sha256={name:hashlib.sha256((kit/'runtime'/name).read_bytes()).hexdigest()for name in ['ac8_menu_route_r13.dll','ac8_mission_pause_r26.dll']},game_launched=False,game_functions_called=False,positive_game_bootstrap_tested=False)
  output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n');return report
 finally:
  for k in list(os.environ):
   if k.startswith('AC8_'):os.environ.pop(k)
  os.environ.update(original)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--kit',type=Path,default=ROOT/'profiles/ac8-steam-coop-r31');p.add_argument('--output',type=Path,required=True);p.add_argument('--with-lua',action='store_true');a=p.parse_args();print(json.dumps(run(a.kit.resolve(),a.output,a.with_lua)))
