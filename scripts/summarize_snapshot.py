"""Summarize a read-only UE4SS TSV; loaded assets are not active mission actors."""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path


def outer_path(full_name):
    # UE4SS full name: Class /Package.World:PersistentLevel.Object
    _, _, path = full_name.partition(" ")
    return path.partition(":")[0] if ":" in path else None


def summarize(path):
    raw = path.read_bytes()
    lines = raw.decode("utf-8-sig").splitlines()
    comments = [line for line in lines if line.startswith("#")]
    rows = list(csv.DictReader((line for line in lines if not line.startswith("#")), delimiter="\t"))
    required = {"kind", "object", "class", "Controller", "Pawn"}
    if not rows or not required.issubset(rows[0]):
        raise ValueError("Snapshot has no objects or lacks required columns")
    if any(None in row or any(value is None for value in row.values()) for row in rows):
        raise ValueError("Malformed TSV row")
    players = [row for row in rows if row["kind"] == "PlayerController"]
    inferred_worlds = sorted({outer_path(row["object"]) for row in players if outer_path(row["object"])})
    relevant = [row for row in rows if outer_path(row["object"]) in inferred_worlds]
    other = [row for row in rows if outer_path(row["object"]) not in inferred_worlds]
    return {
        "source": str(path.resolve()),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "counts_by_kind": dict(collections.Counter(row["kind"] for row in rows)),
        "scan_metadata": comments,
        "worlds_inferred_from_player_controller_outer": inferred_worlds,
        "same_outer_objects": relevant,
        "other_outer_count": len(other),
        "other_outer_classes": dict(collections.Counter(row["class"] for row in other)),
        "limitations": [
            "World grouping is inferred from object name paths, not a GetWorld identity check.",
            "FindAllOf includes loaded objects; candidates may include assets or templates.",
            "The v0.1 probe conflates absent properties and invalid/null object references.",
            "Replication flags do not establish working campaign multiplayer.",
            "No memory writes, possession, team changes or gameplay tests are performed by this parser.",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = summarize(args.snapshot)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)
