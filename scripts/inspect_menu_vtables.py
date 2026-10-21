"""Read-only snapshots of current menu object vtables; no target writes or calls."""
import argparse,datetime,hashlib,json,struct,time
from pathlib import Path
import sample_plane_motion as motion

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--session',type=Path,required=True);ap.add_argument('--ticket',type=Path,required=True);ap.add_argument('--game',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--roots-only',action='store_true');a=ap.parse_args()
 session=json.loads((a.session/'session.json').read_text(encoding='utf-8-sig'))
 if session['exit_code'] is not None or a.ticket.resolve().parent!=a.session.resolve() or time.time()-a.ticket.stat().st_mtime>120:raise ValueError('Not a fresh live-session ticket')
 motion.GAME=a.game.resolve();reader=motion.WindowsReader(session['pid'],datetime.datetime.fromisoformat(session['started']).timestamp())
 try:
  found={};lines=a.ticket.read_text(encoding='utf-8').splitlines()
  roots={x.split('\t')[2]for x in lines if x.startswith('instance\tLiveMenuBase\t')}
  for line in lines:
   row=line.split('\t')
   if row[0]!='address' or len(row)!=3 or (row[1]not in roots and not any(s in row[1]for s in ('Menu','NUI','Hangar','MapChange','StateManager'))):continue
   if a.roots_only and row[1]not in roots and'Default__'not in row[1]:continue
   if len(found)>=96:raise ValueError('Object budget exceeded')
   address=int(row[2],16);head=reader.read(address,0x28);vtable=struct.unpack_from('<Q',head)[0];rv=vtable-reader.base
   if not 0<=rv<0x20000000:raise ValueError('Object vtable outside game')
   raw=reader.read(vtable,2048)+reader.read(vtable+2048,512)
   slots=[]
   for index,pointer in enumerate(struct.unpack('<320Q',raw)):
    rva=pointer-reader.base
    if 0<=rva<0xc000000:
     slots.append({'index':index,'rva':hex(rva),'first16':reader.read(pointer,16).hex()})
   if reader.read(address,0x28)!=head:raise ValueError('Object changed while sampled')
   record={'address':hex(address),'header':head.hex(),'vtable_rva':hex(rv),'slots':slots}
   if row[1]in roots and 0xc700000<=rv<=0xc900000:
    data=reader.read(address,0x720)
    selected=struct.unpack_from('<h',data,0x688)[0];array,count,capacity=struct.unpack_from('<Qii',data,0x690)
    if 0<count<=128 and count<=capacity<=256:
     entries=[]
     for index in range(count):
      command=reader.read(array+index*0x1b8,0x1b8);text_addr,text_count,text_cap=struct.unpack_from('<Qii',command,0x130)
      caption=''
      if 0<text_count<=128 and text_count<=text_cap<=512:
       caption=reader.read(text_addr,text_count*2).decode('utf-16le').rstrip('\0')
      tag_addr,tag_count,tag_cap=struct.unpack_from('<Qii',command,0xf8);tag=''
      if 0<tag_count<=128 and tag_count<=tag_cap<=512:tag=reader.read(tag_addr,tag_count*2).decode('utf-16le').rstrip('\0')
      entries.append({'index':index,'tag':tag,'caption':caption,'id108':struct.unpack_from('<i',command,0x108)[0],'id158':struct.unpack_from('<i',command,0x158)[0],'weapon160':command[0x160],'bytes':command.hex()})
     record['commands']={'selected':selected,'count':count,'entries':entries}
   found[row[1]]=record
  a.output.write_text(json.dumps({'pid':session['pid'],'base':hex(reader.base),'ticket':a.ticket.name,'ticket_sha256':hashlib.sha256(a.ticket.read_bytes()).hexdigest(),'objects':found},indent=2)+'\n',encoding='utf-8')
  print('Read-only menu vtables:',len(found))
 finally:reader.close()
if __name__=='__main__':main()
