"""Prepare two isolated UE4SS runtimes from the pinned accepted runtime whitelist."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / 'profiles/ac8-local-r12'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def prepare(adapter=False):
    global PROFILE
    if adapter:
        PROFILE = ROOT / 'profiles/ac8-local-r13'
    running = subprocess.run(['powershell.exe', '-NoProfile', '-Command',
                              'if(Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue){exit 10}else{exit 0}'], capture_output=True)
    if running.returncode and (not adapter or PROFILE.exists()):
        raise ValueError('Close the game before refreshing its local runtime')
    base = ROOT / 'profiles/ac8-build25201480-r8'
    accepted = json.loads((base / 'trial-manifest.json').read_text(encoding='utf-8-sig'))
    selected = {
        'runtime/LICENSE', 'runtime/UE4SS.dll', 'runtime/UE4SS-settings.ini',
        'runtime/Mods/mods.json', 'runtime/Mods/mods.txt',
        'runtime/Mods/shared/UEHelpers/UEHelpers.lua',
    }
    entries = {e['path'].replace('\\', '/'): e for e in accepted['files']}
    for name in selected:
        if name not in entries or digest(base / name) != entries[name]['sha256']:
            raise ValueError('Pinned runtime mismatch: ' + name)
    revision = 'r13' if adapter else 'r12'
    dll = ROOT / f'build/shared-session-{revision}/ac8_local_session_{revision}.dll'
    if not dll.is_file():
        raise ValueError('Build the native session first')
    files = []
    for role in ('host', 'guest'):
        folder = PROFILE / role
        for name in sorted(selected):
            target = folder / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(base / name, target)
            files.append(target)
        target = folder / f'runtime/ac8_local_session_{revision}.dll'
        shutil.copy2(dll, target)
        files.append(target)
        if adapter:
            target = folder / 'runtime/ac8_menu_route_r13.dll'
            shutil.copy2(ROOT / 'build/menu-route-r13/ac8_menu_route_r13.dll', target)
            files.append(target)
        scripts = folder / 'runtime/Mods/AC8CoopRecon/Scripts'
        scripts.mkdir(parents=True, exist_ok=True)
        sources = ['coop_main_menu.lua', 'coop_lobby_frontend.lua', 'coop_lobby_layout.lua', 'coop_menu_catalog.lua', 'shared_session_local_services.lua', 'shared_session_local_main.lua']
        if adapter:
            sources += ['local_hangar_inspect.lua', 'local_menu_native.lua', 'local_hangar_ui.lua', 'local_hangar_adapter.lua']
        sources += ['scene_codec.lua', 'scene_client.lua', 'scene_clock.lua', 'scene_host.lua', 'scene_preview.lua', 'scene_steam.lua',
                    'scene_transform.lua', 'scene_visual_host.lua', 'scene_engine.lua', 'scene_engine_session.lua', 'scene_visibility.lua', 'scene_preview_quality.lua',
                    'guest_pilot_view.lua', 'guest_pilot_camera.lua']
        for name in sources:
            target = scripts / ('main.lua' if name.endswith('_main.lua') else name)
            shutil.copy2(ROOT / 'probe/AC8CoopRecon/Scripts' / name, target)
            files.append(target)
    manifest = {
        'revision': revision+'-local-control-development', 'game_adapter_ready': False,
        'game_sha256': accepted['game_sha256'],
        'proxy_sha256': '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB',
        'files': [{'path': p.relative_to(PROFILE).as_posix(), 'sha256': digest(p)} for p in files],
    }
    PROFILE.mkdir(parents=True, exist_ok=True)
    (PROFILE / 'local-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(PROFILE)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser();parser.add_argument('--adapter',action='store_true')
    prepare(parser.parse_args().adapter)
