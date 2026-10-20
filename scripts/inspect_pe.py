#!/usr/bin/env python3
"""Read-only PE reconnaissance: headers, imports, hash, and selected strings."""

import argparse
import hashlib
import json
import mmap
import os
import re
import struct
import sys


CATEGORY_PATTERNS = {
    "wingman_squadron_companion": (80, r"(?:wingmen?|squadrons?|companions?|wingmates?|squadmates?)"),
    "mission": (40, r"(?:missionmanager|missionobjective|missionstate|missions?|sorties|objectives?|campaigns?|checkpoints?)"),
    "controller": (30, r"(?:playercontroller|aicontroller|controller|pawn|possession|playerstate|gamemode|gamestate)"),
    "networking": (20, r"(?:dedicatedserver|listenserver|onlinesubsystem|sessioninterface|networkversion|netdriver|replication|multiplayer|matchmaking|coop|party)"),
    "engine_build": (10, r"(?:unrealengine|engineversion|buildid|buildversion|changelist|buildconfiguration)"),
}
MIN_STRING_LEN = 5


def wide_pattern(pattern):
    """Turn a simple ASCII token regex into a UTF-16LE byte regex."""
    return re.sub(r"[A-Za-z0-9]", lambda match: match.group(0) + r"\x00", pattern)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unpack(view, fmt, offset):
    size = struct.calcsize(fmt)
    require(offset >= 0 and offset + size <= len(view), "truncated PE structure")
    return struct.unpack_from(fmt, view, offset)


def c_string(view, offset, limit=4096):
    require(0 <= offset < len(view), "string offset outside file")
    end = min(len(view), offset + limit)
    raw = bytes(view[offset:end]).split(b"\0", 1)[0]
    return raw.decode("ascii", errors="replace")


def inspect(path):
    size = os.path.getsize(path)
    digest = sha256_file(path)
    with open(path, "rb") as stream:
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as view:
            require(len(view) >= 64 and view[:2] == b"MZ", "missing DOS MZ header")
            pe_off = unpack(view, "<I", 0x3C)[0]
            require(view[pe_off:pe_off + 4] == b"PE\0\0", "missing PE signature")
            coff = pe_off + 4
            machine, nsections, timestamp, symptr, nsyms, opt_size, chars = unpack(view, "<HHIIIHH", coff)
            opt = coff + 20
            magic = unpack(view, "<H", opt)[0]
            require(magic == 0x20B, "input is not PE32+ / PE64")
            entry_rva = unpack(view, "<I", opt + 16)[0]
            image_base = unpack(view, "<Q", opt + 24)[0]
            section_alignment, file_alignment = unpack(view, "<II", opt + 32)
            size_image, size_headers = unpack(view, "<II", opt + 56)
            n_dirs = unpack(view, "<I", opt + 108)[0]
            dirs_off = opt + 112
            dirs = []
            for i in range(min(n_dirs, 16)):
                rva, length = unpack(view, "<II", dirs_off + i * 8)
                dirs.append((rva, length))
            sections = []
            sec_off = opt + opt_size
            for i in range(nsections):
                off = sec_off + i * 40
                name_b, vsize, va, raw_size, raw_ptr, reloc, line, nreloc, nline, flags = unpack(view, "<8sIIIIIIHHI", off)
                sections.append({
                    "name": name_b.rstrip(b"\0").decode("ascii", errors="replace"),
                    "virtual_address": va, "virtual_size": vsize,
                    "raw_offset": raw_ptr, "raw_size": raw_size,
                    "characteristics": f"0x{flags:08x}",
                })

            def rva_to_offset(rva):
                if rva < size_headers and rva < len(view):
                    return rva
                for section in sections:
                    start = section["virtual_address"]
                    span = max(section["virtual_size"], section["raw_size"])
                    if start <= rva < start + span:
                        delta = rva - start
                        if delta < section["raw_size"]:
                            result = section["raw_offset"] + delta
                            if result < len(view):
                                return result
                return None

            imports = []
            import_rva, import_len = dirs[1] if len(dirs) > 1 else (0, 0)
            imp_off = rva_to_offset(import_rva) if import_rva else None
            if imp_off is not None:
                max_desc = min(import_len // 20 if import_len else 4096, 4096)
                for i in range(max_desc):
                    desc = unpack(view, "<IIIII", imp_off + i * 20)
                    oft, _, _, name_rva, first = desc
                    if not any(desc):
                        break
                    noff = rva_to_offset(name_rva)
                    dll = c_string(view, noff) if noff is not None else None
                    imports.append({"dll": dll})

            category_counts = {name: 0 for name in CATEGORY_PATTERNS}
            category_samples = {name: [] for name in CATEGORY_PATTERNS}
            compiled_categories = {
                name: (limit, re.compile(pattern.encode("ascii"), re.I),
                       re.compile(wide_pattern(pattern).encode("ascii"), re.I))
                for name, (limit, pattern) in CATEGORY_PATTERNS.items()
            }
            broad_ascii = re.compile(b"|".join(b"(?:" + v[1].pattern + b")" for v in compiled_categories.values()), re.I)
            broad_wide = re.compile(b"|".join(b"(?:" + v[2].pattern + b")" for v in compiled_categories.values()), re.I)

            def file_rva(offset):
                for section in sections:
                    start = section["raw_offset"]
                    if start <= offset < start + section["raw_size"]:
                        return section["virtual_address"] + offset - start
                return None

            def add_category_sample(name, match, string_start, string_end, encoding):
                limit = compiled_categories[name][0]
                category_counts[name] += 1
                samples = category_samples[name]
                if len(samples) >= limit:
                    return
                # Keep only a bounded context around the category hit, even if the
                # underlying printable string is unusually large.
                context_start = max(string_start, match.start() - 160)
                context_end = min(string_end, match.end() + 160)
                raw = bytes(view[context_start:context_end])
                if encoding == "utf16le":
                    if len(raw) % 2:
                        raw = raw[:-1]
                    snippet = raw.decode("utf-16le", errors="replace")
                else:
                    snippet = raw.decode("utf-8", errors="replace")
                rva = file_rva(string_start)
                samples.append({"text": snippet[:512], "encoding": encoding,
                                "file_offset": string_start, "matched_offset": match.start(),
                                "rva": rva, "va": image_base + rva if rva is not None else None})

            def is_word(value):
                return (48 <= value <= 57) or (65 <= value <= 90) or (97 <= value <= 122) or value == 95

            def bounded_match(pattern, string_start, string_end, encoding):
                for match in pattern.finditer(view, string_start, string_end):
                    if encoding == "ascii":
                        left_word = match.start() > string_start and is_word(view[match.start() - 1])
                        right_word = match.end() < string_end and is_word(view[match.end()])
                    else:
                        left_word = (match.start() - 2 >= string_start and
                                     is_word(struct.unpack_from("<H", view, match.start() - 2)[0]))
                        right_word = (match.end() + 2 <= string_end and
                                      is_word(struct.unpack_from("<H", view, match.end())[0]))
                    if not left_word and not right_word:
                        return match
                return None

            ascii_re = re.compile(rb"[\x20-\x7e]{%d,}" % MIN_STRING_LEN)
            wide_re = re.compile(rb"(?:[\x20-\x7e]\x00){%d,}" % MIN_STRING_LEN)
            # `finditer` scans the mmap directly, so string starts and ends may
            # cross arbitrary offsets without chunk-boundary loss or file copies.
            for regex, broad, encoding in ((ascii_re, broad_ascii, "ascii"), (wide_re, broad_wide, "utf16le")):
                for string_match in regex.finditer(view):
                    start, end = string_match.span()
                    broad_hit = broad.search(view, start, end)
                    if broad_hit is None:
                        continue
                    for name, (limit, ascii_pattern, wide_token_pattern) in compiled_categories.items():
                        pattern = ascii_pattern if encoding == "ascii" else wide_token_pattern
                        match = bounded_match(pattern, start, end, encoding)
                        if match is not None:
                            add_category_sample(name, match, start, end, encoding)

            return {
                "path": os.path.abspath(path), "file_size": size, "sha256": digest,
                "format": "PE32+", "machine": f"0x{machine:04x}",
                "sections_count": nsections, "timestamp": timestamp,
                "entrypoint_rva": entry_rva,
                "entrypoint_va": image_base + entry_rva if entry_rva else None,
                "image_base": image_base, "section_alignment": section_alignment,
                "file_alignment": file_alignment, "size_of_image": size_image,
                "size_of_headers": size_headers, "characteristics": f"0x{chars:04x}",
                "sections": sections, "imports": imports,
                "string_scan": {
                    "full_scan_completed": True,
                    "minimum_string_length": MIN_STRING_LEN,
                    "category_patterns": {name: {"regex": pattern, "sample_limit": limit}
                                          for name, (limit, pattern) in CATEGORY_PATTERNS.items()},
                    "category_match_counts": category_counts,
                    "category_samples": category_samples,
                    "category_samples_truncated": {name: category_counts[name] > len(category_samples[name])
                                                   for name in CATEGORY_PATTERNS},
                },
                "interpretation_limit": "String matches identify embedded text only; they do not prove code reachability, execution, multiplayer behavior, or a usable feature.",
            }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="path to a PE32+ executable")
    parser.add_argument("--output", required=True, help="JSON output path")
    args = parser.parse_args()
    result = inspect(args.input)
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8", newline="\n") as out:
        json.dump(result, out, indent=2, ensure_ascii=False)
        out.write("\n")
    print(json.dumps({"output": os.path.abspath(args.output), "file_size": result["file_size"],
                      "sha256": result["sha256"], "sections": len(result["sections"]),
                      "import_modules": len(result["imports"]),
                      "category_match_counts": result["string_scan"]["category_match_counts"]}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, struct.error) as exc:
        print(f"inspect_pe: {exc}", file=sys.stderr)
        sys.exit(2)
