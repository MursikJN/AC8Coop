"""Read-only PE verification of the hangar-to-flight lifecycle GhidraMCP evidence."""
import hashlib
import json
import struct
from datetime import datetime, timezone
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/hangar-flight-contract-ghidra-20261022'
EXPECTED = '51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
binary = ROOT / '.tools/offline-research/targets/ac8-build25201480/AceCombat8.exe'
original = Path('D:/Programs/Steam/steamapps/common/ACE COMBAT 8/Game/Binaries/Win64/AceCombat8.exe')
identities = []
for path in (binary, original):
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    assert digest == EXPECTED, str(path)
    identities.append({'path': str(path), 'sha256': digest, 'size': path.stat().st_size})
m = binary.read_bytes()
pe = struct.unpack_from('<I', m, 0x3c)[0]
opt = pe + 24
base = struct.unpack_from('<Q', m, opt + 24)[0]
assert base == 0x140000000
sh = opt + struct.unpack_from('<H', m, pe + 20)[0]
sections = [struct.unpack_from('<IIII', m, sh + 40*i + 8)
            for i in range(struct.unpack_from('<H', m, pe + 6)[0])]

def off(rv):
    for _, r, size, offset in sections:
        if r <= rv < r + size:
            return offset + rv - r
    raise ValueError(hex(rv))

checks = []
records = []
for path in sorted((OUT / 'responses').glob('*.json')):
    record = json.loads(path.read_text(encoding='utf-8'))
    records.append(record)
    if record['tool'] != 'read_memory' or record['response'].get('isError'):
        continue
    data = record['response']['structuredContent']
    va = int(data['address'], 16)
    assert not data['gaps'], path.name
    content = bytes.fromhex(data['hex'])
    offset = off(va - base)
    assert m[offset:offset + len(content)] == content, path.name
    checks.append({'response': path.name, 'va': hex(va), 'file_offset': hex(offset),
                   'length': len(content), 'match': True})

er, es = struct.unpack_from('<II', m, opt + 112 + 24)
ranges = sorted(struct.unpack_from('<III', m, p)
                for p in range(off(er), off(er) + es - 11, 12))

def primary(row):
    for _ in range(20):
        p = off(row[2])
        flags, _, count, _ = struct.unpack_from('4B', m, p)
        if flags >> 3 & 4:
            row = struct.unpack_from('<III', m, p + 4 + ((count + 1) & ~1)*2)
        else:
            return row[0]
    raise ValueError('unwind chain')

targets = {0x74a13e0, 0x74a1a90, 0x74b5310, 0x74a4b10, 0x74a4480,
           0x1c3a3de0, 0x78df820, 0x78df3d0, 0x7d24a40, 0x756ad30,
           0x81974c0, 0x71ca650, 0x71cc490, 0x74b53f0, 0x74a1990}
cs = Cs(CS_ARCH_X86, CS_MODE_64)
paths = []
for row in ranges:
    begin, end, _ = row
    if not (0x71c0000 <= begin < 0x71e0000 or 0x74a0000 <= begin < 0x74c0000
            or 0x756a000 <= begin < 0x756b000 or 0x78df000 <= begin < 0x78e0000
            or 0x7d24000 <= begin < 0x7d25000 or 0x8197000 <= begin < 0x8198000
            or 0x1c3a3d00 <= begin < 0x1c3a4000):
        continue
    pr = primary(row)
    if pr not in targets:
        continue
    for ins in cs.disasm(m[off(begin):off(begin) + end - begin], base + begin):
        paths.append({'function_rva': hex(pr), 'fragment_rva': hex(begin),
                      'va': hex(ins.address), 'bytes': ins.bytes.hex(),
                      'instruction': ins.mnemonic + ' ' + ins.op_str})
assert targets <= {int(x['function_rva'], 16) for x in paths}
anchors = {
    0x74a19ac: ('e82ffaffff', 'detach room callbacks before full selector reset'),
    0x74a19b8: ('e833f2ffff', 'full selector reset wrapper call'),
    0x74a19e8: ('e883250000', 'recreate selectors on reset boolean branch'),
    0x74a4ccf: ('e83c060100', 'unregister selector network object'),
    0x74a4cdd: ('4c89a388010000', 'clear selector network pointer after unregister'),
    0x74b535e: ('4c8b4f28', 'load unregister key'),
    0x74b53d6: ('e8c52b35fb', 'erase registry entry by key'),
    0x7d24a8f: ('e87c0879ff', 'unregister plane network object'),
    0x7d24a9a: ('ff90700c0000', 'invoke plane network pointer release slot'),
    0x1c3a3e70: ('e89b0c10eb', 'full selector reset calls network detach'),
    0x1c3a3e82: ('e8b97e42e5', 'full selector reset clears profile map branch'),
    0x78dfc33: ('4c89af58090000', 'full context cleanup clears member manager pointer'),
    0x78dfd74: ('4c89af10090000', 'full context cleanup clears STRIX system pointer'),
    0x71ca92c: ('41888ed80e0000', 'assign local plane role'),
    0x71cc77a: ('c686d80e000002', 'assign remote plane role 2'),
}
anchor_checks = []
by_va = {int(x['va'], 16): x for x in paths}
for rv, (expected, meaning) in anchors.items():
    item = by_va[base + rv]
    assert item['bytes'] == expected, (hex(rv), item)
    anchor_checks.append(dict(item, meaning=meaning, match=True))
tables = []
for rv, expected in [(0xcc02938, 0x7c43cf0), (0xc88c238, 0x74bb4c0),
                     (0xcc02900, 0x6dc5800), (0xcc02908, 0x6dc5810)]:
    actual = struct.unpack_from('<Q', m, off(rv))[0]
    assert actual == base + expected
    tables.append({'slot_va': hex(base + rv), 'target_rva': hex(expected), 'match': True})
errors = [r['id'] for r in records if r['response'].get('isError')]
assert set(errors) == {'003-selector-reset', '023-player-virtual-detach'}
leaf_checks = []
for rv in [0x74a0bf0, 0x7c43cf0, 0x6dc5800, 0x6dc5810]:
    decoded = []
    for ins in cs.disasm(m[off(rv):off(rv)+16], base+rv):
        decoded.append({'va':hex(ins.address),'bytes':ins.bytes.hex(),
                        'instruction':ins.mnemonic+' '+ins.op_str})
        if ins.mnemonic in ('ret','jmp'):
            break
    leaf_checks.append({'rva':hex(rv),'instructions':decoded})
assert m[off(0x7c43cf0):off(0x7c43cf0)+12].hex() == '48c781d00e000000000000c3'
assert m[off(0x74a0bf0):off(0x74a0bf0)+5].hex() == 'e9eb31f014'
result = {'utc': datetime.now(timezone.utc).isoformat(), 'image_base': hex(base),
          'artifacts': identities, 'mcp_byte_checks': checks,
          'verified_table_slots': tables, 'decoded_instructions': paths,
          'asserted_instruction_anchors': anchor_checks, 'decoded_leaf_paths': leaf_checks,
          'mcp_responses': len(records), 'mcp_errors': errors, 'game_executed': False,
          'limitations': ['Static addresses are not runtime addresses or validated call ABI.',
                         'Decoded unwind fragments do not establish runtime execution.',
                         'No native call ABI or automatic campaign transition is claimed.']}
(OUT / 'byte-and-instruction-verification.json').write_text(
    json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'mcp_responses': len(records), 'mcp_byte_checks': len(checks),
                  'decoded_instructions': len(paths), 'table_slots': len(tables),
                  'hashes_match': True, 'errors': errors}, indent=2))
