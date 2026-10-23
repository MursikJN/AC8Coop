"""Read-only PE verification of the session-routing GhidraMCP evidence."""
import hashlib
import json
import struct
from datetime import datetime, timezone
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/session-routing-ghidra-20261022'
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

targets = {0x75034c0, 0x751f220, 0x751f7b0, 0x74b53f0, 0x74b5310,
           0x71ca650, 0x7502120, 0x7502180, 0x7502210, 0x78e3fe0,
           0x75039c0, 0x7503ab0, 0x74c70c0, 0x74ced40, 0x7502ce0,
           0x7502500, 0x7500670, 0x780c030, 0x75002a0}
cs = Cs(CS_ARCH_X86, CS_MODE_64)
paths = []
for row in ranges:
    begin, end, _ = row
    if not (0x71c0000 <= begin < 0x71e0000 or 0x74b0000 <= begin < 0x7520000
            or 0x780c000 <= begin < 0x780d000 or 0x78e0000 <= begin < 0x78f0000):
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
    0x7503555: ('4189571c', 'sender metadata write'),
    0x75035d8: ('49c1e138', 'category shifted by 56 bits'),
    0x71ca910: ('b903000000', 'local network role candidate 3'),
    0x71ca915: ('ba01000000', 'offline role candidate 1'),
    0x71ca927: ('0f44ca', 'select offline role when system flag is zero'),
    0x71ca92c: ('41888ed80e0000', 'write selected plane role'),
    0x78e40aa: ('ff90400a0000', 'state 1 transition call'),
    0x78e4109: ('ff90400a0000', 'state 5 transition call'),
    0x78e4121: ('ff90400a0000', 'state 6 transition call'),
}
anchor_checks = []
by_va = {int(x['va'], 16): x for x in paths}
for rv, (expected, meaning) in anchors.items():
    item = by_va[base + rv]
    assert item['bytes'] == expected, (hex(rv), item)
    anchor_checks.append(dict(item, meaning=meaning, match=True))
tables = []
for rv, expected in [(0xcb7fc18, 0x751f220), (0xcb7fe90, 0x751f7b0),
                     (0xcbc6560, 0x78e4440)]:
    actual = struct.unpack_from('<Q', m, off(rv))[0]
    assert actual == base + expected
    tables.append({'slot_va': hex(base + rv), 'target_rva': hex(expected), 'match': True})
errors = [r['id'] for r in records if r['response'].get('isError')]
assert not errors
result = {'utc': datetime.now(timezone.utc).isoformat(), 'image_base': hex(base),
          'artifacts': identities, 'mcp_byte_checks': checks,
          'verified_table_slots': tables, 'decoded_instructions': paths,
          'asserted_instruction_anchors': anchor_checks,
          'mcp_responses': len(records), 'mcp_errors': errors, 'game_executed': False,
          'limitations': ['Static addresses are not runtime addresses or validated call ABI.',
                         'Decoded unwind fragments do not establish runtime execution.',
                         'Sender admission, transport ordering and full session bootstrap remain incomplete.']}
(OUT / 'byte-and-instruction-verification.json').write_text(
    json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'mcp_responses': len(records), 'mcp_byte_checks': len(checks),
                  'decoded_instructions': len(paths), 'table_slots': len(tables),
                  'hashes_match': True, 'errors': errors}, indent=2))
