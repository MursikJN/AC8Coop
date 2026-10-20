"""Compare observed UE4SS class metadata without inferring behavior from names."""
import argparse
import collections
import csv
import hashlib
import json
import re
from pathlib import Path


def summarize(path):
    raw = path.read_bytes()
    lines = raw.decode("utf-8-sig").splitlines()
    rows = list(csv.DictReader((line for line in lines if not line.startswith("#")), delimiter="\t"))
    if not rows or not {"kind", "owner_class", "name", "detail"}.issubset(rows[0]):
        raise ValueError("Missing schema rows or columns")
    if any(None in row or any(value is None for value in row.values()) for row in rows):
        raise ValueError("Malformed schema TSV")
    parents = {r["owner_class"]: r["name"] for r in rows if r["kind"] == "parent"}
    members = collections.defaultdict(list)
    for row in rows:
        if row["kind"] in ("property", "function"):
            members[row["owner_class"]].append(row)

    def chain(start):
        result = []
        while start in parents and start not in result and len(result) < 64:
            result.append(start)
            start = parents[start]
        return {"classes": result, "terminal": start}

    wingmen = sorted(name for name in parents if "/AI/Wingman/" in name)
    players = sorted(name for name in parents if "/Player/Plane/" in name)
    controllers = sorted(name for name in parents if name.endswith(".LivePlayerController"))
    comparisons = []
    for wingman in wingmen:
        wc = chain(wingman)["classes"]
        for player in players:
            pc = chain(player)["classes"]
            shared = next((name for name in wc if name in pc), None)
            comparisons.append({"wingman": wingman, "player": player, "first_shared_observed_ancestor": shared})
    relevant_classes = set()
    for name in wingmen + players + controllers:
        relevant_classes.update(chain(name)["classes"])
    keywords = re.compile(r"control|input|pilot|team|squad|wing|brain|movement|flight|possess|target|damage|weapon|network|replic|^ai", re.I)
    return {
        "source": str(path.resolve()),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "class_count": len(parents),
        "metadata": [line for line in lines if line.startswith("#")],
        "wingman_chains": {name: chain(name) for name in wingmen},
        "player_chains": {name: chain(name) for name in players},
        "controller_chains": {name: chain(name) for name in controllers},
        "comparisons": comparisons,
        "name_matched_members": {name: [row for row in members[name] if keywords.search(row["name"])] for name in sorted(relevant_classes)},
        "function_fields": [row for row in rows if row["kind"] == "function_field" and row["owner_class"].split("::", 1)[0] in relevant_classes],
        "function_flags": [row for row in rows if row["kind"] == "function_flags" and row["owner_class"] in relevant_classes],
        "limitations": [
            "Only reflected metadata emitted by the probe is included; native-only members may be absent.",
            "Names indicate research candidates, not verified function behavior or ownership.",
            "Inheritance alone does not establish safe possession or compatible flight controls.",
            "No listed game function has been executed by this analysis.",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    rendered = json.dumps(summarize(args.schema), ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)
