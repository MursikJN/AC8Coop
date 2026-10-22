"""Stage a development profile without touching an active profile/game."""
from pathlib import Path
import argparse,hashlib,json,shutil,zipfile
ROOT=Path(__file__).resolve().parents[1]
LUA=('steam_lobby_main','steam_lobby_services','steam_coop_role','steam_coop_pilot','steam_coop_client','steam_coop_client_world','guest_owner_preparation',
 'coop_main_menu','coop_menu_catalog','coop_lobby_frontend','coop_lobby_layout','lobby_menu_lifetime','engine_call_trace',
 'mission_sync_adapter','mission_sync_pause','mission_sync_cinema_guard','mission_sync_status_ui','local_menu_native','local_hangar_ui',
 'guest_slot_resolver','guest_player_asset','guest_role_adapter','guest_role_runtime','guest_role_marker','guest_pilot_view','guest_pilot_camera',
 'scene_codec','scene_client','scene_host','scene_visual_host','scene_engine','scene_clock','scene_transform','scene_visibility')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def prepare(revision='r27'):
 assert revision in ('r27','r28','r29','r29-debug1','r29-debug2','r31')
 owner=revision=='r31';automatic=revision in ('r29-debug2','r31');diagnostic=revision in ('r29-debug1','r29-debug2','r31');native_revision='r29'if diagnostic and not owner else revision
 cinema=revision!='r27';policy=revision in ('r29','r29-debug1','r29-debug2','r31');PROFILE=ROOT/('profiles/ac8-steam-coop-'+revision)
 if(PROFILE/'evidence').exists():raise ValueError('Do not replace a used profile')
 base=ROOT/'profiles/ac8-build25201480-r8';accepted=json.loads((base/'trial-manifest.json').read_text(encoding='utf-8-sig'));pinned={v['path'].replace('\\','/'):v['sha256']for v in accepted['files']}
 selected=('runtime/LICENSE','runtime/UE4SS.dll','runtime/UE4SS-settings.ini','runtime/Mods/mods.json','runtime/Mods/mods.txt','runtime/Mods/shared/UEHelpers/UEHelpers.lua','Collect-CoopLogs.ps1')
 sources={name:base/name for name in selected}
 for name,path in sources.items():assert digest(path)==pinned[name],name
 native={
 'ac8_steam_coop_'+native_revision+'.dll':'steam-coop-'+native_revision,
 'ac8_menu_route_r13.dll':'menu-route-r13',
 'ac8_cinema_guard_r26_3.dll':'cinema-sync-r26',
 'ac8_mission_pause_r26.dll':'mission-pause-r26',
 'ac8_guest_player_init_r19.dll':'guest-player-r19',
 'ac8_guest_story_r19c.dll':'guest-story-r19c'}
 for name,folder in native.items():sources['runtime/'+name]=ROOT/'build'/folder/name
 for name in LUA:sources['runtime/Mods/AC8CoopRecon/Scripts/'+('main'if name=='steam_lobby_main'else name)+'.lua']=ROOT/'probe/AC8CoopRecon/Scripts'/(name+'.lua')
 if cinema:
  for name in ('cinema_playback','cinema_native'):sources['runtime/Mods/AC8CoopRecon/Scripts/'+name+'.lua']=ROOT/'probe/AC8CoopRecon/Scripts'/(name+'.lua')
 if policy:
  for name in ('session_lifecycle','session_recovery_ui'):sources['runtime/Mods/AC8CoopRecon/Scripts/'+name+'.lua']=ROOT/'probe/AC8CoopRecon/Scripts'/(name+'.lua')
  sources['Session-Policy.ps1']=ROOT/'scripts/Session-Policy.ps1'
 sources['Coop-AdapterEnvironment.ps1']=ROOT/'scripts/Coop-AdapterEnvironment.ps1'
 if diagnostic:
  sources['runtime/Mods/AC8CoopRecon/Scripts/session_diagnostics.lua']=ROOT/'probe/AC8CoopRecon/Scripts/session_diagnostics.lua'
  sources['Session-Diagnostics.ps1']=ROOT/'scripts/Session-Diagnostics.ps1'
  sources['Collect-CoopLogs.ps1']=ROOT/'coop/Collect-CoopLogs.ps1'
  sources['Collect-DebugLogs.ps1']=ROOT/'coop/Collect-DebugLogs.ps1'
 if automatic:sources['Auto-Reports.ps1']=ROOT/'scripts/Auto-Reports.ps1'
 if owner:
  for name in ('Coop-Kit','Coop-LabStorage','Prepare-CoopLab','Repair-CompactLab'):sources[name+'.ps1']=ROOT/'scripts'/(name+'.ps1')
  sources['Owner-Lab-Peer.exe']=ROOT/'build/steam-coop-r31/owner_lab_peer.exe'
  sources['runtime/Mods/AC8CoopRecon/Scripts/owner_local_lab.lua']=ROOT/'probe/AC8CoopRecon/Scripts/owner_local_lab.lua'
  sources['TEST-PLAN-RU.md']=ROOT/'coop/TEST-PLAN-R31-RU.md'
  sources['analyze_coop_reports.py']=ROOT/'scripts/analyze_coop_reports.py'
  sources['CREDITS.md']=ROOT/'coop/CREDITS-R31.md'
 sources['Start-SteamLobby.ps1']=ROOT/'scripts/Start-SteamLobby.ps1'
 sources['README-RU.md']=ROOT/('coop/README-STEAM-COOP-'+revision.upper()+'-RU.md')
 sources['loader/dwmapi.dll']=ROOT/'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll'
 proxy_hash='93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB';assert digest(sources['loader/dwmapi.dll'])==proxy_hash
 files=[]
 for name,path in sorted(sources.items()):
  target=PROFILE/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target);files.append(target)
 for role in('Host','Guest'):
  target=PROFILE/('Start-'+role+'.cmd');target.write_bytes((f'@echo off\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-SteamLobby.ps1" -Role {role.lower()} %*\r\nif errorlevel 1 pause\r\n').encode('ascii'));files.append(target)
 if diagnostic:
  target=PROFILE/'Collect-DebugLogs.cmd';target.write_bytes(b'@echo off\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-DebugLogs.ps1" %*\r\npause\r\n');files.append(target)
 if owner:
  commands={'Prepare-Lab':('Prepare-CoopLab.ps1',''),'Repair-Lab':('Prepare-CoopLab.ps1','-UpgradeCompact'),'Validate-Kit':('Prepare-CoopLab.ps1','-ValidateOnly'),'Validate-Lab':('Start-SteamLobby.ps1','-ValidateOnly -Role host'),'Start-LocalModelTest':('Start-SteamLobby.ps1','-Role guest -LocalModelTest')}
  for name,(script,args)in commands.items():
   target=PROFILE/(name+'.cmd');target.write_bytes((f'@echo off\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0{script}" {args} %*\r\npause\r\n').encode('ascii'));files.append(target)
 manifest=dict(revision=revision+'-development',protocol=8 if owner else 7 if policy else 6 if cinema else 5,pilot_protocol=3 if owner else 2,steam_invites=True,steam_coop=True,cinema_sync=cinema,session_policy=policy,
  native_file='runtime/ac8_steam_coop_'+native_revision+'.dll',game_sha256=accepted['game_sha256'],proxy_sha256=proxy_hash,
  steam_sha256='4DF999C0C8CB12589F0864D52BE5D4C775577AEB27FEE28B49B188F9BA083EEA',
  game_tested=False,client_world_loader_implemented=True,client_world_loader_game_verified=False,guest_cinematic_visuals_implemented=owner and cinema,guest_cinematic_adapter_implemented=cinema,guest_cinematic_visuals_game_verified=False,first_shared_flight_ready=False,full_mission_replication=False,
  host_progress_only=policy,lobby_only_entry=policy,shared_restart_mode='fresh_process_return_to_lobby'if policy else None,in_process_mission_restart_supported=False,
  session_diagnostics=diagnostic,diagnostics_schema=1 if diagnostic else 0,
  automatic_reports=automatic,
  owner_native=owner,isolated_lab_required=owner,local_model_test_implemented=owner,owner_runtime_tested=False,
  owner_world_readiness=1 if owner else 0,kit_update='cinema-2'if owner else None,adapter_bootstrap=1 if owner else 0,cinema_metadata=1 if owner else 0,native_shutdown=1 if owner else 0,menu_lifetime=1 if owner else 0,engine_call_trace=1 if owner else 0,
  lab_storage_policy=3 if owner else 0,lab_storage_default='compact'if owner else None,archive_layout='paks-junction-v1'if owner else None,shared_archives_read_locked=owner,
  scope=('Steam room + local stock F-14D simulation + owner-state transport + isolated client terrain/replicas + local cinematic barriers'if owner else'Steam room + mission barriers + input/pose transport + paused replica terrain loader candidate'+(' + local cinematic player candidates and per-clip two-peer completion barriers'if cinema else''))+'; not game validated',
  files=[dict(path=p.relative_to(PROFILE).as_posix(),sha256=digest(p))for p in sorted(files)])
 path=PROFILE/'lobby-manifest.json';path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8');files.append(path)
 archive=ROOT/('dist/ac8-steam-coop-'+revision+'-development.zip')
 archive.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED)as z:
  for p in sorted(files):z.write(p,PROFILE.name+'/'+p.relative_to(PROFILE).as_posix())
 archive.with_suffix(archive.suffix+'.sha256').write_text(digest(archive).lower()+'  '+archive.name+'\n',encoding='ascii')
 print(json.dumps(dict(profile=str(PROFILE),archive=str(archive),sha256=digest(archive),files=len(files),game_launched=False,first_shared_flight_ready=False),ensure_ascii=False))
 return manifest
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--revision',choices=('r27','r28','r29','r29-debug1','r29-debug2','r31'),default='r27');prepare(parser.parse_args().revision)
