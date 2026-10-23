"""Read-only PE/string/xref candidate index. Does not load or execute the image."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import bisect
import hashlib
import json
import mmap
import re
import struct

TERMS = {
    "engine": ["++UE5", "++UE4", "Release-5.", "Release-4.", "Unreal Engine", "Build.version"],
    "player": ["CreatePlayer", "CreateLocalPlayer", "SpawnPlayActor", "RestartPlayer", "Possess",
               "ClientRestart", "InitNewPlayer", "LivePlayerPlane", "LivePlayerController",
               "CreatePlayerPlane", "SpawnPlayerPlane", "CreatePlane", "SetupPlayer", "InitPlayer"],
    "mission": ["StartMission", "BeginMission", "MissionStart", "InitMission", "StartSortie",
                "SortieStart", "LiveMission", "LiveStage", "LiveGameInstance", "Mission007",
                "StartGame", "LoadMission", "MissionComplete", "MissionFailed", "SetMission"],
    "network": ["NetDriver", "CreateNetDriver", "InitListen", "ServerReplicateActors", "PreReplication",
                "GetLifetimeReplicatedProps", "RepNotify", "CallRemoteFunction", "ProcessRemoteFunction",
                "StrixNetworkFacade", "LiveNetwork", "bReplicates", "bReplicateMovement", "RemoteRole",
                "ServerTravel", "ClientTravel", "ReplicatedUsing", "ReplicateMovement"],
}


def index(image):
    with image.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        digest = hashlib.sha256(data).hexdigest()
        if digest != "51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f":
            raise ValueError("Unrecognized build; no old addresses may be reused")
        pe = struct.unpack_from("<I", data, 0x3c)[0]
        opt = pe + 24
        base = struct.unpack_from("<Q", data, opt + 24)[0]
        sh = opt + struct.unpack_from("<H", data, pe + 20)[0]
        sections = []
        for i in range(struct.unpack_from("<H", data, pe + 6)[0]):
            at = sh + 40 * i
            vs, rva, size, offset = struct.unpack_from("<IIII", data, at + 8)
            flags = struct.unpack_from("<I", data, at + 36)[0]
            if offset + size > len(data):
                raise ValueError("Section exceeds file")
            sections.append((rva, size, offset, flags))

        def rva_for(off):
            for rv, size, offset, flags in sections:
                if offset <= off < offset + size:
                    return rv + off - offset

        def off_for(rva):
            for rv, size, offset, flags in sections:
                if rv <= rva < rv + size:
                    return offset + rva - rv
            raise ValueError(f"Not file-backed: {rva:x}")

        def executable(va):
            return any(rv <= va - base < rv + size and flags & 0x20000000 for rv, size, _, flags in sections)

        exception_rva, exception_size = struct.unpack_from("<II", data, opt + 112 + 24)
        eo = off_for(exception_rva)
        ranges = sorted(struct.unpack_from("<III", data, at) for at in range(eo, eo + exception_size - 11, 12))
        ranges = [row for row in ranges if row[0] < row[1]]
        starts = [r[0] for r in ranges]

        def containing(rva):
            at = bisect.bisect_right(starts, rva) - 1
            if at < 0 or rva >= ranges[at][1]:
                return None
            row = ranges[at]
            original = row
            for _ in range(20):
                off = off_for(row[2])
                flags, _, count, _ = struct.unpack_from("4B", data, off)
                if flags >> 3 & 4:
                    row = struct.unpack_from("<III", data, off + 4 + ((count + 1) & ~1) * 2)
                else:
                    return {"primary_rva": hex(row[0]), "fragment_start_rva": hex(original[0]), "fragment_end_rva": hex(original[1])}
            raise ValueError("Unwind chain cycle/depth")

        hits = []
        for category, terms in TERMS.items():
            for term in terms:
                for encoding in ("ascii", "utf-16-le"):
                    needle = term.encode(encoding)
                    cursor = 0
                    for _ in range(96):
                        at = data.find(needle, cursor)
                        if at < 0:
                            break
                        cursor = at + len(needle)
                        lo = max(0, at - 80)
                        hi = min(len(data), at + len(needle) + 220)
                        if encoding == "utf-16-le":
                            lo += (at - lo) % 2
                            hi -= (hi - lo) % 2
                        context = bytes(data[lo:hi]).decode(encoding, errors="replace")
                        hits.append({"category": category, "term": term, "encoding": encoding,
                                     "file_offset": at, "rva": rva_for(at), "context": context,
                                     "terminated": bytes(data[at + len(needle):at + len(needle) + (2 if encoding == 'utf-16-le' else 1)]) == (b'\0\0' if encoding == 'utf-16-le' else b'\0')})
        pointers = []
        string_rvas = {h["rva"] for h in hits if h["rva"] is not None}
        print(f"String search complete: {len(hits)} hits", flush=True)
        # One overlapping scan, instead of one full-file scan for each string.
        pointer_pattern = re.compile(rb"(?=(...." + re.escape(struct.pack("<I", base >> 32)) + rb"))", re.S)
        for match in pointer_pattern.finditer(data):
            at = match.start()
            if at % 8 or at + 16 > len(data):
                continue
            rv = struct.unpack("<Q", match.group(1))[0] - base
            if rv not in string_rvas:
                continue
            fn = struct.unpack_from("<Q", data, at + 8)[0]
            if executable(fn):
                pointers.append({"string_rva": hex(rv), "table_rva": hex(rva_for(at)) if rva_for(at) is not None else None,
                                 "function_rva": hex(fn - base), "function_va": hex(fn),
                                 "range": containing(fn - base), "status": "adjacent_pointer_pair_candidate_only"})
        print(f"Pointer scan complete: {len(pointers)} candidates", flush=True)
        xrefs = []
        pattern = re.compile(rb"[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]....", re.S)
        for rv, size, off, flags in sections:
            if not flags & 0x20000000:
                continue
            for match in pattern.finditer(data, off, off + size):
                src = rv + match.start() - off
                target = src + 7 + struct.unpack_from("<i", match.group(), 3)[0]
                if target in string_rvas:
                    xrefs.append({"instruction_rva": hex(src), "string_rva": hex(target),
                                  "bytes": match.group().hex(), "range": containing(src),
                                  "status": "RIP_LEA_candidate_requires_instruction_validation"})
        hints = []
        # Existing project source, not an independently established semantic label.
        for name, rv in [("spawn_actor_from_native_plane_flight_probe", 0x465a120)]:
            at = off_for(rv)
            hints.append({"name": name, "source": "native/plane_flight_probe.cpp:71", "rva": hex(rv),
                          "bytes": bytes(data[at:at+32]).hex(), "range": containing(rv), "semantic_status": "unverified_hint"})
        return {"time_utc": datetime.now(timezone.utc).isoformat(), "image": str(image.resolve()),
                "sha256": digest, "image_base": hex(base), "exception_function_ranges": len(ranges),
                "strings": hits, "pointer_pairs": pointers, "rip_lea_candidates": xrefs, "project_hints": hints,
                "limitations": ["No target execution", "Raw byte xrefs and pointer adjacency are candidates, not confirmed functions", "Case-sensitive bounded string searches; no conclusion from absence", "No runtime ownership, authority or replication verification"]}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--image", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    result = index(args.image)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Indexed {len(result['strings'])} string hits, {len(result['pointer_pairs'])} pointer pairs, {len(result['rip_lea_candidates'])} RIP candidates")
