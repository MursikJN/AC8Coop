"""Package a prepared R7 profile without private settings, sessions, SDK or game files."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def digest(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest().upper()


def package(profile, dest):
    profile=profile.resolve();dest=dest.resolve()
    if dest.exists() or dest.with_suffix('.zip').exists():raise ValueError('Destination already exists')
    manifest=json.loads((profile/'trial-manifest.json').read_text(encoding='utf-8-sig'))
    revision=manifest['revision']
    if revision not in ('r7','r8','r9','r10'):raise ValueError('Not a supported coop profile')
    profile_name='ac8-build25201480-'+revision
    output=dest/'profiles'/profile_name;output.mkdir(parents=True)
    for entry in manifest['files']:
        src=(profile/entry['path']).resolve()
        if not src.is_relative_to(profile) or digest(src)!=entry['sha256']:raise ValueError('Profile hash/path mismatch')
        target=output/src.relative_to(profile);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    shutil.copy2(profile/'trial-manifest.json',output/'trial-manifest.json')
    for name in (('Start-Coop.cmd',) if revision in ('r8','r9','r10') else ('Start-Host.cmd','Start-Guest.cmd','Review-And-Arm.cmd')):
        text='@echo off\r\ncall "%~dp0profiles\\'+profile_name+'\\'+name+'"\r\n'
        (dest/name).write_bytes(text.encode('ascii'))
    proxy=ROOT/'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll'
    if digest(proxy)!='93B9431A5A4F32C675D269C5DA1C9B3EC6F88552EC20C282AB435F411E9271FB':raise ValueError('Proxy hash mismatch')
    proxy_out=dest/'packages/ue4ss-3.0.1-1181-g83330635/dwmapi.dll';proxy_out.parent.mkdir(parents=True);shutil.copy2(proxy,proxy_out)
    shutil.copy2(ROOT/('coop/README-LOBBY-R10-RU.md' if revision=='r10' else 'coop/README-LOBBY-RU.md' if revision=='r9' else 'coop/README-MENU-RU.md' if revision=='r8' else 'coop/README-RU.md'),dest/'README-RU.md')
    licenses=dest/'licenses';licenses.mkdir();shutil.copy2(ROOT/'packages/valve-headers-d534/LICENSE',licenses/'Valve-GameNetworkingSockets-LICENSE.txt')
    files=sorted(p for p in dest.rglob('*') if p.is_file())
    if any(p.name.lower() in ('acecombat8.exe','steam_api64.dll') or any(part in ('state','evidence','.git') for part in p.relative_to(dest).parts) for p in files):raise ValueError('Private settings/game files in package')
    (dest/'package-manifest.json').write_text(json.dumps({'revision':revision,'files':[{'path':p.relative_to(dest).as_posix(),'sha256':digest(p)} for p in files]},indent=2)+'\n',encoding='utf-8')
    archive=dest.with_suffix('.zip')
    with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(p for p in dest.rglob('*') if p.is_file()):z.write(p,dest.name+'/'+p.relative_to(dest).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip():raise ValueError('Bad archive')
        for p in files:
            if hashlib.sha256(z.read(dest.name+'/'+p.relative_to(dest).as_posix())).hexdigest().upper()!=digest(p):raise ValueError('Archive content mismatch')
    return {'directory':str(dest),'archive':str(archive),'bytes':archive.stat().st_size,'sha256':digest(archive)}


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--profile',type=Path,default=ROOT/'profiles/ac8-build25201480-r7');ap.add_argument('--dest',type=Path,default=ROOT/'dist/AC8CoopFlight-r7');args=ap.parse_args();print(json.dumps(package(args.profile,args.dest),indent=2))
