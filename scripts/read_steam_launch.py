#!/usr/bin/env python3
"""Read one app's public launch metadata from Steam appinfo.vdf v41."""

import argparse
import hashlib
import json
import os
import re
import struct
import sys
from datetime import datetime, timezone


MAGIC_V41 = 0x07564429
TARGET_APPID = 2288340
MAX_STRING_TABLE = 2_000_000
MAX_RECORD_SIZE = 128 * 1024 * 1024


def read_exact(stream, count):
    data = stream.read(count)
    if len(data) != count:
        raise ValueError("unexpected end of appinfo.vdf")
    return data


def read_cstring(stream, end):
    out = bytearray()
    while stream.tell() < end:
        byte = stream.read(1)
        if not byte or byte == b"\0":
            return out.decode("utf-8", errors="replace")
        out += byte
        if len(out) > 4 * 1024 * 1024:
            raise ValueError("string exceeds safety limit")
    raise ValueError("unterminated string")


class KVReader:
    def __init__(self, data, strings):
        self.data = data
        self.pos = 0
        self.strings = strings

    def take(self, count):
        if count < 0 or self.pos + count > len(self.data):
            raise ValueError("binary KV value extends past app record")
        value = self.data[self.pos:self.pos + count]
        self.pos += count
        return value

    def unpack(self, fmt):
        size = struct.calcsize(fmt)
        return struct.unpack(fmt, self.take(size))

    def key(self):
        (index,) = self.unpack("<i")
        if index < 0 or index >= len(self.strings):
            raise ValueError(f"invalid string-table key index {index}")
        return self.strings[index]

    def cstring(self):
        end = self.data.find(b"\0", self.pos)
        if end < 0:
            raise ValueError("unterminated KV string")
        value = self.data[self.pos:end].decode("utf-8", errors="replace")
        self.pos = end + 1
        return value

    def object_entries(self, depth=0):
        if depth > 128:
            raise ValueError("KV nesting exceeds safety limit")
        entries = []
        while True:
            (kind,) = self.unpack("<B")
            if kind in (8, 11):
                return entries
            key = self.key()
            if kind == 0:
                value = self.object_entries(depth + 1)
            elif kind == 1:
                value = self.cstring()
            elif kind == 2:
                (value,) = self.unpack("<i")
            elif kind == 3:
                (value,) = self.unpack("<f")
            elif kind == 4:
                (value,) = self.unpack("<I")
            elif kind == 5:
                (length,) = self.unpack("<i")
                if length < 0 or length > 16 * 1024 * 1024:
                    raise ValueError("invalid wide-string length")
                value = self.take(length * 2).decode("utf-16le", errors="replace").split("\0", 1)[0]
            elif kind == 6:
                (value,) = self.unpack("<I")
            elif kind == 7:
                (value,) = self.unpack("<Q")
            elif kind == 9:
                (length,) = self.unpack("<I")
                if length > MAX_RECORD_SIZE:
                    raise ValueError("binary blob exceeds safety limit")
                self.take(length)
                value = {"binary_blob_bytes": length}
            elif kind == 10:
                (value,) = self.unpack("<q")
            else:
                raise ValueError(f"unsupported binary KV node type {kind}")
            entries.append((key, value))


def find_all(entries, key):
    return [value for name, value in entries if name == key]


def first(entries, key, default=None):
    found = find_all(entries, key)
    return found[0] if found else default


def first_ci(entries, key, default=None):
    key = key.casefold()
    return next((value for name, value in entries if name.casefold() == key), default)


def vdf_pairs(text):
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|//[^\r\n]*|[{}]|[^\s{}"]+', text)
    tokens = [t for t in tokens if not t.startswith("//")]
    return _vdf_pairs_tokens(tokens, 0)


def _vdf_pairs_tokens(tokens, position, nested=False):
    pairs = []

    def decode(token):
        if token.startswith('"'):
            return re.sub(r'\\(["\\])', r'\1', token[1:-1])
        return token

    while position < len(tokens):
        if tokens[position] == "}":
            if not nested:
                raise ValueError("unexpected closing brace in appmanifest")
            return pairs, position + 1
        key = decode(tokens[position])
        position += 1
        if position >= len(tokens):
            raise ValueError("missing appmanifest value")
        if tokens[position] == "{":
            value, position = _vdf_pairs_tokens(tokens, position + 1, True)
        else:
            value = decode(tokens[position])
            position += 1
        pairs.append((key, value))
    if nested:
        raise ValueError("unterminated appmanifest object")
    return pairs, position


def read_installed_branch(path, appid, public_branch):
    if not path or not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8-sig", errors="replace") as stream:
        pairs, _ = vdf_pairs(stream.read())
    state = first_ci(pairs, "AppState", [])
    if first_ci(state, "appid") != str(appid):
        raise ValueError("appmanifest appid does not match requested appid")
    build_id = first_ci(state, "buildid")
    user_config = first_ci(state, "UserConfig", [])
    beta_key = first_ci(user_config, "BetaKey")
    public_build = (public_branch or {}).get("buildid")
    same_public_build = build_id is not None and str(build_id) == str(public_build)
    no_beta_key = beta_key in (None, "")
    return {
        "appmanifest_appid": int(first_ci(state, "appid")),
        "installed_buildid": int(build_id) if build_id is not None else None,
        "userconfig_betakey_present": not no_beta_key,
        "userconfig_betakey": beta_key,
        "matches_cached_public_buildid": same_public_build,
        "classification": "consistent_with_public_branch" if same_public_build and no_beta_key else "not_established_as_public",
        "basis": "Installed manifest buildid matches appinfo public branch buildid and no UserConfig BetaKey is recorded." if same_public_build and no_beta_key else "Installed manifest does not provide both a matching public buildid and an absent BetaKey.",
    }


def parse_appinfo(path, appid, manifest_path=None):
    file_hash = hashlib.sha256()
    with open(path, "rb") as stream:
        while True:
            chunk = stream.read(4 * 1024 * 1024)
            if not chunk:
                break
            file_hash.update(chunk)

    with open(path, "rb") as stream:
        magic, universe = struct.unpack("<II", read_exact(stream, 8))
        if magic != MAGIC_V41:
            raise ValueError(f"expected appinfo v41 magic 0x{MAGIC_V41:08x}, got 0x{magic:08x}")
        (string_offset,) = struct.unpack("<Q", read_exact(stream, 8))
        file_size = os.path.getsize(path)
        if string_offset < 16 or string_offset + 4 > file_size:
            raise ValueError("string-table offset is outside file")
        after_header = stream.tell()
        stream.seek(string_offset)
        (string_count,) = struct.unpack("<I", read_exact(stream, 4))
        if string_count > MAX_STRING_TABLE:
            raise ValueError(f"string table count exceeds limit: {string_count}")
        strings = [read_cstring(stream, file_size) for _ in range(string_count)]
        string_table_end = stream.tell()
        if string_table_end > file_size:
            raise ValueError("string table extends past file")
        stream.seek(after_header)

        records_seen = 0
        while stream.tell() + 4 <= file_size:
            record_start = stream.tell()
            (current_appid,) = struct.unpack("<I", read_exact(stream, 4))
            if current_appid == 0:
                raise ValueError(f"target appid {appid} not found before footer")
            (record_size,) = struct.unpack("<I", read_exact(stream, 4))
            record_data_start = stream.tell()
            record_end = record_data_start + record_size
            if record_size > MAX_RECORD_SIZE or record_end > file_size:
                raise ValueError(f"invalid app record size for appid {current_appid}")
            records_seen += 1
            if current_appid != appid:
                stream.seek(record_end)
                continue

            if record_size < 60:
                raise ValueError("target app record is too short for v41 metadata")
            info_state, updated = struct.unpack("<II", read_exact(stream, 8))
            stream.seek(8 + 20, os.SEEK_CUR)  # omit product token and protocol hash
            (change_number,) = struct.unpack("<I", read_exact(stream, 4))
            stream.seek(20, os.SEEK_CUR)  # omit binary-VDF integrity hash
            kv_data = read_exact(stream, record_end - stream.tell())
            reader = KVReader(kv_data, strings)
            root = reader.object_entries()
            if reader.pos != len(kv_data):
                raise ValueError("unexpected bytes after target app KV root")
            public_branch = extract_public_branch(root)
            launches = extract_launch(root)
            installed_branch = read_installed_branch(manifest_path, appid, public_branch)
            return {
                "source": os.path.abspath(path),
                "source_sha256": file_hash.hexdigest(),
                "appinfo_format": "0x07564429 (v41)",
                "steam_universe": universe,
                "target_appid": appid,
                "target_record_offset": record_start,
                "target_record_size": record_size,
                "records_skipped_before_target": records_seen - 1,
                "app_info_state": info_state,
                "app_last_updated_utc": datetime.fromtimestamp(updated, timezone.utc).isoformat(),
                "app_change_number": change_number,
                "app_common_name": first(first(first(root, "appinfo", root), "common", []), "name"),
                "public_config_launch": launches,
                "public_branch_metadata": public_branch,
                "installed_branch_evidence": installed_branch,
                "no_eac_launch_accessibility": assess_no_eac(launches, public_branch, installed_branch),
                "credential_and_non_target_data": "App token, hashes, and all other app records are omitted.",
                "interpretation_limit": "Cached appinfo describes Steam-published metadata; it does not prove the installed client presents or permits a launch choice at runtime.",
            }
        raise ValueError(f"target appid {appid} not found")


def extract_launch(root):
    appinfo = first(root, "appinfo", root)
    config = first(appinfo, "config", [])
    launches = first(config, "launch", [])
    result = []
    for index, value in launches:
        if not isinstance(value, list):
            continue
        entry_config = first(value, "config", [])
        restrictions = {}
        for key, val in entry_config:
            if key.lower() in {"oslist", "osarch", "osver", "ostype", "betakey", "branch", "realm", "language", "ownsdlc", "controller"}:
                restrictions[key] = val
        result.append({
            "launch_index": index,
            "metadata": {key: value for key, value in value if key.lower() != "config"},
            "restrictions": restrictions,
        })
    return result


def extract_public_branch(root):
    appinfo = first(root, "appinfo", root)
    branches = first(first(appinfo, "depots", []), "branches", [])
    public = first(branches, "public")
    if not isinstance(public, list):
        return None
    allowed = {"buildid", "timeupdated", "description", "pwdrequired", "betakeyrequired", "lcsrequired", "allowrollback"}
    return {key: value for key, value in public if key.lower() in allowed}


def assess_no_eac(launches, public_branch, installed):
    selected = next((entry for entry in launches
                     if "no eac" in str(entry["metadata"].get("description", "")).lower()), None)
    if selected is None:
        return {"status": "not_found_in_cached_launch_metadata"}
    restrictions = selected["restrictions"]
    beta_keys = restrictions.get("BetaKey", restrictions.get("betakey"))
    public_build = (public_branch or {}).get("buildid")
    if beta_keys and installed and installed.get("classification") == "consistent_with_public_branch":
        status = "restricted_away_from_installed_public_branch"
        reason = "This launch entry declares BetaKey restrictions, while the installed manifest matches the cached public build and records no UserConfig BetaKey."
    elif beta_keys:
        status = "beta_restricted_installed_branch_unconfirmed"
        reason = "This launch entry declares BetaKey restrictions, but the installed branch could not be confirmed as public."
    else:
        status = "no_beta_restriction_in_cached_entry"
        reason = "No BetaKey restriction is present in the cached launch entry."
    return {
        "status": status,
        "launch_index": selected["launch_index"],
        "description": selected["metadata"].get("description"),
        "executable": selected["metadata"].get("executable"),
        "arguments": selected["metadata"].get("arguments"),
        "allowed_beta_keys": beta_keys,
        "cached_public_buildid": public_build,
        "installed_branch_classification": (installed or {}).get("classification"),
        "reason": reason,
        "runtime_limit": "This is a metadata-based Steam launch-selector assessment, not a live Steam UI check.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Steam appcache/appinfo.vdf path")
    parser.add_argument("--appid", type=int, default=TARGET_APPID)
    parser.add_argument("--manifest", help="optional installed appmanifest_<appid>.acf for branch cross-check")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = parse_appinfo(args.input, args.appid, args.manifest)
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8", newline="\n") as out:
        json.dump(result, out, indent=2, ensure_ascii=False)
        out.write("\n")
    print(json.dumps({"output": os.path.abspath(args.output), "appid": args.appid,
                      "name": result["app_common_name"],
                      "launch_entries": len(result["public_config_launch"]),
                      "public_branch": result["public_branch_metadata"],
                      "installed_branch": result["installed_branch_evidence"],
                      "no_eac_assessment": result["no_eac_launch_accessibility"]["status"]}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, struct.error) as exc:
        print(f"read_steam_launch: {exc}", file=sys.stderr)
        sys.exit(2)
