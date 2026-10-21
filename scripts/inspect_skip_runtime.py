"""Read-only, bounded skip-strategy vtables from a fresh game-thread ticket."""
import argparse,datetime,json,struct,time
from pathlib import Path
import sample_plane_motion as motion

def main():
 p=argparse.ArgumentParser();p.add_argument('--ticket',type=Path,required=True);p.add_argument('--pid',type=int,required=True);p.add_argument('--started',required=True);p.add_argument('--game',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--menu',action='store_true');a=p.parse_args()
 if not 0<=time.time()-a.ticket.stat().st_mtime<120:raise ValueError('Stale ticket')
 motion.GAME=a.game.resolve();r=motion.WindowsReader(a.pid,datetime.datetime.fromisoformat(a.started).timestamp())
 try:
  result=dict(pid=a.pid,base=hex(r.base),read_only=True,objects=[])
  for line in a.ticket.read_text(encoding='utf-8').splitlines():
   cols=line.split('\t')
   prefixes=('LiveMenuPauseWidget ','LiveMenuPauseBootWidget ','LiveMenuPauseDerivationWidget ','LiveMenuBase ','LivePauseManager ')if a.menu else('LiveSkipOperationManager ','LiveSkipOperationPressHoldSkipStrategy ','LiveSkipOperationPressHoldSkipUnGuideStrategy ')
   if cols[0]!='object'or not cols[1].startswith(prefixes):continue
   address=int(cols[2],16);head=r.read(address,40);table=struct.unpack_from('<Q',head)[0]
   assert 0<=table-r.base<0x20000000
   size=320 if a.menu else 96;raw_table=b''.join(r.read(table+at,min(2048,size*8-at))for at in range(0,size*8,2048));slots=struct.unpack('<'+str(size)+'Q',raw_table)
   result['objects'].append(dict(name=cols[1],address=cols[2],header=head.hex(),vtable=hex(table-r.base),raw=r.read(address,256).hex(),slots=[dict(index=i,rva=hex(v-r.base))for i,v in enumerate(slots)if 0<=v-r.base<0xc000000]))
   assert r.read(address,40)==head
  a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
  for o in result['objects']:print(o['name'].split()[0],o['vtable'],o['slots'][-24:])
 finally:r.close()
if __name__=='__main__':main()
