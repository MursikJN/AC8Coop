"""Validate the current AC8 manual-control snapshot with READ-ONLY process access.

Only writes a local ready token after exact native-code and instance-layout checks.
No memory-write/debugger APIs are used. Run while game is paused after F8.
"""
import argparse
import csv
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
from pathlib import Path
import struct

GAME = Path(r"D:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe")
SHA256 = "51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f"
BASELINE = Path(r"D:\projects\unreal-mod-tools\profiles\ac8-build25201480\evidence\session-20261020-035351\native-entrypoints.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session", type=Path, required=True)
    parser.add_argument("--stamp", required=True)
    args = parser.parse_args()
    info = json.loads((args.session / "session.json").read_text(encoding="utf-8-sig"))
    assert info["game_sha256"].lower() == SHA256 and info["exit_code"] is None, "Unexpected/finished session"
    rows = list(csv.DictReader((args.session / f"manual-addresses-{args.stamp}.tsv").read_text().splitlines(), delimiter="\t"))
    functions = {r["name"]: int(r["address"], 0) for r in rows if r["kind"] == "ufunction"}
    planes = {r["name"]: int(r["address"], 0) for r in rows if r["kind"] == "plane"}
    components = {r["name"]: int(r["address"], 0) for r in rows if r["kind"] == "component"}
    assert set(planes) == set(components) == {"Joker2", "Joker3", "Joker4"}, "Incorrect target set"
    assert len(set(planes.values())) == len(set(components.values())) == 3, "Duplicate targets"
    assert set(functions) == {"InputPitch", "InputYaw", "InputRoll", "SetAIStateActive"}, "Missing code targets"
    k = C.WinDLL("kernel32", use_last_error=True)
    k.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    k.OpenProcess.restype = W.HANDLE
    k.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
    k.ReadProcessMemory.restype = W.BOOL
    k.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
    k.QueryFullProcessImageNameW.restype = W.BOOL
    k.CloseHandle.argtypes = [W.HANDLE]
    handle = k.OpenProcess(0x10 | 0x1000, False, info["pid"])
    if not handle:
        raise C.WinError(C.get_last_error())

    def read(address, size):
        assert 0 < size <= 512
        buf = C.create_string_buffer(size)
        got = C.c_size_t()
        if not k.ReadProcessMemory(handle, address, buf, size, C.byref(got)) or got.value != size:
            raise C.WinError(C.get_last_error())
        return buf.raw

    def pointer(address):
        return struct.unpack("<Q", read(address, 8))[0]

    report = {"pid": info["pid"], "stamp": args.stamp, "read_only": True, "functions": [], "slots": []}
    try:
        path = C.create_unicode_buffer(32768)
        length = W.DWORD(len(path))
        if not k.QueryFullProcessImageNameW(handle, 0, path, C.byref(length)):
            raise C.WinError(C.get_last_error())
        assert Path(path.value).resolve() == GAME.resolve(), "PID belongs to another image"
        baseline = json.loads(BASELINE.read_text())
        expected = {}
        for target in baseline["targets"]:
            name = target["name"].rsplit(":", 1)[-1]
            code = next(c for c in baseline["code"] if c["address"] == target["native"])
            expected[name] = bytes.fromhex(code["bytes_hex"])
        for name, address in functions.items():
            native = pointer(address + 0xD8)
            raw = read(native, len(expected[name]))
            assert raw == expected[name], f"Native bytes changed: {name}"
            report["functions"].append({"name": name, "native": hex(native), "sha256": hashlib.sha256(raw).hexdigest()})
        for slot, plane in planes.items():
            component = components[slot]
            assert pointer(plane + 0x2808) == component, f"AIStateComponent mismatch: {slot}"
            assert pointer(component + 0xF0) == plane, f"Owner mismatch: {slot}"
            assert read(plane + 0x29CB, 1) == b"\1", f"AI activation gate unexpected: {slot}"
            vtable = pointer(component)
            setter = pointer(vtable + 0x3D8)
            assert read(setter, 7) == bytes.fromhex("8891d3000000c3"), f"Native setter changed: {slot}"
            assert read(component + 0xD3, 1) == b"\1", f"Native enable byte unexpected: {slot}"
            scale = struct.unpack("<f", read(plane + 0x6C8, 4))[0]
            assert scale == 1.0, f"Input scale unexpected: {slot}"
            axes = struct.unpack("<3f", read(plane + 0x2A8C, 12))
            assert all(-1 <= x <= 1 for x in axes), f"Invalid axis data: {slot}"
            report["slots"].append({"slot": slot, "plane": hex(plane), "component": hex(component),
                                    "setter": hex(setter), "scale": scale, "axes": axes})
        (args.session / f"manual-validation-{args.stamp}.json").write_text(json.dumps(report, indent=2) + "\n")
        (args.session / "manual-ready.txt").write_text(args.stamp, encoding="ascii")
        print("Validated 4 native functions and 3 live wingmen. Local control ready token written.")
    finally:
        k.CloseHandle(handle)


if __name__ == "__main__":
    main()
