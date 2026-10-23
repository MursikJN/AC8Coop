"""Read-only PE/Ghidra cross-check for the R31 native owner candidate.

Does not load/execute the game or call a native game function.
"""
from pathlib import Path
import hashlib
import json
import re
import struct
from datetime import datetime, timezone
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

ROOT=Path(__file__).resolve().parents[1]
RAW=ROOT/'.tools/offline-research/owner-native-r31/responses'
OUT=ROOT/'evidence/owner-native-r31-20261022'
EXPECTED='51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
TARGET=ROOT/'.tools/offline-research/targets/ac8-build25201480/AceCombat8.exe'
ORIGINAL=Path('D:/Programs/Steam/steamapps/common/ACE COMBAT 8/Game/Binaries/Win64/AceCombat8.exe')

def main():
 global OUT
 import argparse
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-directory',type=Path,default=OUT)
 OUT=parser.parse_args().output_directory
 identities=[]
 for path in (TARGET,ORIGINAL):
  with path.open('rb')as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
  assert digest==EXPECTED,str(path)
  identities.append(dict(path=str(path),size=path.stat().st_size,sha256=digest))
 m=TARGET.read_bytes();pe=struct.unpack_from('<I',m,60)[0];opt=pe+24
 base=struct.unpack_from('<Q',m,opt+24)[0];assert base==0x140000000
 sh=opt+struct.unpack_from('<H',m,pe+20)[0]
 sections=[struct.unpack_from('<IIII',m,sh+40*i+8)for i in range(struct.unpack_from('<H',m,pe+6)[0])]
 def off(rva):
  for _,rv,size,start in sections:
   if rv<=rva<rv+size:return start+rva-rv
  raise ValueError(hex(rva))
 def read(va,n):return m[off(va-base):off(va-base)+n]
 records=[];ranges=[];errors=[]
 for p in sorted(RAW.glob('*.json')):
  r=json.loads(p.read_text());records.append(r);result=r['result'];d=result.get('structuredContent')
  if result.get('isError')or not d:
   errors.append(dict(response=p.name,tool=r['tool']));continue
  if r['tool']=='get_program_info':assert d['sha256']==EXPECTED and int(d['image_base'],16)==base
  if r['tool']=='read_memory':
   assert not d['gaps'],p.name
   expected=bytes.fromhex(d['hex']);va=int(d['address'],16);assert read(va,len(expected))==expected,p.name
   ranges.append(dict(response=p.name,va=hex(va),bytes=len(expected),match=True))
 source=(ROOT/'native/guest_owner_native.inl').read_text()
 anchors=re.findall(r'fingerprint\(0x([0-9a-f]+),"([0-9a-f]{32})"',source)
 anchors+=re.findall(r'\{0x([0-9a-f]+),"([0-9a-f]{32})"\}',source)
 checked=[]
 for rva,data in anchors:
  expected=bytes.fromhex(data);va=base+int(rva,16);assert read(va,16)==expected,(rva,data)
  checked.append(dict(rva=hex(int(rva,16)),bytes=data,match=True))
 cs=Cs(CS_ARCH_X86,CS_MODE_64)
 getter=[dict(va=hex(i.address),bytes=i.bytes.hex(),instruction=i.mnemonic+' '+i.op_str)for i in cs.disasm(read(base+0x73610b0,0x108),base+0x73610b0)]
 assert any(x['instruction']=='mov rax, rbx'for x in getter)
 caller=list(cs.disasm(read(base+0x7d4af60,480),base+0x7d4af60))
 calls=[i for i,x in enumerate(caller)if x.mnemonic=='call'and x.op_str=='0x1473610b0']
 assert len(calls)==1
 i=calls[0];block=caller[max(0,i-6):i+5]
 assert any(x.mnemonic=='mov'and x.op_str=='qword ptr [rdi + 0x3ab0], rax'for x in block)
 slots={hex(slot):hex(struct.unpack('<Q',read(base+0xcc01cc8+slot,8))[0])for slot in (0x390,0x398,0x618,0xc70)}
 assert slots=={'0x390':'0x147d23f00','0x398':'0x147d24a40','0x618':'0x144836910','0xc70':'0x147c43cf0'}
 assert read(base+0x7c43cf0,12).hex()=='48c781d00e000000000000c3'
 OUT.mkdir(parents=True,exist_ok=True)
 report=dict(created_utc=datetime.now(timezone.utc).isoformat(),identities=identities,image_base=hex(base),
  native_executed=False,game_launched=False,originals_written=False,ghidra_responses=len(records),negative_results=errors,
  matched_memory_ranges=ranges,matched_entry_anchors=checked,player_vtable_slots=slots,
  getter_disassembly=getter,getter_caller=[dict(va=hex(x.address),bytes=x.bytes.hex(),instruction=x.mnemonic+' '+x.op_str)for x in block],
  scope='Static bytes/ABI evidence only; generic guest-world initialization and native retirement require a game test.')
 p=OUT/'byte-verification.json';p.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(dict(memory_ranges=len(ranges),entry_anchors=len(checked),responses=len(records),negative_results=len(errors),report_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),game_launched=False)))

if __name__=='__main__':main()
