"""Verify fixed-RVA guards using a read-only offline image, never load the image."""
from pathlib import Path
import argparse, hashlib, json, mmap, re, struct
ROOT=Path(__file__).resolve().parents[1]
EXPECTED='51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
def verify(path):
 with path.open('rb')as file,mmap.mmap(file.fileno(),0,access=mmap.ACCESS_READ)as data:
  assert hashlib.sha256(data).hexdigest()==EXPECTED,'Unsupported image'
  pe=struct.unpack_from('<I',data,0x3c)[0];opt=pe+24;assert struct.unpack_from('<Q',data,opt+24)[0]==0x140000000
  sh=opt+struct.unpack_from('<H',data,pe+20)[0];sections=[]
  for i in range(struct.unpack_from('<H',data,pe+6)[0]):
   at=sh+40*i;vs,rv,sz,off=struct.unpack_from('<IIII',data,at+8);flags=struct.unpack_from('<I',data,at+36)[0];sections.append((rv,sz,off,flags))
  def read(rva):
   for rv,sz,off,flags in sections:
    if rv<=rva and rva+16<=rv+sz:return data[off+rva-rv:off+rva-rv+16]
   raise ValueError('RVA outside file')
  header=(ROOT/'native/adapter_bootstrap_contract.h').read_text()
  pause=re.search(r'pause_update_fingerprint\[\]="([0-9a-f]+)"',header)[1]
  pairs=[(0x79163f0,pause)]+[(int(r,16),s)for r,s in re.findall(r'(0x[0-9a-f]+),"([0-9a-f]+)"',(ROOT/'native/menu_route_contract.h').read_text())]
  for rva,name in [(0x7916407,'pause_reason_shift_fingerprint'),(0x7916417,'pause_override_branch_fingerprint')]:
   pairs.append((rva,re.search(name+r'\[\]="([0-9a-f]+)"',header)[1]))
  checks=[]
  for rva,fingerprint in pairs:
   assert len(fingerprint)==32,(hex(rva),'incorrect fingerprint length')
   actual=read(rva);assert actual.hex()==fingerprint,(hex(rva),fingerprint,actual.hex())
   checks.append(dict(rva=hex(rva),bytes_hex=fingerprint))
  needle=bytes.fromhex(pause);count=0
  for rv,sz,off,flags in sections:
   if not flags&0x20000000:continue
   cursor=off
   while True:
    found=data.find(needle,cursor,off+sz)
    if found<0:break
    count+=1;cursor=found+1
  assert count==1,'Pause guard prefix is not unique in executable sections'
  return dict(format='ac8-adapter-offline-fingerprints-v1',image_sha256=EXPECTED,image_base='0x140000000',guards=checks,pause_prefix_executable_matches=count,game_launched=False,originals_written=False)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--image',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();r=verify(a.image);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(r,indent=2)+'\n');print('PASS:',len(r['guards']),'fixed-RVA guards and unique pause prefix; offline reads only.')
