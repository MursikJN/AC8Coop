"""Bounded READ-ONLY AC8 memory/code inspection; never attaches a debugger or writes memory."""
import argparse
import csv
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, r"D:\projects\unreal-mod-tools\packages\python-analysis")
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

GAME = Path(r"D:\SteamLibrary\steamapps\common\ACE COMBAT 8\Game\Binaries\Win64\AceCombat8.exe")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--pid", type=int, required=True)
    p.add_argument("--base", type=lambda x: int(x, 0), required=True)
    p.add_argument("--addresses", type=Path)
    p.add_argument("--code", action="append", default=[], type=lambda x: int(x, 0))
    p.add_argument("--data", action="append", default=[], help="address:size (max 256 bytes each)")
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    k = C.WinDLL("kernel32", use_last_error=True)
    k.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    k.OpenProcess.restype = W.HANDLE
    k.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
    k.ReadProcessMemory.restype = W.BOOL
    k.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
    k.QueryFullProcessImageNameW.restype = W.BOOL
    k.CloseHandle.argtypes = [W.HANDLE]
    handle = k.OpenProcess(0x10 | 0x1000, False, a.pid)  # VM_READ + QUERY_LIMITED_INFORMATION only
    if not handle:
        raise C.WinError(C.get_last_error())

    def read(address, size):
        if not 0 < size <= 4096:
            raise ValueError("Read exceeds bound")
        buffer = C.create_string_buffer(size)
        got = C.c_size_t()
        if not k.ReadProcessMemory(handle, address, buffer, size, C.byref(got)) or got.value != size:
            raise C.WinError(C.get_last_error())
        return buffer.raw

    try:
        image_path = C.create_unicode_buffer(32768)
        length = W.DWORD(len(image_path))
        if not k.QueryFullProcessImageNameW(handle, 0, image_path, C.byref(length)):
            raise C.WinError(C.get_last_error())
        if Path(image_path.value).resolve() != GAME.resolve():
            raise ValueError("PID no longer identifies the intended game")
        headers = read(a.base, 4096)
        pe = struct.unpack_from("<I", headers, 0x3C)[0]
        if headers[:2] != b"MZ" or headers[pe:pe+4] != b"PE\0\0":
            raise ValueError("Invalid module base")
        sections = struct.unpack_from("<H", headers, pe+6)[0]
        optsize = struct.unpack_from("<H", headers, pe+20)[0]
        ranges = []
        for n in range(sections):
            offset = pe+24+optsize+n*40
            vsize, rva = struct.unpack_from("<II", headers, offset+8)
            flags = struct.unpack_from("<I", headers, offset+36)[0]
            if flags & 0x20000000:
                ranges.append((a.base+rva, a.base+rva+vsize))
        report = {"pid": a.pid, "image": str(GAME), "base": hex(a.base), "read_only": True,
                  "ufunction_native_pointer_offset": "0xd8 (observed in this UE4SS session log)",
                  "targets": [], "code": [], "data": []}
        targets = list(a.code)
        if a.addresses:
            for row in csv.DictReader(a.addresses.read_text(encoding="utf-8-sig").splitlines(), delimiter="\t"):
                if row["kind"] != "ufunction":
                    continue
                obj = int(row["address"], 0)
                native = struct.unpack("<Q", read(obj+0xD8, 8))[0]
                report["targets"].append({"name": row["name"], "ufunction": hex(obj), "native": hex(native)})
                targets.append(native)
        decoder = Cs(CS_ARCH_X86, CS_MODE_64)
        for address in dict.fromkeys(targets):
            containing = next(((lo, hi) for lo, hi in ranges if lo <= address < hi), None)
            if not containing:
                report["code"].append({"address": hex(address), "error": "outside game executable sections"})
                continue
            data = read(address, min(512, containing[1]-address))
            instructions = []
            for ins in decoder.disasm(data, address):
                instructions.append({"address": hex(ins.address), "bytes": ins.bytes.hex(), "mnemonic": ins.mnemonic, "operands": ins.op_str})
                if ins.mnemonic in ("ret", "retf", "int3"):
                    break
            report["code"].append({"address": hex(address), "sha256": hashlib.sha256(data).hexdigest(),
                                   "bytes_read": len(data), "bytes_hex": data.hex(), "instructions": instructions})
        for spec in a.data:
            addr, size = (int(x, 0) for x in spec.split(":"))
            if size > 256:
                raise ValueError("Data read exceeds 256 bytes")
            report["data"].append({"address": hex(addr), "size": size, "bytes_hex": read(addr, size).hex()})
        a.output.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
        for target in report["targets"]:
            print(target["name"], target["native"])
        print("Saved bounded read-only report:", a.output)
    finally:
        k.CloseHandle(handle)


if __name__ == "__main__":
    main()
