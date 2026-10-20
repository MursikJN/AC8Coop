"""Build a fresh portable diagnostic package. Never ship game binaries or old probes."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path('D:/projects/unreal-mod-tools')
VERSION = '0.1.2'
DEST = TOOLS / f'packages/ac8-connection-test-{VERSION}'
ZIP = TOOLS / f'dist/ac8-connection-test-{VERSION}.zip'
RUNTIME = TOOLS / 'profiles/ac8-build25201480/runtime'
HEADERS = TOOLS / 'references/valve-networking-headers'


def digest(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest().upper()


def copy(source, relative):
    target = DEST / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def write(relative, text, encoding='utf-8-sig'):
    target = DEST / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding=encoding)


def main():
    if DEST.exists() or ZIP.exists():
        raise SystemExit('Destination already exists; use a new version or inspect it explicitly.')
    DEST.mkdir(parents=True)
    for name in ('Launch-ConnectionTest.ps1', 'Remove-ConnectionLoader.ps1', 'README-RU.md'):
        copy(ROOT / 'connection-test' / name, name)
    write('READ-ME-RU.txt', (ROOT / 'connection-test/README-RU.md').read_text(encoding='utf-8'))
    for role in ('Host', 'Guest'):
        write(f'Start-{role}.cmd', '@echo off\n'
              f'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-ConnectionTest.ps1" -Role {role}\n'
              'pause\n', 'ascii')
    write('Cleanup.cmd', '@echo off\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-ConnectionLoader.ps1"\npause\n', 'ascii')
    write('peers.json', json.dumps({'host_steam_id': '', 'guest_steam_id': ''}, indent=2) + '\n')
    copy(TOOLS / 'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll', 'loader/dwmapi.dll')
    for name in ('UE4SS.dll', 'UE4SS-settings.ini'):
        copy(RUNTIME / name, 'runtime/' + name)
    for name in ('CustomGameConfigs', 'Default_UVTD_Configs', 'MapGenBP', 'MemberVarLayoutTemplates',
                 'UE4SS_SDK_Backends', 'UE4SS_Signatures', 'VTableLayoutTemplates'):
        shutil.copytree(RUNTIME / name, DEST / 'runtime' / name)
    copy(TOOLS / 'build/connection-test/ac8_connection_test.dll', 'runtime/ac8_connection_test.dll')
    copy(ROOT / 'connection-test/main.lua', 'runtime/Mods/AC8ConnectionTest/Scripts/main.lua')
    write('runtime/Mods/mods.txt', 'AC8ConnectionTest : 1\n', 'ascii')
    copy(RUNTIME / 'LICENSE', 'licenses/UE4SS.txt')
    copy(HEADERS / 'LICENSE', 'licenses/Valve-GameNetworkingSockets.txt')
    for name in ('connection_test.cpp', 'connection_protocol.h', 'connection_protocol_tests.cpp', 'connection_runtime_tests.cpp'):
        copy(ROOT / 'native' / name, 'source/native/' + name)
    for name in ('Build-ConnectionTest.ps1', 'package_connection_test.py'):
        copy(ROOT / 'scripts' / name, 'source/scripts/' + name)
    for name in HEADERS.iterdir():
        if name.is_file():
            copy(name, 'source/valve-networking-headers/' + name.name)
    copy(ROOT / 'tests/test_connection_lua.py', 'source/tests/test_connection_lua.py')
    for name in ('main.lua', 'Launch-ConnectionTest.ps1', 'Remove-ConnectionLoader.ps1', 'README-RU.md'):
        copy(ROOT / 'connection-test' / name, 'source/connection-test/' + name)
    files = sorted(p for p in DEST.rglob('*') if p.is_file())
    forbidden = [p for p in files if p.suffix.lower() in ('.exe', '.log', '.pdb') or p.name.lower() == 'steam_api64.dll']
    assert not forbidden, forbidden
    manifest = {'schema_version': 1, 'package_version': VERSION,
                'game_sha256': '51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F',
                'steam_dll_sha256': '4DF999C0C8CB12589F0864D52BE5D4C775577AEB27FEE28B49B188F9BA083EEA',
                'files': [{'path': p.relative_to(DEST).as_posix(), 'sha256': digest(p)} for p in files]}
    write('manifest.json', json.dumps(manifest, indent=2) + '\n')
    ZIP.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ZIP, 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(p for p in DEST.rglob('*') if p.is_file()):
            z.write(path, DEST.name + '/' + path.relative_to(DEST).as_posix())
    with zipfile.ZipFile(ZIP) as z:
        assert z.testzip() is None
        assert len(z.namelist()) == len(files) + 1
        for entry in manifest['files']:
            content = z.read(DEST.name + '/' + entry['path'])
            assert hashlib.sha256(content).hexdigest().upper() == entry['sha256']
    print(json.dumps({'directory': str(DEST), 'archive': str(ZIP), 'bytes': ZIP.stat().st_size,
                      'sha256': digest(ZIP), 'manifest_files': len(files)}, indent=2))


if __name__ == '__main__':
    main()
