"""Read-only checks of the 2026-10-22 Ghidra guest-world evidence against PE bytes.

Does not load/execute the game. Raw Ghidra replies stay in the ignored lab.
Run from the repository root with the Python standard library only.
"""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / '.tools/offline-research/guest-world-r31-20261022'
EXPECTED_EXE = '51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f'
EXPECTED_ZIP = 'db9dd759be1af3c8e08096c50d87e0ded543c3ada5d78cb585263bee10c82e5d'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    copy = ROOT / '.tools/offline-research/targets/ac8-build25201480/AceCombat8.exe'
    original = Path('D:/Programs/Steam/steamapps/common/ACE COMBAT 8/Game/Binaries/Win64/AceCombat8.exe')
    kit = ROOT / 'dist/ac8-steam-coop-r31-development.zip'
    for path, expected in ((copy, EXPECTED_EXE), (original, EXPECTED_EXE), (kit, EXPECTED_ZIP)):
        assert digest(path) == expected, f'Hash mismatch: {path}'
    data = copy.read_bytes()
    pe = struct.unpack_from('<I', data, 60)[0]
    optional = pe + 24
    base = struct.unpack_from('<Q', data, optional + 24)[0]
    assert base == 0x140000000
    section_start = optional + struct.unpack_from('<H', data, pe + 20)[0]
    sections = [struct.unpack_from('<IIII', data, section_start + i * 40 + 8)
                for i in range(struct.unpack_from('<H', data, pe + 6)[0])]

    def read(va, size):
        rva = va - base
        for _, start, length, offset in sections:
            if start <= rva and rva + size <= start + length:
                return data[offset + rva - start:offset + rva - start + size]
        raise ValueError(f'Unmapped read {va:x}+{size:x}')

    records = []
    matched = []
    replies = {}
    for path in sorted((LAB / 'responses').glob('*.json')):
        record = json.loads(path.read_text(encoding='utf-8'))
        replies[path.name[:3]] = record
        records.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': digest(path),
                        'tool': record['tool'], 'args': record['args']})
        if record['tool'].endswith('__read_memory'):
            result = record['result']['structuredContent']
            assert not result['gaps'], path.name
            expected = bytes.fromhex(result['hex'])
            assert len(expected) == result['length']
            assert read(int(result['address'], 16), len(expected)) == expected, path.name
            matched.append(path.name)
    assert len(records) == 55
    names = {0x14ca59ce2: 'LiveSoundManager', 0x14c783c5a: 'LiveInformationManager',
             0x14c99293a: 'LiveObjectMapper', 0x14c650b02: 'LiveCombatZone',
             0x14cb2f65a: 'LiveWorldSubsystem'}
    for address, name in names.items():
        assert read(address, (len(name) + 1) * 2).decode('utf-16le') == name + '\0'
    slots = {0x2b8: 0x1473ad190, 0x2c0: 0x1473acfe0,
             0x2c8: 0x1473ad0d0, 0x308: 0x1473a1620}
    for slot, target in slots.items():
        assert struct.unpack('<Q', read(0x14c4b2450 + slot, 8))[0] == target
    # Narrow instruction checks at independently identified boundaries; this
    # is deliberately not a general x86 decoder or an invented native ABI.
    instruction_checks = {
        0x1478dc389: ('lea rcx,[r14+908]', '498d8e08090000'),
        0x1478dc395: ('mov r8,[r14+828]', '4d8b8628080000'),
        0x1478dc39c: ('mov rcx,[r14+908]', '498b8e08090000'),
        0x147d24a74: ('add rcx,700', '4881c100070000'),
    }
    for address, (_, expected) in instruction_checks.items():
        assert read(address, len(bytes.fromhex(expected))) == bytes.fromhex(expected), hex(address)
    def direct_call(address, expected):
        opcode = read(address, 5)
        assert opcode[0] == 0xe8
        assert address + 5 + struct.unpack_from('<i', opcode, 1)[0] == expected
    direct_call(0x1478dc3a3, 0x1478a4620)
    direct_call(0x147d24a7e, 0x1417015d0)
    out = ROOT / 'evidence/guest-world-r31-20261022'
    out.mkdir(parents=True, exist_ok=True)
    report = {'schema': 1, 'binary_sha256': EXPECTED_EXE, 'image_base': hex(base),
              'original_exe_sha256': digest(original), 'kit_sha256_unchanged': digest(kit),
              'raw_reply_count': len(records), 'memory_ranges_matched_to_copy': matched,
              'class_names_verified': {hex(a): n for a, n in names.items()},
              'actor_manager_slots_verified': {hex(s): hex(t) for s, t in slots.items()},
              'instruction_checks': {hex(a): {'instruction': n, 'hex': b}
                                     for a, (n, b) in instruction_checks.items()},
              'direct_calls_verified': {'0x1478dc3a3': '0x1478a4620',
                                        '0x147d24a7e': '0x1417015d0'},
              'raw_replies': records,
              'verifier_sha256': digest(Path(__file__)), 'game_executed': False,
              'native_calls_executed': False, 'runtime_result': 'not_tested'}
    (out / 'manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'raw_replies': len(records), 'memory_ranges_matched': len(matched),
                      'original_and_kit_hashes_unchanged': True, 'game_executed': False}))


if __name__ == '__main__':
    main()
