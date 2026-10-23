"""Read-only PE cross-check of the R31 object-readiness additions; never executes EXE."""
from pathlib import Path
import hashlib
import json
import struct

ROOT=Path(__file__).resolve().parents[1]
SHA='51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'


def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()


def main():
 copy=ROOT/'.tools/offline-research/targets/ac8-build25201480/AceCombat8.exe'
 original=Path('D:/Programs/Steam/steamapps/common/ACE COMBAT 8/Game/Binaries/Win64/AceCombat8.exe')
 assert digest(copy)==SHA and digest(original)==SHA
 data=copy.read_bytes();pe=struct.unpack_from('<I',data,60)[0];opt=pe+24
 base=struct.unpack_from('<Q',data,opt+24)[0];assert base==0x140000000
 start=opt+struct.unpack_from('<H',data,pe+20)[0]
 sections=[struct.unpack_from('<IIII',data,start+40*i+8)for i in range(struct.unpack_from('<H',data,pe+6)[0])]
 def read(va,size):
  rva=va-base
  for _,r,n,o in sections:
   if r<=rva and rva+size<=r+n:return data[o+rva-r:o+rva-r+size]
  raise ValueError(hex(va))
 raw=ROOT/'.tools/offline-research/r31-object-readiness-20261022'
 records=[]
 for p in sorted(raw.glob('*.json')):
  record=json.loads(p.read_text(encoding='utf-8'));r=record['result']['structuredContent']
  if record['tool'].endswith('get_program_info'):assert r['sha256']==SHA
  if record['tool'].endswith('read_memory'):
   assert not r['gaps'];b=bytes.fromhex(r['hex']);assert read(int(r['address'],16),len(b))==b
  records.append({'path':p.relative_to(ROOT).as_posix(),'sha256':digest(p),'tool':record['tool'],'args':record['args']})
 assert len(records)==3
 anchors={
  0x147d30fa0:('test mapper+28 before initialization','4883792800'),
  0x147d30fa5:('retain address mapper+28 in r14','4c8d7128'),
  0x147d30fb5:('stack low byte initialized marker 1','c640e801'),
  0x147d30fd9:('load marker qword from same stack slot','f20f1040e8'),
  0x147d30fde:('store marker to mapper+58','f20f114158'),
  0x147d3113d:('address mapper+30 for shared ownership assignment','498d4e08'),
  0x147d31146:('publish spatial allocation in mapper+28','498906'),
  0x147d3114e:('assign shared ownership control','e8cd74a1f9'),
 }
 for va,(_,hexbytes)in anchors.items():assert read(va,len(bytes.fromhex(hexbytes)))==bytes.fromhex(hexbytes),hex(va)
 call=0x147d3114e;assert call+5+struct.unpack('<i',read(call+1,4))[0]==0x141748620
 previous=ROOT/'evidence/guest-world-r31-20261022/manifest.json'
 report={'format':'ac8-r31-object-readiness-evidence-v1','binary_sha256':SHA,'image_base':hex(base),
         'original_unchanged':True,'mcp_memory_ranges_matched':1,'mcp_memory_bytes_matched':1024,
         'instructions':{hex(va):{'meaning':name,'bytes':h}for va,(name,h)in anchors.items()},
         'raw':records,'previous_world_evidence_sha256':digest(previous),
         'RG-02':'initializer builds a spatial index; it does not store a direct CombatZone context pointer',
         'readiness':'mapper+28 and +30 nonnull, byte +58 equal to 1; stable world/class/outer identities',
         'game_executed':False,'native_calls_executed':False,'runtime_verified':False}
 out=ROOT/'evidence/r31-object-readiness-20261022/byte-verification.json'
 out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('PASS: pinned EXE hashes, 1024 Ghidra bytes, 8 instruction anchors; no game execution')


if __name__=='__main__':main()
