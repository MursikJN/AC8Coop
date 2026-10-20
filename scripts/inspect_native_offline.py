"""Bounded read-only PE function inspection with chained-unwind range recovery.

Disassembly, direct-call byte candidates and pointer occurrences are observations,
not recovered source signatures. Never loads or executes the inspected image.
"""
import argparse
import bisect
import hashlib
import json
import mmap
from pathlib import Path
import re
import struct
import sys

sys.path.insert(0, r"D:\projects\unreal-mod-tools\packages\python-analysis")
import capstone
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

EXPECTED = "51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f"
GAME = Path(r"D:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe")


def inspect(image, rvas, calls_to, pointers_to, byte_limit=24000):
    with image.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        digest = hashlib.sha256(data).hexdigest()
        if digest != EXPECTED:
            raise ValueError("Image hash changed; revalidate this AC8 analysis profile")
        pe = struct.unpack_from("<I", data, 0x3c)[0]
        opt = pe+24
        base = struct.unpack_from("<Q", data, opt+24)[0]
        ns = struct.unpack_from("<H", data, pe+6)[0]
        sh = opt+struct.unpack_from("<H", data, pe+20)[0]
        sections = []
        for i in range(ns):
            at = sh+40*i
            vs, rva, size, offset = struct.unpack_from("<IIII", data, at+8)
            if offset+size > len(data):
                raise ValueError("Section outside file")
            sections.append((rva, size, offset, struct.unpack_from("<I", data, at+36)[0]))

        def offset_for(rva):
            for rv, sz, off, flags in sections:
                if rv <= rva < rv+sz:
                    return off+rva-rv
            raise ValueError("RVA is not file-backed: " + hex(rva))

        def rva_for(offset):
            for rv, sz, off, flags in sections:
                if off <= offset < off+sz:
                    return rv+offset-off
            return None

        er, es = struct.unpack_from("<II", data, opt+112+24)
        eo = offset_for(er)
        ranges = sorted(struct.unpack_from("<III", data, at) for at in range(eo, eo+es-11, 12))
        starts = [r[0] for r in ranges]
        cache = {}

        def primary(row, depth=0):
            if row in cache:
                return cache[row]
            if depth > 16:
                raise ValueError("Unwind chain depth exceeded")
            at = offset_for(row[2])
            version_flags, prolog, count, frame = struct.unpack_from("4B", data, at)
            if version_flags >> 3 & 4:
                parent = struct.unpack_from("<III", data, at+4+((count+1)&~1)*2)
                result = primary(parent, depth+1)
            else:
                result = row[0]
            cache[row] = result
            return result

        def containing(rva):
            index = bisect.bisect_right(starts, rva)-1
            return ranges[index] if index >= 0 and rva < ranges[index][1] else None

        groups = {}
        for row in ranges:
            if row[0] < row[1]:
                groups.setdefault(primary(row), []).append(row)
        decoder = Cs(CS_ARCH_X86, CS_MODE_64)
        functions = []
        for rva in rvas:
            row = containing(rva)
            if row is None:
                at = offset_for(rva)
                raw = data[at:at+64]
                insns = []
                for i in decoder.disasm(raw, base+rva):
                    insns.append(dict(address=hex(i.address), rva=hex(i.address-base), bytes=i.bytes.hex(),
                                      mnemonic=i.mnemonic, operands=i.op_str))
                    if i.mnemonic in ("ret", "jmp", "int3"):
                        break
                functions.append(dict(requested_rva=hex(rva), primary_rva=None,
                    limitation="no_exception_directory_range; 64-byte leaf/thunk candidate only",
                    fragments=[dict(start_rva=hex(rva), bytes_read=len(raw), bytes_hex=raw.hex(),
                                    instructions=insns)], truncated=True))
                continue
            start = primary(row)
            remaining = byte_limit
            fragments = []
            for lo, hi, unwind in groups[start]:
                if remaining <= 0:
                    break
                amount = min(hi-lo, remaining)
                at = offset_for(lo)
                raw = data[at:at+amount]
                insns = [dict(address=hex(i.address), rva=hex(i.address-base),
                    bytes=i.bytes.hex(), mnemonic=i.mnemonic, operands=i.op_str)
                    for i in decoder.disasm(raw, base+lo)]
                decoded = sum(len(bytes.fromhex(i["bytes"])) for i in insns)
                fragments.append(dict(start_rva=hex(lo), end_rva=hex(hi), unwind_rva=hex(unwind),
                    bytes_read=amount, decoded_bytes=decoded, sha256=hashlib.sha256(raw).hexdigest(),
                    bytes_hex=raw.hex(), instructions=insns))
                remaining -= amount
            total = sum(hi-lo for lo, hi, _ in groups[start])
            functions.append(dict(requested_rva=hex(rva), primary_rva=hex(start),
                total_bytes=total, truncated=total > byte_limit, fragments=fragments))
        calls = []
        targets = set(calls_to)
        if targets:
            for rv, sz, off, flags in sections:
                if not flags & 0x20000000:
                    continue
                for match in re.finditer(rb"\xe8....", data[off:off+sz], re.S):
                    at = rv+match.start()
                    target = at+5+struct.unpack_from("<i", match.group(), 1)[0]
                    if target not in targets:
                        continue
                    row = containing(at)
                    calls.append(dict(call_rva=hex(at), target_rva=hex(target),
                        primary_rva=hex(primary(row)) if row else None))
        pointers = []
        for rva in pointers_to:
            needle = struct.pack("<Q", base+rva)
            cursor = 0
            count = 0
            while True:
                at = data.find(needle, cursor)
                if at < 0:
                    break
                count += 1
                if count <= 256:
                    loc = rva_for(at)
                    pointers.append(dict(target_rva=hex(rva), offset=at,
                                         pointer_rva=hex(loc) if loc is not None else None))
                cursor = at+1
            if count > 256:
                pointers.append(dict(target_rva=hex(rva), capped=True, total=count))
        return dict(image=str(image), sha256=digest, image_base=hex(base),
            decoder="Capstone "+capstone.__version__, functions=functions,
            direct_call_candidates=calls, pointer_occurrences=pointers,
            limitations=["Read-only offline; no target execution or memory writes.",
                "PE chained unwind groups are compiler ranges, not recovered semantic identities.",
                "Direct E8 byte matches need instruction-boundary verification; indirect calls not covered.",
                "Pointer matches do not establish vtable membership or use.",
                "Native argument contracts and runtime preconditions remain unverified."])


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--image", type=Path, default=GAME)
    p.add_argument("--rva", type=lambda x: int(x, 0), action="append", default=[])
    p.add_argument("--calls-to", type=lambda x: int(x, 0), action="append", default=[])
    p.add_argument("--pointers-to", type=lambda x: int(x, 0), action="append", default=[])
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    if len(args.rva)+len(args.calls_to)+len(args.pointers_to) > 32:
        raise ValueError("Too many targets")
    result = inspect(args.image, args.rva, args.calls_to, args.pointers_to)
    args.output.write_text(json.dumps(result, indent=2)+"\n", encoding="utf8")
    for fn in result["functions"]:
        print(fn["requested_rva"], fn.get("primary_rva"), fn.get("total_bytes"), "truncated", fn.get("truncated"))
    print("direct calls",len(result["direct_call_candidates"]),"pointer occurrences",len(result["pointer_occurrences"]))
