"""Bounded, read-only AC8 flight observation. Never writes/calls inside the game."""
import argparse
import ctypes as C
from ctypes import wintypes as W
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import struct
import time

GAME = Path(r"D:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe")
SHA = "51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f"
LAYOUT = Path(__file__).resolve().parents[1] / "native/plane_motion_layout.json"
F14D_VTABLE_RVA = 0xCC01CC8
INLINE = 0x2268
EXTENT = 0x948
TYPES = {"float32": "f", "float64": "d", "uint8": "B", "uint32_bits": "I"}


def load_layout(path=LAYOUT):
    layout = json.loads(path.read_text(encoding="utf-8-sig"))
    if (layout["image_sha256"].lower() != SHA
            or int(layout["origin"]["actor_inline_offset"], 0) != INLINE
            or int(layout["read_extent"]["bytes"], 0) != EXTENT):
        raise ValueError("unsupported layout/build")
    seen = set()
    for field in layout["fields"]:
        offset, count = int(field["offset"], 0), field["count"]
        size = struct.calcsize("<" + TYPES[field["type"]]) * count
        if not 0 < count <= 16 or offset < 0 or offset + size > EXTENT or offset in seen:
            raise ValueError("invalid field bounds/duplicate")
        seen.add(offset)
    if len(seen) != 16:
        raise ValueError("unexpected field count")
    return layout


def decode_block(block, layout):
    if len(block) != EXTENT:
        raise ValueError("incomplete flight block")
    result = {}
    for field in layout["fields"]:
        offset, count = int(field["offset"], 0), field["count"]
        fmt = "<" + TYPES[field["type"]] * count
        size = struct.calcsize(fmt)
        values = struct.unpack_from(fmt, block, offset)
        result[field["offset"]] = {
            "values": [v if not isinstance(v, float) or math.isfinite(v) else str(v) for v in values],
            "raw_hex": block[offset:offset+size].hex(),
        }
    return result


def parse_ticket(path, process_created, session_started, now):
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    if len(lines) != 10 or path.stat().st_size > 8192:
        raise ValueError("invalid ticket size")
    values = dict(line.split("\t", 1) for line in lines)
    if len(values) != 10 or values["format"] != "ac8-flight-ticket-v1":
        raise ValueError("invalid ticket format")
    created = int(values["created_unix"])
    if created < max(process_created, session_started)-1 or not -1 <= now-created <= 60:
        raise ValueError("stale ticket")
    if "Mission007" not in values["world_name"]:
        raise ValueError("wrong mission")
    for name in ("controller", "pawn", "pawn_class", "world"):
        value = int(values[name], 0)
        if not 0x10000 <= value < 0x800000000000 or value % 8:
            raise ValueError("invalid object address")
        values[name] = value
    for name in ("pc_pawn_offset", "plane_controller_offset"):
        value = int(values[name], 0)
        if not 0x28 <= value <= 0x2000 or value % 8:
            raise ValueError("invalid property offset")
        values[name] = value
    return values


class FlightReader:
    """Identity checks bracket each read. They are guards, NOT an engine object pin/serial check."""
    def __init__(self, read, base, ticket):
        self.read, self.base, self.ticket = read, base, ticket
        self.identities = None
        self.check_identity()

    def qword(self, address):
        return struct.unpack("<Q", self.read(address, 8))[0]

    def check_identity(self):
        t = self.ticket
        if self.qword(t["pawn"]) != self.base + F14D_VTABLE_RVA:
            raise ValueError("F-14D vtable changed/unsupported aircraft")
        if self.qword(t["pawn"] + 0x10) != t["pawn_class"]:
            raise ValueError("pawn class changed")
        if self.qword(t["controller"] + t["pc_pawn_offset"]) != t["pawn"]:
            raise ValueError("controlled pawn changed")
        if self.qword(t["pawn"] + t["plane_controller_offset"]) != t["controller"]:
            raise ValueError("controller backlink changed")
        identities = []
        for name in ("controller", "pawn", "world"):
            header = self.read(t[name], 0x28)
            # UE UObject: vtable; InternalIndex/Class/Name/Outer. ObjectFlags may change.
            identities.append((header[:8], header[12:]))
        if self.identities is not None and identities != self.identities:
            raise ValueError("object identity header changed")
        self.identities = identities

    def sample(self, layout):
        self.check_identity()
        block = self.read(self.ticket["pawn"] + INLINE, EXTENT)
        self.check_identity()
        return decode_block(block, layout)


class WindowsReader:
    def __init__(self, pid, session_started):
        self.k = k = C.WinDLL("kernel32", use_last_error=True)
        k.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
        k.OpenProcess.restype = W.HANDLE
        k.CloseHandle.argtypes = [W.HANDLE]
        k.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
        k.ReadProcessMemory.restype = W.BOOL
        k.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
        k.QueryFullProcessImageNameW.restype = W.BOOL
        k.GetProcessTimes.argtypes = [W.HANDLE] + [C.POINTER(W.FILETIME)] * 4
        k.GetProcessTimes.restype = W.BOOL
        self.handle = k.OpenProcess(0x1010, False, pid)  # VM_READ | QUERY_LIMITED_INFORMATION
        if not self.handle:
            raise C.WinError(C.get_last_error())
        try:
            path, length = C.create_unicode_buffer(32768), W.DWORD(32768)
            if not k.QueryFullProcessImageNameW(self.handle, 0, path, C.byref(length)):
                raise C.WinError(C.get_last_error())
            if Path(path.value).resolve() != GAME.resolve():
                raise ValueError("PID is not the configured game")
            times = [W.FILETIME() for _ in range(4)]
            if not k.GetProcessTimes(self.handle, *(C.byref(t) for t in times)):
                raise C.WinError(C.get_last_error())
            self.created = ((times[0].dwHighDateTime << 32) | times[0].dwLowDateTime) / 1e7 - 11644473600
            if not -1 <= self.created - session_started <= 60:
                raise ValueError("process does not belong to this launcher session")
            with GAME.open("rb") as f:
                digest = hashlib.file_digest(f, "sha256").hexdigest()
            if digest != SHA:
                raise ValueError("game build changed")
            self.base = self.module_base(pid)
            if self.read(self.base, 2) != b"MZ":
                raise ValueError("invalid module base")
        except BaseException:
            self.close()
            raise

    def module_base(self, pid):
        class Module(C.Structure):
            _fields_ = [("dwSize", W.DWORD), ("th32ModuleID", W.DWORD),
                        ("th32ProcessID", W.DWORD), ("GlblcntUsage", W.DWORD),
                        ("ProccntUsage", W.DWORD), ("modBaseAddr", C.c_void_p),
                        ("modBaseSize", W.DWORD), ("hModule", W.HMODULE),
                        ("szModule", W.WCHAR * 256), ("szExePath", W.WCHAR * 260)]
        k = self.k
        k.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
        k.CreateToolhelp32Snapshot.restype = W.HANDLE
        k.Module32FirstW.argtypes = [W.HANDLE, C.POINTER(Module)]
        k.Module32FirstW.restype = W.BOOL
        k.Module32NextW.argtypes = [W.HANDLE, C.POINTER(Module)]
        k.Module32NextW.restype = W.BOOL
        snap = k.CreateToolhelp32Snapshot(8, pid)
        if snap == C.c_void_p(-1).value:
            raise C.WinError(C.get_last_error())
        try:
            module = Module()
            module.dwSize = C.sizeof(module)
            more = k.Module32FirstW(snap, C.byref(module))
            while more:
                if Path(module.szExePath).resolve() == GAME.resolve():
                    return module.modBaseAddr
                more = k.Module32NextW(snap, C.byref(module))
            raise ValueError("game module not found")
        finally:
            k.CloseHandle(snap)

    def read(self, address, size):
        if not 0 < size <= EXTENT or not 0x10000 <= address < 0x800000000000:
            raise ValueError("read outside permitted bounds")
        buffer, got = C.create_string_buffer(size), C.c_size_t()
        if not self.k.ReadProcessMemory(self.handle, address, buffer, size, C.byref(got)) or got.value != size:
            raise OSError("ReadProcessMemory failed or short read", C.get_last_error())
        return buffer.raw

    def close(self):
        if self.handle:
            self.k.CloseHandle(self.handle)
            self.handle = None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--session", type=Path, required=True)
    p.add_argument("--wait-ticket", type=int, default=600)
    p.add_argument("--duration", type=float, default=30)
    p.add_argument("--hz", type=float, default=10)
    a = p.parse_args()
    if not 0 < a.duration <= 60 or not 1 <= a.hz <= 20 or not 0 <= a.wait_ticket <= 900:
        p.error("limits: duration (0,60], Hz [1,20], ticket wait [0,900]")
    layout = load_layout()
    session = json.loads((a.session / "session.json").read_text(encoding="utf-8-sig"))
    if session["extension"] != "plane_motion_probe.lua" or session["game_sha256"].lower() != SHA or session.get("finished"):
        raise ValueError("need an active plane_motion_probe launcher session")
    started = datetime.fromisoformat(session["started"]).timestamp()
    reader = WindowsReader(int(session["pid"]), started)
    try:
        print("WAITING_FOR_FRESH_F8_TICKET", flush=True)
        deadline = time.monotonic() + a.wait_ticket
        while True:
            paths = sorted(a.session.glob("flight-ticket-*.tsv"), key=lambda f: f.stat().st_mtime_ns, reverse=True)
            if paths:
                ticket_path = paths[0]
                ticket = parse_ticket(ticket_path, reader.created, started, time.time())
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("no F8 flight ticket")
            time.sleep(0.2)
        flight = FlightReader(reader.read, reader.base, ticket)
        output = a.session / (ticket_path.stem.replace("flight-ticket-", "flight-motion-") + ".jsonl")
        manifest_path = output.with_suffix(".manifest.json")
        manifest = {"read_only": True, "pid": session["pid"], "process_created": reader.created,
                    "game_sha256": SHA, "base": hex(reader.base), "ticket": ticket,
                    "ticket_file": ticket_path.name, "layout": layout, "duration": a.duration,
                    "hz": a.hz, "samples": 0, "result": "recording",
                    "limitations": "external reads are not atomic; header/backlink guards do not pin UObject lifetime or verify serial; no native apply/creation tested"}
        # Exclusive outputs: a second invocation cannot silently replace a successful record.
        with manifest_path.open("x", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)
        try:
            with output.open("x", encoding="utf-8") as f:
                print("RECORDING_FLIGHT_READ_ONLY", flush=True)
                begin = time.perf_counter()
                for index in range(math.ceil(a.duration * a.hz)):
                    remaining = begin + index/a.hz - time.perf_counter()
                    if remaining > 0:
                        time.sleep(remaining)
                    sample_started = time.perf_counter()
                    sample = flight.sample(layout)
                    row = {"index": index, "elapsed_s": sample_started-begin,
                           "read_ms": (time.perf_counter()-sample_started)*1000, "fields": sample}
                    f.write(json.dumps(row, allow_nan=False) + "\n")
                    f.flush()
                    manifest["samples"] += 1
                manifest["result"] = "capture_complete"
        except Exception as error:
            manifest["result"] = "stopped"
            manifest["error"] = str(error)
        finally:
            manifest["finished"] = datetime.now().astimezone().isoformat()
            temp = manifest_path.with_suffix(".tmp")
            temp.write_text(json.dumps(manifest, indent=2, allow_nan=False) + "\n", encoding="utf-8")
            temp.replace(manifest_path)
        print(json.dumps({"result": manifest["result"], "samples": manifest["samples"], "output": str(output)}), flush=True)
        if manifest["result"] != "capture_complete":
            raise SystemExit(1)
    finally:
        reader.close()


if __name__ == "__main__":
    main()
