"""Validate a freshly extracted R31 kit. Does not launch game or Steam."""
from pathlib import Path,PurePosixPath
import argparse
import hashlib
import json
import re
import subprocess
import uuid
import zipfile
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
def validate(archive,output):
 extraction=ROOT/'build'/('r31-unpacked-'+uuid.uuid4().hex);extraction.mkdir(parents=True)
 with zipfile.ZipFile(archive)as z:
  assert z.testzip()is None,'ZIP CRC failure'
  members=z.infolist();assert len(members)<200 and sum(i.file_size for i in members)<512*1024*1024
  seen=set()
  for i in members:
   p=PurePosixPath(i.filename);assert not p.is_absolute()and'..'not in p.parts and'\\'not in i.filename and':'not in i.filename
   key=i.filename.lower();assert key not in seen;seen.add(key)
   assert not i.is_dir();assert ((i.external_attr>>16)&0o170000)!=0o120000,'ZIP symlink'
  z.extractall(extraction)
 kit=extraction/'ac8-steam-coop-r31';m=json.loads((kit/'lobby-manifest.json').read_text())
 expected={f['path']for f in m['files']}|{'lobby-manifest.json'}
 actual={p.relative_to(kit).as_posix()for p in kit.rglob('*')if p.is_file()};assert actual==expected,'Unlisted/missing file'
 assert m['protocol']==8 and m['pilot_protocol']==3 and m['owner_native']and m['isolated_lab_required']and m['automatic_reports']
 assert m['owner_world_readiness']==1 and m['kit_update']=='cinema-1'and m['adapter_bootstrap']==1 and m['menu_lifetime']==1 and m['engine_call_trace']==1 and m['lab_storage_policy']==3 and m['archive_layout']=='paks-junction-v1'and m['shared_archives_read_locked']
 assert not m['game_tested']and not m['owner_runtime_tested']and not m['first_shared_flight_ready']
 lua=LuaRuntime(unpack_returned_tuples=True);compiled=0;text_scanned=0
 for f in m['files']:
  p=kit/f['path'];assert hashlib.sha256(p.read_bytes()).hexdigest().upper()==f['sha256'],f['path']
  assert p.suffix.lower()not in ('.pak','.utoc','.ucas','.sav','.dmp','.pdb','.obj','.lib'),f['path']
  assert p.name.lower()not in ('acecombat8.exe','steam_api64.dll','modlog.md'),f['path']
  if p.suffix=='.exe':assert p.name=='Owner-Lab-Peer.exe'
  if p.suffix=='.lua':lua.execute('local f,why=load(...);assert(f,why);return true',p.read_text(encoding='utf-8-sig'));compiled+=1
  if p.suffix.lower()in ('.lua','.ps1','.py','.md','.json','.cmd','.ini','.txt'):
   text=p.read_text(encoding='utf-8-sig',errors='replace');text_scanned+=1
   assert not re.search(r'gh[pousr]_[A-Za-z0-9]{30,}|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9_-]{40,}',text),'Possible embedded secret: '+f['path']
   assert not re.search(r'C:[\\/]Users[\\/](?:Administrator|[^\\/\s]+)[\\/]',text),'Personal absolute path: '+f['path']
 result=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(kit/'Prepare-CoopLab.ps1'),'-ValidateOnly'],capture_output=True,timeout=60)
 assert result.returncode==0,(result.stdout.decode(errors='replace'),result.stderr.decode(errors='replace'))
 assert not (kit/'lab-game').exists()and not (kit/'evidence').exists(),'Read-only validation created game/session'
 report=dict(format='ac8-r31-package-validation-v1',archive=str(archive),archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),files=len(actual),lua_syntax_checked=compiled,text_secret_path_checks=text_scanned,extraction=str(kit),manifest_hashes=True,zip_crc=True,pe_exports_and_ps5_preflight=True,game_files_included=False,game_launched=False,originals_written=False,shared_flight_verified=False)
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n');return report
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--archive',type=Path,default=ROOT/'dist/ac8-steam-coop-r31-development.zip');p.add_argument('--output',type=Path,default=ROOT/'evidence/r31-kit-20261022/package-validation.json');a=p.parse_args();print(json.dumps(validate(a.archive,a.output)))
