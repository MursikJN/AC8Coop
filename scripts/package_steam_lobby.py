"""Build one identical portable host/guest package from a pinned minimal whitelist."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PROFILE=ROOT/'profiles/ac8-steam-lobby-r25'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def prepare():
 base=ROOT/'profiles/ac8-build25201480-r8'
 accepted=json.loads((base/'trial-manifest.json').read_text(encoding='utf-8-sig'))
 entries={e['path'].replace('\\','/'):e for e in accepted['files']}
 selected=['runtime/LICENSE','runtime/UE4SS.dll','runtime/UE4SS-settings.ini','runtime/Mods/mods.json','runtime/Mods/mods.txt','runtime/Mods/shared/UEHelpers/UEHelpers.lua','Collect-CoopLogs.ps1']
 sources={name:base/name for name in selected}
 for name in selected:
  if digest(sources[name])!=entries[name]['sha256']:raise ValueError('Pinned runtime mismatch: '+name)
 sources['runtime/ac8_steam_lobby_r25.dll']=ROOT/'build/steam-lobby-r25/ac8_steam_lobby_r25.dll'
 proxy=ROOT/'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll'
 proxy_hash='93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB'
 if digest(proxy)!=proxy_hash:raise ValueError('Loader mismatch')
 sources['loader/dwmapi.dll']=proxy
 sources['Start-SteamLobby.ps1']=ROOT/'scripts/Start-SteamLobby.ps1'
 sources['README-RU.md']=ROOT/'coop/README-STEAM-INVITES-R25-RU.md'
 for name in ['steam_lobby_main.lua','steam_lobby_services.lua','coop_main_menu.lua','coop_lobby_frontend.lua','coop_lobby_layout.lua','coop_menu_catalog.lua']:
  sources['runtime/Mods/AC8CoopRecon/Scripts/'+('main.lua'if name=='steam_lobby_main.lua'else name)]=ROOT/'probe/AC8CoopRecon/Scripts'/name
 if (PROFILE/'evidence').exists():raise ValueError('Do not refresh a used profile; prepare a separate clean profile')
 files=[]
 for name,source in sorted(sources.items()):
  target=PROFILE/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target);files.append(target)
 for role in ['Host','Guest']:
  target=PROFILE/f'Start-{role}.cmd'
  target.write_bytes((f'@echo off\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-SteamLobby.ps1" -Role {role.lower()} %*\r\nif errorlevel 1 pause\r\n').encode('ascii'));files.append(target)
 manifest={'revision':'r25','protocol':3,'steam_invites':True,'native_file':'runtime/ac8_steam_lobby_r25.dll','scope':'Steam lobby with invitations; game already running','full_mission_replication':False,'game_sha256':accepted['game_sha256'],'proxy_sha256':proxy_hash,'steam_sha256':'4DF999C0C8CB12589F0864D52BE5D4C775577AEB27FEE28B49B188F9BA083EEA','files':[{'path':p.relative_to(PROFILE).as_posix(),'sha256':digest(p)}for p in sorted(files)]}
 target=PROFILE/'lobby-manifest.json';target.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8');files.append(target)
 archive=ROOT/'dist/ac8-steam-lobby-r25.zip';archive.parent.mkdir(exist_ok=True)
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED)as z:
  for file in sorted(files):z.write(file,PROFILE.name+'/'+file.relative_to(PROFILE).as_posix())
 print(json.dumps({'profile':str(PROFILE),'archive':str(archive),'sha256':digest(archive),'files':len(files)},ensure_ascii=False))
if __name__=='__main__':prepare()
