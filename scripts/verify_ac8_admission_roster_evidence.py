"""Read-only PE verification of the admission, ordering and roster GhidraMCP evidence."""
import hashlib
import json
import struct
from datetime import datetime, timezone
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/admission-roster-ghidra-20261022'
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

targets = {0x71cb3e0, 0x74a5ae0, 0x74a5cf0, 0x74bda10, 0x74b7770,
           0x74a35e0, 0x74a3f70, 0x74a33b0, 0x74a1990, 0x74a1a00,
           0x74a0d40, 0x74a0a00, 0x74c5b00, 0x74c5e00, 0x74c1870,
           0x74c2180, 0xa4b3920, 0x81482b0, 0x817fd30, 0x81471a0}
cs = Cs(CS_ARCH_X86, CS_MODE_64)
paths = []
for row in ranges:
    begin, end, _ = row
    if not (0x71c0000 <= begin < 0x71e0000 or 0x74a0000 <= begin < 0x74d0000
            or 0x8140000 <= begin < 0x8180000 or 0xa4b0000 <= begin < 0xa4c0000):
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
    0x74a3684: ('83782cff', 'bind only previously unassigned selector member ID'),
    0x74a36d1: ('4489602c', 'write selector member ID'),
    0x74a3725: ('48b80000000000000002', 'selector category 2 key prefix'),
    0x74a3784: ('48896928', 'write selector network key'),
    0x74a37da: ('ff90b8020000', 'invoke selector network lifecycle slot after key write'),
    0x74a42db: ('894330', 'write selector slot index'),
    0x74a5ca3: ('44397030', 'match requested slot index'),
    0x74a5cc3: ('8b402c', 'read selector member ID'),
    0x71cb519: ('418bbc24d8030000', 'campaign reads configured slot count'),
    0x71cb544: ('e8871d0000', 'campaign shared remote spawn call'),
    0x74bdb39: ('e8329cffff', 'call movement consistency check'),
    0x74bdb3e: ('488b4508', 'overwrite return register by loading incoming timestamp'),
    0x74bdb4d: ('48894308', 'copy timestamp into single stored snapshot'),
    0x74bdb73: ('89431c', 'copy sender metadata without an admission comparison here'),
    0x74b7923: ('482b4808', 'timestamp delta used in consistency calculation'),
    0x74c5b61: ('8983d8030000', 'write configured slot count'),
}
anchor_checks = []
by_va = {int(x['va'], 16): x for x in paths}
for rv, (expected, meaning) in anchors.items():
    item = by_va[base + rv]
    assert item['bytes'] == expected, (hex(rv), item)
    anchor_checks.append(dict(item, meaning=meaning, match=True))
tables = []
for rv, expected in [(0xcc86720, 0x817fd30)]:
    actual = struct.unpack_from('<Q', m, off(rv))[0]
    assert actual == base + expected
    tables.append({'slot_va': hex(base + rv), 'target_rva': hex(expected), 'match': True})
errors = [r['id'] for r in records if r['response'].get('isError')]
assert set(errors) == {'003-state-buffer', '053-selector-constructor', '056-selector-real-constructor'}
result = {'utc': datetime.now(timezone.utc).isoformat(), 'image_base': hex(base),
          'artifacts': identities, 'mcp_byte_checks': checks,
          'verified_table_slots': tables, 'decoded_instructions': paths,
          'asserted_instruction_anchors': anchor_checks,
          'mcp_responses': len(records), 'mcp_errors': errors, 'game_executed': False,
          'limitations': ['Static addresses are not runtime addresses or validated call ABI.',
                         'Decoded unwind fragments do not establish runtime execution.',
                         'No runtime acceptance, wire ordering or campaign execution is claimed.']}
(OUT / 'byte-and-instruction-verification.json').write_text(
    json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'mcp_responses': len(records), 'mcp_byte_checks': len(checks),
                  'decoded_instructions': len(paths), 'table_slots': len(tables),
                  'hashes_match': True, 'errors': errors}, indent=2))
