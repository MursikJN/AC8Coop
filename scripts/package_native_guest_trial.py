"""Seal the native-world guest diagnostic without old menu/flight modules or private state."""
import hashlib
import json
import shutil
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()

def package():
    name = 'ac8-native-guest-r11b'
    profile = ROOT / 'profiles' / name
    destination = ROOT / 'dist/AC8NativeGuest-r11b'
    archive = destination.with_suffix('.zip')
    if any(p.exists() for p in (profile, destination, archive)):
        raise ValueError('Destination already exists')
    base = ROOT / 'profiles/ac8-build25201480-r8'
    accepted = json.loads((base/'trial-manifest.json').read_text(encoding='utf-8-sig'))
    whitelist = {'Launch-Recon.ps1', 'Remove-ReconLoader.ps1', 'runtime/LICENSE',
                 'runtime/UE4SS-settings.ini', 'runtime/UE4SS.dll', 'runtime/Mods/mods.json',
                 'runtime/Mods/mods.txt', 'runtime/Mods/shared/UEHelpers/UEHelpers.lua'}
    copied = set()
    for item in accepted['files']:
        relative = item['path'].replace('\\', '/')
        if relative not in whitelist:
            continue
        source = base/relative
        if digest(source) != item['sha256']:
            raise ValueError('Accepted runtime hash mismatch: '+relative)
        target = profile/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied.add(relative)
    if copied != whitelist:
        raise ValueError('Incomplete runtime selection')
    scripts = profile/'runtime/Mods/AC8CoopRecon/Scripts'
    scripts.mkdir(parents=True)
    for src, target in [('shared_session_guest_main.lua', 'main.lua'),
                        ('shared_session_guest_trial.lua', 'state_probe.lua'),
                        ('shared_session_connection_observer.lua', 'shared_session_connection_observer.lua'),
                        ('shared_session_error_observer.lua','shared_session_error_observer.lua')]:
        shutil.copy2(ROOT/'probe/AC8CoopRecon/Scripts'/src, scripts/target)
    shutil.copy2(ROOT/'build/steam-legacy-state-r11b/ac8_steam_legacy_state_r11b.dll', profile/'runtime/ac8_steam_legacy_state_r11b.dll')
    for src, target in [('Start-NativeGuest.ps1', 'Start-Guest.ps1'),
                        ('Collect-NativeLogs.ps1', 'Collect-NativeLogs.ps1')]:
        shutil.copy2(ROOT/'coop'/src, profile/target)
    launch = profile/'Launch-Recon.ps1'
    text = launch.read_text(encoding='utf-8-sig').replace(
        'Stay in single-player. F8 captures objects. Exit the game normally to remove the loader.',
        'Native guest trial: press Enter at the title, then wait in the main menu. No F8. Exit normally for loader cleanup.')
    text=text.replace("if (Test-Path -LiteralPath $proxyTarget) {", "if ((Get-FileHash -LiteralPath $steamDll).Hash -ne $expectedSteamDll) { throw 'Steam DLL hash mismatch.' }\nif (Test-Path -LiteralPath $proxyTarget) {")
    launch.write_text(text, encoding='utf-8-sig')
    files = sorted(p for p in profile.rglob('*') if p.is_file())
    manifest = {'revision': 'native-world-r11b', 'purpose': 'native Steam world connection diagnostic with failure and legacy P2P state observation; no shared flight implemented',
                'files': [{'path': p.relative_to(profile).as_posix(), 'sha256': digest(p)} for p in files]}
    (profile/'native-trial-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    output = destination/'profiles'/name
    shutil.copytree(profile, output)
    for cmd, script in [('Start-Guest.cmd', 'Start-Guest.ps1'), ('Collect-Logs.cmd', 'Collect-NativeLogs.ps1')]:
        (destination/cmd).write_bytes((
            '@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0profiles\\'+name+'\\'+script+'"\r\npause\r\n').encode('ascii'))
    proxy = ROOT/'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll'
    if digest(proxy) != '93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB':
        raise ValueError('Proxy mismatch')
    proxy_target = destination/'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll'
    proxy_target.parent.mkdir(parents=True)
    shutil.copy2(proxy, proxy_target)
    shutil.copy2(ROOT/'coop/README-NATIVE-GUEST-RU.md', destination/'README-RU.md')
    files = sorted(p for p in destination.rglob('*') if p.is_file())
    for p in files:
        rel = p.relative_to(destination)
        if p.name.lower() in ('acecombat8.exe', 'steam_api64.dll') or any(x in ('state','evidence','reports','.git') for x in rel.parts):
            raise ValueError('Private or game files in package')
    (destination/'package-manifest.json').write_text(json.dumps({'revision': 'native-world-r11b',
        'files': [{'path': p.relative_to(destination).as_posix(), 'sha256': digest(p)} for p in files]}, indent=2)+'\n', encoding='utf-8')
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(p for p in destination.rglob('*') if p.is_file()):
            z.write(p, destination.name+'/'+p.relative_to(destination).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip():
            raise ValueError('Archive corruption')
        for p in files:
            if hashlib.sha256(z.read(destination.name+'/'+p.relative_to(destination).as_posix())).hexdigest().upper()!=digest(p):
                raise ValueError('Archive bytes mismatch')
    print(json.dumps({'archive':str(archive), 'sha256':digest(archive), 'bytes':archive.stat().st_size}, indent=2))

if __name__ == '__main__':
    package()
