"""Offline UE4SS crash XML symbolication with local matching DLL/PDB. No game execution."""
import argparse
import ctypes as C
from ctypes import wintypes as W
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET


class SymbolInfo(C.Structure):
    _fields_ = [("SizeOfStruct", W.ULONG), ("TypeIndex", W.ULONG),
                ("Reserved", C.c_ulonglong * 2), ("Index", W.ULONG), ("Size", W.ULONG),
                ("ModBase", C.c_ulonglong), ("Flags", W.ULONG), ("Value", C.c_ulonglong),
                ("Address", C.c_ulonglong), ("Register", W.ULONG), ("Scope", W.ULONG),
                ("Tag", W.ULONG), ("NameLen", W.ULONG), ("MaxNameLen", W.ULONG), ("Name", C.c_char * 1)]


class LineInfo(C.Structure):
    _fields_ = [("SizeOfStruct", W.DWORD), ("Key", C.c_void_p), ("LineNumber", W.DWORD),
                ("FileName", C.c_char_p), ("Address", C.c_ulonglong)]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--xml", type=Path, required=True)
    p.add_argument("--dll", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    root = ET.parse(a.xml).getroot().find("RuntimeProperties")
    frames = re.findall(r"(\w+)\s+(0x[0-9a-fA-F]+)\s+\+\s+([0-9a-fA-F]+)", root.findtext("PCallStack", ""))
    assert frames and frames[0][0] == "UE4SS", "Expected captured UE4SS crash"
    base = int(frames[0][1], 16)
    dbg = C.WinDLL("dbghelp", use_last_error=True)
    dbg.SymInitializeW.argtypes = [W.HANDLE, W.LPCWSTR, W.BOOL]
    dbg.SymInitializeW.restype = W.BOOL
    dbg.SymSetOptions.argtypes = [W.DWORD]
    dbg.SymSetOptions.restype = W.DWORD
    dbg.SymLoadModuleExW.argtypes = [W.HANDLE, W.HANDLE, W.LPCWSTR, W.LPCWSTR, C.c_ulonglong, W.DWORD, C.c_void_p, W.DWORD]
    dbg.SymLoadModuleExW.restype = C.c_ulonglong
    dbg.SymFromAddr.argtypes = [W.HANDLE, C.c_ulonglong, C.POINTER(C.c_ulonglong), C.POINTER(SymbolInfo)]
    dbg.SymFromAddr.restype = W.BOOL
    dbg.SymGetLineFromAddr64.argtypes = [W.HANDLE, C.c_ulonglong, C.POINTER(W.DWORD), C.POINTER(LineInfo)]
    dbg.SymGetLineFromAddr64.restype = W.BOOL
    dbg.SymCleanup.argtypes = [W.HANDLE]
    dbg.SymCleanup.restype = W.BOOL
    # Unique non-process key, fInvadeProcess=False. Local search path only.
    handle = W.HANDLE(0xAC8001)
    dbg.SymSetOptions(0x2 | 0x10 | 0x200 | 0x80000)  # UNDNAME, LOAD_LINES, FAIL_CRITICAL_ERRORS, NO_PROMPTS
    if not dbg.SymInitializeW(handle, str(a.dll.parent), False):
        raise C.WinError(C.get_last_error())
    try:
        if not dbg.SymLoadModuleExW(handle, None, str(a.dll), None, base, 0, None, 0):
            raise C.WinError(C.get_last_error())
        results = []
        for module, framebase, offset in frames:
            row = {"module": module, "rva": "0x" + offset}
            results.append(row)
            if module != "UE4SS":
                continue
            addr = int(framebase, 16) + int(offset, 16)
            buffer = C.create_string_buffer(C.sizeof(SymbolInfo) + 4096)
            symbol = C.cast(buffer, C.POINTER(SymbolInfo))
            symbol.contents.SizeOfStruct = C.sizeof(SymbolInfo)
            symbol.contents.MaxNameLen = 4096
            displacement = C.c_ulonglong()
            if dbg.SymFromAddr(handle, addr, C.byref(displacement), symbol):
                row.update(symbol=C.string_at(C.addressof(buffer) + SymbolInfo.Name.offset, symbol.contents.NameLen).decode("utf-8", "replace"),
                           displacement=displacement.value, symbol_address=hex(symbol.contents.Address))
            else:
                row["symbol_error"] = C.get_last_error()
            line = LineInfo(); line.SizeOfStruct = C.sizeof(LineInfo)
            linedisplacement = W.DWORD()
            if dbg.SymGetLineFromAddr64(handle, addr, C.byref(linedisplacement), C.byref(line)):
                row.update(file=line.FileName.decode("utf-8", "replace"), line=line.LineNumber)
        report = {"read_only": True, "source": str(a.xml), "xml_sha256": hashlib.sha256(a.xml.read_bytes()).hexdigest(),
                  "dll_sha256": hashlib.sha256(a.dll.read_bytes()).hexdigest(),
                  "error": root.findtext("ErrorMessage"), "pid": root.findtext("ProcessId"), "frames": results,
                  "limits": "Symbolicates recorded PCallStack; does not re-unwind or reproduce crash. Only local UE4SS symbols."}
        a.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps({"error": report["error"], "first_frames": results[:8], "output": str(a.output)}, indent=2))
    finally:
        dbg.SymCleanup(handle)


if __name__ == "__main__":
    main()
