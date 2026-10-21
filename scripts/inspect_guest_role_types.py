"""Read-only native metadata at the guest mission-role boundary; executes no game code."""
import argparse,ctypes as C,hashlib,json,struct,time
from ctypes import wintypes as W
from pathlib import Path
GAME=Path(r'D:\Programs\Steam\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe')
SHA='51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
SELECT={'FindAIGameObjectByWDName','BattleNavigation','BattleNavigationUnit','BattleNavigationUnitList','GetObjNameID','GetCallsign','GetCallsignID','GetUnitName','OnChangeInputWingmanState','GetWorldUILocation','GetDisplayName','GetDisplayHealthRate','GetDisplayFaction','ModifyHealth','GetHealth','GetMinHealth','GetMaxHealth','SetMinHealth','SetActive'}
def inspect(session,stamp):
 pair=json.loads((session/'pair.json').read_text(encoding='utf-8-sig'))
 source=session/'host'/('guest-role-schema-'+stamp+'.tsv')
 assert abs(time.time()-source.stat().st_mtime)<120,'Stale metadata snapshot'
 log=(session.parents[1]/'host/runtime/UE4SS.log').read_text(encoding='utf-8-sig')
 for layout in ['FObjectPropertyBase::PropertyClass = 0x70','UFunction::Func = 0xD8']:
  assert layout in log,'Runtime has not confirmed layout: '+layout
 assert hashlib.sha256(GAME.read_bytes()).hexdigest()==SHA
 rows=[line.split('\t')for line in source.read_text().splitlines()]
 classes={int(x[2],0):x[1]for x in rows if x[0]=='class'}
 k=C.WinDLL('kernel32',use_last_error=True)
 k.OpenProcess.argtypes=[W.DWORD,W.BOOL,W.DWORD];k.OpenProcess.restype=W.HANDLE
 k.ReadProcessMemory.argtypes=[W.HANDLE,C.c_void_p,C.c_void_p,C.c_size_t,C.POINTER(C.c_size_t)];k.ReadProcessMemory.restype=W.BOOL
 k.QueryFullProcessImageNameW.argtypes=[W.HANDLE,W.DWORD,W.LPWSTR,C.POINTER(W.DWORD)];k.QueryFullProcessImageNameW.restype=W.BOOL
 k.CloseHandle.argtypes=[W.HANDLE]
 h=k.OpenProcess(0x10|0x1000,False,pair['host_pid'])
 if not h:raise C.WinError(C.get_last_error())
 def read64(p):
  b=C.create_string_buffer(8);n=C.c_size_t()
  if not k.ReadProcessMemory(h,p,b,8,C.byref(n))or n.value!=8:raise C.WinError(C.get_last_error())
  return struct.unpack('<Q',b.raw)[0]
 try:
  path=C.create_unicode_buffer(32768);n=W.DWORD(len(path))
  assert k.QueryFullProcessImageNameW(h,0,path,C.byref(n))and Path(path.value).resolve()==GAME.resolve()
  result={'pid':pair['host_pid'],'read_only':True,'functions':[],'parameter_types':[],'native_classes':[]}
  for x in rows:
   if x[0]=='function'and x[2]in SELECT:
    ptr=read64(int(x[3],0)+0xd8)
    result['functions'].append({'owner':x[1],'name':x[2],'exec_address':hex(ptr),'exec_rva':hex(ptr-0x140000000)})
   if x[0]=='argument'and x[2]in SELECT and x[4]in ('ObjectProperty','WeakObjectProperty','ClassProperty'):
    cl=read64(int(x[6],0)+0x70)
    result['parameter_types'].append({'owner':x[1],'function':x[2],'parameter':x[3],'class_pointer':hex(cl),'class':classes.get(cl,'unmapped')})
  wanted={'LiveGameObject','LiveAIGameObject','LiveUnit','LiveWingmanUnit','LivePlayerPlane','LiveWingmanManager','LiveSetGameObjectDisplayName','LiveTakeDamageUnitHealth','LiveWingmanHUDLocatorForceDisplay','LiveHUD','LiveHasHealthInterface','LiveWorldDataInterface'}
  for cl,name in classes.items():
   if not name.startswith('Class /Script/Live.')or name.rsplit('.',1)[-1]not in wanted:continue
   cdo=read64(cl+0x110);vt=read64(cdo);flags=read64(cl+0xd4)&0xffffffff
   limit=0xa00 if name.rsplit('.',1)[-1]in {'LiveAIGameObject','LiveUnit','LiveWingmanUnit','LivePlayerPlane','LiveHUD'}else 0x400
   slots=[{'offset':hex(o),'target_rva':hex(read64(vt+o)-0x140000000)}for o in range(0,limit,8)]
   interfaces=[];data=read64(cl+0x1d8);count=read64(cl+0x1e0)&0xffffffff
   assert count<=32
   for i in range(count):
    it=read64(data+16*i);layout=read64(data+16*i+8);offset=layout&0xffffffff;impl=bool((layout>>32)&0xff)
    interfaces.append({'class':classes.get(it,hex(it)),'pointer':hex(it),'offset':hex(offset),'blueprint':impl,'vtable_rva':hex(read64(cdo+offset)-0x140000000)if offset and not impl else None})
   health=None
   if name.rsplit('.',1)[-1]in {'LiveGameObject','LivePlayerPlane','LiveUnit','LiveWingmanUnit'}:
    h_off=0x298 if name.endswith('Unit')else 0x320;h_vt=read64(cdo+h_off)
    health={'offset':hex(h_off),'vtable_rva':hex(h_vt-0x140000000),'slots':[hex(read64(h_vt+i*8)-0x140000000)for i in range(4)]}
   result['native_classes'].append({'name':name,'class':hex(cl),'flags':hex(flags),'abstract':bool(flags&1),'cdo':hex(cdo),'vtable':hex(vt),'vtable_rva':hex(vt-0x140000000),'interfaces':interfaces,'health_interface':health,'bounded_vtable_candidates':slots})
  target=session/'host'/('guest-role-native-'+stamp+'.json')
  target.write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
  print(json.dumps({'path':str(target),'classes':[{k:v for k,v in c.items()if k!='bounded_vtable_candidates'}for c in result['native_classes']]},indent=2))
 finally:k.CloseHandle(h)
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--session',type=Path,required=True);p.add_argument('--stamp',required=True);args=p.parse_args();inspect(args.session,args.stamp)
