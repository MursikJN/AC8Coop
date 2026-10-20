"""Read exception context from a Windows AMD64 minidump; no target execution."""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("dump", type=Path)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--read", action="append", default=[], help="Recorded memory address:size, at most 256 bytes")
    a = p.parse_args()
    data = a.dump.read_bytes()
    def u(fmt, pos):
        return struct.unpack_from("<" + fmt, data, pos)
    assert data[:4] == b"MDMP", "Not a minidump"
    count, directory = u("II", 8)
    assert count <= 1024
    streams = {u("III", directory + i * 12)[0]: u("III", directory + i * 12)[1:] for i in range(count)}
    size, at = streams[6]
    assert size >= 168
    tid = u("I", at)[0]
    code, flags, nested, address, nparams = u("IIQQI", at + 8)
    params = u("15Q", at + 40)[:nparams]
    csize, ctx = u("II", at + 160)
    assert csize >= 256 and u("I", ctx + 48)[0] & 0x100000, "Not AMD64 context"
    names = "rax rcx rdx rbx rsp rbp rsi rdi r8 r9 r10 r11 r12 r13 r14 r15 rip".split()
    regs = dict(zip(names, u("17Q", ctx + 120)))
    report = {"dump_sha256": hashlib.sha256(data).hexdigest(), "thread": tid,
              "exception_code": hex(code), "exception_address": hex(address),
              "exception_parameters": [hex(v) for v in params], "registers": {k: hex(v) for k, v in regs.items()},
              "limits": "Recorded exception context only; no stack unwind or live reproduction."}
    ranges = []
    if 5 in streams:
        _, mem = streams[5]
        n = u("I", mem)[0]; assert n <= 100000
        for i in range(n):
            start, length, filepos = u("QII", mem + 4 + i * 16)
            ranges.append((start, length, filepos))
    if 9 in streams:
        _, mem = streams[9]
        n, filepos = u("QQ", mem); assert n <= 100000
        for i in range(n):
            start, length = u("QQ", mem + 16 + i * 16)
            ranges.append((start, length, filepos)); filepos += length
    report["memory"] = []
    for spec in a.read:
        addr, length = (int(v, 0) for v in spec.split(":"))
        assert 0 < length <= 256
        match = next((r for r in ranges if r[0] <= addr and addr + length <= r[0] + r[1]), None)
        row = {"address": hex(addr), "length": length, "recorded": match is not None}
        if match:
            at = match[2] + addr - match[0]
            assert at + length <= len(data)
            row["hex"] = data[at:at+length].hex()
            row["qwords"] = [hex(v) for v in u(str(length // 8) + "Q", at)]
        report["memory"].append(row)
    a.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
