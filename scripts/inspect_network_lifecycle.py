"""Offline AC8 string anchors and bounded RIP-relative references; no game execution.

These are candidate registration/code locations, not recovered callable signatures.
All addresses are preferred image VAs/RVAs, never live process addresses.
"""
import argparse
import bisect
import hashlib
import json
import mmap
from pathlib import Path
import re
import struct

TOKENS = re.compile(
    r"LiveNetwork\w+|NetworkObject(?:Manager|Spawner)|SpawnRemote|"
    r"Create\w*Network|Network\w*(?:Create|Spawn|Link)|Link\w*Actor|"
    r"OnRestored|ResetFlightModel|OnNetworkMovement|NetworkOwnership|"
    r"LiveOnlineGameMode\w*|LiveTeamDeathMatchGameMode|"
    r"ELive(?:Online)?GameModeState::(?:SpawnPlayerPlane|WaitingSpawnedPlayers)", re.I)
ANCHORS = {
    "ULiveNetworkPlayerPlane", "ULiveNetworkBaseObject", "ULiveNetworkGameObject",
    "ALiveNetworkDummyController", "ULiveNetworkManager", "ULiveNetworkP2P",
    "ALiveOnlineGameMode", "ALiveTeamDeathMatchGameMode",
    "ULiveNetworkCoopGameMode", "ULiveNetworkCompetitiveCoopGameMode",
}


def inspect(path):
    with path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        if data[:2] != b"MZ":
            raise ValueError("Not a PE image")
        pe = struct.unpack_from("<I", data, 0x3c)[0]
        if data[pe:pe+4] != b"PE\0\0":
            raise ValueError("Bad PE signature")
        count = struct.unpack_from("<H", data, pe+6)[0]
        opt = pe+24
        if struct.unpack_from("<H", data, opt)[0] != 0x20b:
            raise ValueError("Expected PE32+")
        base = struct.unpack_from("<Q", data, opt+24)[0]
        start = opt+struct.unpack_from("<H", data, pe+20)[0]
        sections = []
        for i in range(count):
            at = start+40*i
            vs, rva, size, offset = struct.unpack_from("<IIII", data, at+8)
            if offset+size > len(data):
                raise ValueError("Section extends beyond file")
            sections.append(dict(name=data[at:at+8].rstrip(b"\0").decode(), rva=rva,
                                 virtual_size=vs, offset=offset, size=size,
                                 flags=struct.unpack_from("<I", data, at+36)[0]))

        def rva_for(offset):
            for s in sections:
                if s["offset"] <= offset < s["offset"]+s["size"]:
                    return s["rva"]+offset-s["offset"]

        def offset_for(rva):
            for s in sections:
                if s["rva"] <= rva < s["rva"]+s["size"]:
                    return s["offset"]+rva-s["rva"]

        strings = []
        for encoding, pattern in [("ascii", rb"[\x20-\x7e]{5,}"),
                                  ("utf-16le", rb"(?:[\x20-\x7e]\x00){5,}")]:
            for match in re.finditer(pattern, data):
                value = match.group().decode(encoding)
                if TOKENS.search(value):
                    strings.append(dict(text=value, encoding=encoding,
                                        offset=match.start(), rva=rva_for(match.start())))
        # Exception directory is an independent source of candidate function ranges.
        ex_rva, ex_size = struct.unpack_from("<II", data, opt+112+3*8)
        ex_offset = offset_for(ex_rva)
        ranges = []
        if ex_offset is not None and ex_offset+ex_size <= len(data):
            for at in range(ex_offset, ex_offset+ex_size-11, 12):
                lo, hi, unwind = struct.unpack_from("<III", data, at)
                if lo < hi:
                    ranges.append((lo, hi, unwind))
        ranges.sort()
        starts = [row[0] for row in ranges]
        anchors = {row["rva"]: row["text"] for row in strings if row["text"] in ANCHORS}
        # Unreal registration may point past the C++ U/A prefix into a pooled literal.
        for row in strings:
            if row["text"] in ANCHORS and row["text"][0] in "UA":
                anchors[row["rva"]+(2 if row["encoding"] == "utf-16le" else 1)] = row["text"][1:]
        references = []
        # This intentionally narrow scan does not claim complete code xrefs.
        pattern = re.compile(rb"[\x48-\x4f]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]....", re.S)
        for s in sections:
            if not s["flags"] & 0x20000000:
                continue
            for match in pattern.finditer(data, s["offset"], s["offset"]+s["size"]):
                rva = rva_for(match.start())
                target = rva+7+struct.unpack_from("<i", match.group(), 3)[0]
                if target not in anchors:
                    continue
                index = bisect.bisect_right(starts, rva)-1
                span = ranges[index] if index >= 0 and rva < ranges[index][1] else None
                references.append(dict(anchor=anchors[target], rva=rva, va=hex(base+rva),
                    bytes=match.group().hex(), target_rva=target,
                    runtime_function=span,
                    context_offset=max(s["offset"], match.start()-96),
                    context_hex=data[max(s["offset"], match.start()-96):min(match.start()+128, s["offset"]+s["size"])].hex()))
        return dict(path=str(path), sha256=hashlib.sha256(data).hexdigest(), image_base=base,
                    sections=sections, strings=strings, references=references,
                    limitations=["ASCII and ASCII-range UTF-16LE string scan only.",
                        "RIP-relative LEA byte matches can be data or misaligned instructions; verify decoding.",
                        "Runtime function ranges are PE unwind entries, not semantic function identities.",
                        "Names and references do not prove gameplay behavior or safe call contracts.",
                        "No target execution; no game files or process memory modified."])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = inspect(args.image)
    args.output.write_text(json.dumps(result, indent=2)+"\n", encoding="utf8")
    print("sha256", result["sha256"])
    print("strings", len(result["strings"]), "candidate references", len(result["references"]))
    for row in result["references"]:
        print(row["anchor"], row["va"], "function", row["runtime_function"])
