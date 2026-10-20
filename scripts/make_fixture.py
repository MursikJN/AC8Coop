"""Create a tiny original PE64 fixture for static analysis only; do not execute it."""
from pathlib import Path
import struct

out = Path(__file__).resolve().parents[1] / "evidence" / "return42.exe"
out.parent.mkdir(parents=True, exist_ok=True)
data = bytearray(1024)
data[:2] = b"MZ"
struct.pack_into("<I", data, 0x3c, 0x80)
data[0x80:0x84] = b"PE\0\0"
struct.pack_into("<HHIIIHH", data, 0x84, 0x8664, 1, 0, 0, 0, 0xf0, 0x22)
opt = 0x98
struct.pack_into("<H", data, opt, 0x20b)
struct.pack_into("<I", data, opt + 4, 0x200)
struct.pack_into("<II", data, opt + 16, 0x1000, 0x1000)
struct.pack_into("<Q", data, opt + 24, 0x140000000)
struct.pack_into("<II", data, opt + 32, 0x1000, 0x200)
struct.pack_into("<HH", data, opt + 40, 6, 0)
struct.pack_into("<HH", data, opt + 48, 6, 0)
struct.pack_into("<II", data, opt + 56, 0x2000, 0x200)
struct.pack_into("<H", data, opt + 68, 3)
struct.pack_into("<QQQQ", data, opt + 72, 0x100000, 0x1000, 0x100000, 0x1000)
struct.pack_into("<I", data, opt + 108, 16)
sec = opt + 0xf0
data[sec:sec + 8] = b".text\0\0\0"
struct.pack_into("<IIIIIIHHI", data, sec + 8, 6, 0x1000, 0x200, 0x200, 0, 0, 0, 0, 0x60000020)
data[0x200:0x206] = bytes.fromhex("b82a000000c3")  # mov eax,42; ret
out.write_bytes(data)
print(out)
