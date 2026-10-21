"""Read-only capability snapshot: launcher PID/time/hash, live GUObject identity checks.
No engine function invocation, memory writes or automatic travel.
"""
import argparse,datetime,json,struct,hashlib
from pathlib import Path
import sample_plane_motion as motion

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--session',type=Path,required=True);ap.add_argument('--survey',type=Path,required=True);ap.add_argument('--game',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 session=json.loads((a.session/'session.json').read_text(encoding='utf-8-sig'))
 if session['exit_code']is not None or a.survey.resolve().parent!=a.session.resolve():raise ValueError('Not a live survey session')
 if a.survey.stat().st_size>2000000:raise ValueError('Survey budget')
 motion.GAME=a.game.resolve();r=motion.WindowsReader(session['pid'],datetime.datetime.fromisoformat(session['started']).timestamp())
 def q(p):return struct.unpack('<Q',r.read(p,8))[0]
 def identity(p):
  if not 0x10000<=p<0x800000000000 or p%8:raise ValueError('invalid object')
  head=r.read(p,0x28);index=struct.unpack_from('<i',head,12)[0];flags=struct.unpack_from('<I',head,8)[0]
  array=r.base+0xdc60cd0;count=struct.unpack('<i',r.read(array+0x24,4))[0];chunks=struct.unpack('<i',r.read(array+0x2c,4))[0]
  if flags&0x60000000 or not 0<=index<count<=0x1000000 or not 0<chunks<=0x1000 or index//65536>=chunks:raise ValueError('dead/unregistered object')
  item=q(q(array+0x10)+(index//65536)*8)+(index%65536)*0x18
  if q(item)!=p:raise ValueError('object registry mismatch')
  return head,struct.unpack('<i',r.read(item+0x10,4))[0]
 result={'read_only':True,'pid':session['pid'],'base':hex(r.base),'survey_sha256':hashlib.sha256(a.survey.read_bytes()).hexdigest(),'objects':{},'functions':[],'world':{}}
 try:
  lines=[s.split('\t')for s in a.survey.read_text(encoding='utf-8').splitlines()]
  for row in lines:
   if row[0]=='instance'and row[1]in ('LiveGameInstance','LiveNetworkManager','LiveNetworkP2P','LivePlayerController','GameSession','NetDriver'):
    p=int(row[3],16);h=identity(p);vt=q(p);rv=vt-r.base
    if not 0<rv<0x20000000:raise ValueError('foreign vtable')
    slots=[{'slot':i,'rva':hex(fn-r.base)}for i,fn in enumerate(struct.unpack('<256Q',r.read(vt,2048)))if 0x1000<fn-r.base<0xc000000]
    if identity(p)!=h:raise ValueError('object changed while sampled')
    result['objects'][row[1]]={'pointer':hex(p),'header':h[0].hex(),'serial':h[1],'vtable_rva':hex(rv),'slots':slots}
   if row[0]=='function'and row[2]in ('ClientTravel','OpenLevel','OpenLevelBySoftObjectPtr','ExecuteConsoleCommand','GetUnitName','GetCallsign','GetObjName','KickRoomMemberSuccess'):
    p=int(row[4],16);h=identity(p);fn=q(p+0xd8)
    if identity(p)!=h:raise ValueError('function changed')
    result['functions'].append({'class':row[1],'name':row[2],'pointer':hex(p),'native_rva':hex(fn-r.base),'flags':row[3]})
  pc=int(result['objects']['LivePlayerController']['pointer'],16)
  world_class=next(int(x[2],16)for x in lines if x[0]=='class'and x[1]=='Class /Script/Engine.World')
  p=pc
  for _ in range(6):
   identity(p)
   if q(p+0x10)==world_class:
    result['world']={'pointer':hex(p),'net_driver':hex(q(p+56)),'game_mode':hex(q(p+344)),'game_state':hex(q(p+352)),'game_instance':hex(q(p+472))};break
   p=q(p+0x20)
  driver=result['objects'].get('NetDriver')
  if driver and any(x[0]=='instance'and x[1]=='NetDriver'and x[2].startswith('SteamNetDriver ')for x in lines):
   p=int(driver['pointer'],16);h=identity(p)
   # Verified build InitBase 0x822e140 stores the shared local address at +0x7c0.
   # 0x822e050 branches on passthrough +0x978. These reads invoke no methods.
   addr=q(p+0x7c0);info={'passthrough_byte':r.read(p+0x978,1)[0],'local_address_pointer':hex(addr)}
   if addr>=0x10000 and addr%8==0:
    vt=q(addr)
    if not 0<vt-r.base<0x20000000:raise ValueError('Foreign local address vtable')
    info.update({'header_hex':r.read(addr,32).hex(),'vtable_rva':hex(vt-r.base),'slots':[hex(x-r.base)for x in struct.unpack('<24Q',r.read(vt,192))]})
    if vt-r.base==0xcc9bf10 and q(vt+16*8)-r.base==0x81f0c10:
     # ToString at 0x81f0c10 reads SharedUniqueId +8 -> uint64 +24,
     # and GetPort 0x16f6f60 reads address +24. No calls are made here.
     uid=q(addr+8)
     if uid<0x10000 or uid%8:raise ValueError('Invalid shared unique ID')
     info['steam_id']=str(q(uid+24));info['port']=struct.unpack('<i',r.read(addr+24,4))[0]
   if identity(p)!=h:raise ValueError('Driver changed during address observation')
   result['steam_driver_address_observation']=info
  a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('validated read-only objects',len(result['objects']),'functions',len(result['functions']));print(result['world'])
 finally:r.close()
if __name__=='__main__':main()
