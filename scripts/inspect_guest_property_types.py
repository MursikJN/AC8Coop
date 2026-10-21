"""Read only: compare live FWeakObjectProperty class constraints with known class identities."""
import argparse,ctypes as C,hashlib,json,struct,time
from ctypes import wintypes as W
from pathlib import Path
GAME=Path(r'D:\Programs\Steam\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe')
SHA='51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
def inspect(session):
 pair=json.loads((session/'pair.json').read_text(encoding='utf-8-sig'));assert pair['host_exit'] is None
 source=session/'host/guest-property-addresses.tsv';assert abs(time.time()-source.stat().st_mtime)<120,'Stale reflection addresses'
 runtime=session.parents[1]/'host/runtime/UE4SS.log'
 assert 'FObjectPropertyBase::PropertyClass = 0x70' in runtime.read_text(encoding='utf-8-sig'), 'Layout not recorded by this runtime'
 assert hashlib.sha256(GAME.read_bytes()).hexdigest()==SHA,'Unsupported game build'
 classes={};inners={}
 for line in source.read_text().splitlines():
  kind,name,address=line.split('\t');(classes if kind=='class' else inners)[name]=int(address,0)
 assert set(inners)=={'RootAIGameObjects','ChildAIGameObjects','AliveChildAIGameObjects','GroupLeadPlanes'}
 k=C.WinDLL('kernel32',use_last_error=True);k.OpenProcess.argtypes=[W.DWORD,W.BOOL,W.DWORD];k.OpenProcess.restype=W.HANDLE
 k.ReadProcessMemory.argtypes=[W.HANDLE,C.c_void_p,C.c_void_p,C.c_size_t,C.POINTER(C.c_size_t)];k.ReadProcessMemory.restype=W.BOOL
 k.QueryFullProcessImageNameW.argtypes=[W.HANDLE,W.DWORD,W.LPWSTR,C.POINTER(W.DWORD)];k.QueryFullProcessImageNameW.restype=W.BOOL
 k.CloseHandle.argtypes=[W.HANDLE];h=k.OpenProcess(0x10|0x1000,False,pair['host_pid'])
 if not h:raise C.WinError(C.get_last_error())
 def read64(p):
  assert 0x10000<=p<0x800000000000
  b=C.create_string_buffer(8);n=C.c_size_t()
  if not k.ReadProcessMemory(h,p,b,8,C.byref(n))or n.value!=8:raise C.WinError(C.get_last_error())
  return struct.unpack('<Q',b.raw)[0]
 try:
  path=C.create_unicode_buffer(32768);length=W.DWORD(len(path))
  if not k.QueryFullProcessImageNameW(h,0,path,C.byref(length)):raise C.WinError(C.get_last_error())
  assert Path(path.value).resolve()==GAME.resolve(),'PID identity mismatch'
  arrays={}
  for name,p in inners.items():
   target=read64(p+0x70);arrays[name]={'class_pointer':hex(target),'class':next((n for n,p in classes.items()if p==target),'unmapped')}
  result={'read_only':True,'pid':pair['host_pid'],'property_class_offset':'0x70','arrays':arrays}
  (session/'host/guest-array-type-contract.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
 finally:k.CloseHandle(h)
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--session',required=True,type=Path);inspect(p.parse_args().session)
