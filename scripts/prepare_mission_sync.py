"""Prepare a separate r26 one-game laboratory; never refresh a used profile."""
from pathlib import Path
import argparse,datetime,hashlib,json,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
PROFILE=ROOT/'profiles/ac8-local-r26'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def prepare(refresh_closed=False):
 if(PROFILE/'evidence').exists()and not refresh_closed:raise ValueError('Profile already used; use --refresh-closed after closing the game')
 if refresh_closed:
  subprocess.run(['powershell.exe','-NoProfile','-Command',"if(Get-Process AceCombat8,start_protected_game,EasyAntiCheat_EOS -ErrorAction SilentlyContinue){exit 1}"],check=True,capture_output=True)
  old=PROFILE/'local-manifest.json'
  if old.exists():
   backup=ROOT/'build'/('mission-sync-manifest-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'.json');shutil.copy2(old,backup)
 base=ROOT/'profiles/ac8-build25201480-r8';accepted=json.loads((base/'trial-manifest.json').read_text(encoding='utf-8-sig'))
 entries={f['path'].replace('\\','/'):f for f in accepted['files']}
 files=[]
 for role in('host','guest'):
  sources={n:base/n for n in('runtime/LICENSE','runtime/UE4SS.dll','runtime/UE4SS-settings.ini','runtime/Mods/mods.json','runtime/Mods/mods.txt','runtime/Mods/shared/UEHelpers/UEHelpers.lua')}
  for name,p in sources.items():assert digest(p)==entries[name]['sha256'],name
  sources['runtime/ac8_local_session_r26.dll']=ROOT/'build/mission-sync-r26/ac8_local_session_r26.dll'
  sources['runtime/ac8_menu_route_r13.dll']=ROOT/'build/menu-route-r13/ac8_menu_route_r13.dll'
  sources['runtime/ac8_cinema_guard_r26_3.dll']=ROOT/'build/cinema-sync-r26/ac8_cinema_guard_r26_3.dll'
  sources['runtime/ac8_mission_pause_r26.dll']=ROOT/'build/mission-pause-r26/ac8_mission_pause_r26.dll'
  for name in('mission_sync_main.lua','mission_sync_services.lua','mission_sync_probe.lua','mission_sync_adapter.lua','mission_sync_cinema_guard.lua','mission_sync_pause.lua','mission_sync_status_ui.lua','coop_main_menu.lua','coop_menu_catalog.lua','coop_lobby_frontend.lua','coop_lobby_layout.lua','local_menu_native.lua','local_hangar_ui.lua'):
   sources['runtime/Mods/AC8CoopRecon/Scripts/'+('main.lua'if name=='mission_sync_main.lua'else name)]=ROOT/'probe/AC8CoopRecon/Scripts'/name
  for name,p in sources.items():
   target=PROFILE/role/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target);files.append(target)
 manifest=dict(revision='r26-local-mission-sync',protocol=4,game_adapter_ready=False,game_sha256=accepted['game_sha256'],proxy_sha256='93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB',files=[dict(path=p.relative_to(PROFILE).as_posix(),sha256=digest(p))for p in files])
 (PROFILE/'local-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8');print(PROFILE)
if __name__=='__main__':
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--refresh-closed',action='store_true');args=ap.parse_args();prepare(args.refresh_closed)
