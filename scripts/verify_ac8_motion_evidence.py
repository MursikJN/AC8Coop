"""Cross-check saved GhidraMCP reads against the pinned PE and decode selected paths."""
import bisect, hashlib, json, struct
from datetime import datetime, timezone
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64, CS_OP_IMM, CS_OP_MEM

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/aircraft-motion-ghidra-20261022'
EXPECTED = '51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
binary = ROOT / '.tools/offline-research/targets/ac8-build25201480/AceCombat8.exe'
original = Path('D:/Programs/Steam/steamapps/common/ACE COMBAT 8/Game/Binaries/Win64/AceCombat8.exe')
identities = []
for path in [binary, original]:
    with path.open('rb') as f: digest = hashlib.file_digest(f, 'sha256').hexdigest()
    assert digest == EXPECTED, str(path)
    identities.append({'path':str(path),'sha256':digest,'size':path.stat().st_size})
m = binary.read_bytes()
pe = struct.unpack_from('<I', m, 0x3c)[0]; opt = pe+24
base = struct.unpack_from('<Q', m, opt+24)[0]
assert base == 0x140000000
sh = opt+struct.unpack_from('<H',m,pe+20)[0]
sections = [struct.unpack_from('<IIII',m,sh+40*i+8) for i in range(struct.unpack_from('<H',m,pe+6)[0])]
def off(rv):
    for vs,r,s,o in sections:
        if r <= rv < r+s: return o+rv-r
    raise ValueError(hex(rv))
checks=[]; records=[]
for p in sorted((OUT/'responses').glob('*.json')):
    r=json.loads(p.read_text(encoding='utf-8'));records.append(r)
    if r['tool']!='read_memory' or r['response'].get('isError'): continue
    d=r['response']['structuredContent']; va=int(d['address'],16)
    assert not d['gaps']
    b=bytes.fromhex(d['hex']); o=off(va-base)
    assert m[o:o+len(b)]==b,p.name
    checks.append({'response':p.name,'va':hex(va),'file_offset':hex(o),'length':len(b),'match':True})
er,es=struct.unpack_from('<II',m,opt+112+24)
ranges=sorted(struct.unpack_from('<III',m,p) for p in range(off(er),off(er)+es-11,12))
starts=[r[0] for r in ranges]
def primary(row):
    for _ in range(20):
        p=off(row[2]); flags,_,count,_=struct.unpack_from('4B',m,p)
        if flags>>3&4:row=struct.unpack_from('<III',m,p+4+((count+1)&~1)*2)
        else:return row[0]
    raise ValueError('unwind chain')
targets={0x71cc490,0x74bb4c0,0x74b5770,0x74bda10,0x74d8380,0x74d8c00,0x7d639c0,0x7d6ee70,0x7d6f0c0,0x74a08b0,0x78e48e0,0x71cb3e0}
key_calls={base+x for x in [0x4354890,0x74d8380,0x74b7770,0x74d8c00,0x7d6f0c0,0x7d6ee70,0x4d33880,0x71ca650,0x71cb3e0,0x71cd2d0,0x71cc490]}
cs=Cs(CS_ARCH_X86,CS_MODE_64);cs.detail=True
paths=[]
for row in ranges:
    b,e,u=row
    # Restrict before resolving unwind chains across the large PE.
    if not (0x71c0000 <= b < 0x71e0000 or 0x74a0000 <= b < 0x74e0000 or 0x78e0000 <= b < 0x78f0000 or 0x7d60000 <= b < 0x7d80000):continue
    pr=primary(row)
    if pr not in targets:continue
    for ins in cs.disasm(m[off(b):off(b)+e-b],base+b):
        direct=ins.mnemonic in ('call','jmp') and ins.operands and ins.operands[0].type==CS_OP_IMM and ins.operands[0].imm in key_calls
        field=any(op.type==CS_OP_MEM and op.mem.disp in (0xed8,0xc38,0xc40,0xc60,0x98,0x2c,0x30,0x34) for op in ins.operands)
        if direct or field:
            paths.append({'function_rva':hex(pr),'va':hex(ins.address),'bytes':ins.bytes.hex(),'instruction':ins.mnemonic+' '+ins.op_str})
gates=[]
for rv in [0x6dc5800,0x6dc5810,0x6dc5820,0x6dc5830]:
    decoded=[]
    for ins in cs.disasm(m[off(rv):off(rv)+16],base+rv):
        decoded.append({'va':hex(ins.address),'bytes':ins.bytes.hex(),'instruction':ins.mnemonic+' '+ins.op_str})
        if ins.mnemonic=='ret':break
    gates.append({'rva':hex(rv),'instructions':decoded})
constants={
    'clock_ticks_per_second':struct.unpack_from('<d',m,off(0xd2aa9f8))[0],
    'position_scale':struct.unpack_from('<f',m,off(0xdc4c03c))[0],
    'orientation_blend_coefficient':struct.unpack_from('<f',m,off(0xd2aa708))[0],
    'smoothing_distance_squared_threshold':struct.unpack_from('<d',m,off(0xd2aabc8))[0],
}
result={'utc':datetime.now(timezone.utc).isoformat(),'image_base':hex(base),'artifacts':identities,'mcp_byte_checks':checks,'leaf_role_gates':gates,'selected_instruction_paths':paths,'constants':constants,'mcp_responses':len(records),'mcp_errors':[r['id'] for r in records if r['response'].get('isError')], 'game_executed':False,'limitations':['All addresses are static VA/RVA, not ASLR runtime addresses.','Field offsets are observed in this build, not a complete ABI or wire format.','Instruction verification uses PE unwind fragments; empty MCP xrefs/disassembly are metadata limitations.']}
(OUT/'byte-and-instruction-verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'mcp_responses':len(records),'mcp_byte_checks':len(checks),'selected_instructions':len(paths),'constants':constants,'errors':result['mcp_errors'],'hashes_match':True},indent=2))
