"""Offline candidate index; never loads target code. Validate candidates with Ghidra."""
import argparse, bisect, hashlib, json, mmap, re, struct
from pathlib import Path

SHA = '51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--targets', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    targets = json.loads(args.targets.read_text(encoding='utf-8'))
    image = Path('.tools/offline-research/targets/ac8-build25201480/AceCombat8.exe')
    with image.open('rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        assert hashlib.sha256(m).hexdigest() == SHA
        pe = struct.unpack_from('<I', m, 0x3c)[0]
        opt = pe + 24
        base = struct.unpack_from('<Q', m, opt + 24)[0]
        sh = opt + struct.unpack_from('<H', m, pe + 20)[0]
        sections = []
        for i in range(struct.unpack_from('<H', m, pe + 6)[0]):
            p = sh + 40*i
            vs, rv, sz, off = struct.unpack_from('<IIII', m, p+8)
            flags = struct.unpack_from('<I', m, p+36)[0]
            sections.append((rv, sz, off, flags))
        def off(rv):
            for r,s,o,_ in sections:
                if r <= rv < r+s: return o+rv-r
            raise ValueError(hex(rv))
        er, es = struct.unpack_from('<II', m, opt+112+24)
        ranges = sorted(struct.unpack_from('<III', m, p) for p in range(off(er), off(er)+es-11, 12))
        starts = [r[0] for r in ranges]
        def owner(rv):
            i = bisect.bisect_right(starts, rv)-1
            if i < 0 or rv >= ranges[i][1]: return None
            row = ranges[i]; original = row
            for _ in range(20):
                p = off(row[2]); flags,_,count,_ = struct.unpack_from('4B',m,p)
                if flags >> 3 & 4: row=struct.unpack_from('<III',m,p+4+((count+1)&~1)*2)
                else: return {'primary_rva':hex(row[0]), 'fragment_rva':hex(original[0]), 'fragment_end':hex(original[1])}
            raise ValueError('unwind loop')
        calltargets = {int(v,16):k for k,v in targets.get('calls',{}).items()}
        riptargets = {int(v,16):k for k,v in targets.get('rip',{}).items()}
        calls=[]; refs=[]
        for rv,sz,o,flags in sections:
            if not flags & 0x20000000: continue
            for q in re.finditer(rb'(?=([\xe8\xe9]....))', m[o:o+sz], re.S):
                source=rv+q.start(); target=source+5+struct.unpack_from('<i',q.group(1),1)[0]
                if target in calltargets: calls.append({'target':calltargets[target],'source_rva':hex(source),'bytes':q.group(1).hex(),'owner':owner(source),'candidate_only':True})
            for q in re.finditer(rb'[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]....',m[o:o+sz],re.S):
                source=rv+q.start(); target=source+7+struct.unpack_from('<i',q.group(),3)[0]
                if target in riptargets: refs.append({'target':riptargets[target],'source_rva':hex(source),'bytes':q.group().hex(),'owner':owner(source),'candidate_only':True})
        result={'sha256':SHA,'image_base':hex(base),'targets':targets,'call_candidates':calls,'rip_candidates':refs,'limitations':'Raw byte candidates; not instruction-boundary proof. Incomplete metadata xrefs are not absence proof.'}
        if 'field_region' in targets:
            from capstone import Cs, CS_ARCH_X86, CS_MODE_64, CS_OP_MEM
            cs = Cs(CS_ARCH_X86, CS_MODE_64); cs.detail = True
            lo, hi = [int(v,16) for v in targets['field_region']]
            fields = {int(v,16) for v in targets['fields']}
            hits = []
            for b,e,u in ranges:
                if not lo <= b < hi: continue
                for ins in cs.disasm(bytes(m[off(b):off(b)+e-b]), base+b):
                    if any(op.type==CS_OP_MEM and op.mem.disp in fields for op in ins.operands):
                        hits.append({'va':hex(ins.address),'bytes':ins.bytes.hex(),'instruction':ins.mnemonic+' '+ins.op_str,'owner':owner(ins.address-base)})
            result['field_references'] = hits
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({'calls':len(calls),'rip':len(refs),'fields':len(result.get('field_references',[]))}))

if __name__ == '__main__': main()
