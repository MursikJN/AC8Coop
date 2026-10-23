"""Summarize a private reflection capture. Never labels it a complete native graph."""
import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path


def summarize(directory):
    results = []
    for path in sorted(directory.glob('snapshot-*.tsv')):
        counts = Counter()
        footer = None
        key_indices = []
        tables = []
        mission007 = False
        gaps = Counter()
        scope = None
        cycle = None
        with path.open(encoding='utf-8', newline='') as stream:
            for row in csv.reader(stream, delimiter='\t', quoting=csv.QUOTE_NONE):
                if len(row) != 5:
                    counts['malformed'] += 1
                    continue
                tag, owner, status, value, detail = row
                counts[tag] += 1
                mission007 |= 'Mission007' in owner or (tag == 'capture' and 'Mission007' in value)
                if tag == 'summary':
                    footer = dict(status=status, error=value, detail=detail)
                elif tag == 'scope':
                    scope = dict(query=owner, mode=status, root=value, detail=detail)
                elif tag == 'cycle':
                    cycle = owner
                elif tag == 'gap':
                    gaps[status] += 1
                elif tag == 'value' and '.KeyIndexData[' in owner:
                    key_indices.append(dict(path=owner, value=value))
                elif tag == 'table_row':
                    tables.append(dict(table=owner, key=value))
        results.append(dict(file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                            counts=dict(counts), footer=footer, gaps=dict(gaps),
                            mission007_mentioned=mission007, key_index_values=key_indices,
                            scope=scope, cycle=cycle,
                            table_rows=tables,
                            accepted_traversal=bool(footer and footer['status'] == 'traversal_finished'
                                and 'context_changed=false' in footer['detail']
                                and not counts['malformed'] and not counts['fatal']),
                            native_graph_complete=False))
    return dict(format='ac8-mission6-reflection-summary-v1', snapshots=results,
                warning='Accepted traversal may have unsupported fields or caps. Mention of Mission007 is not proof of active-world membership. No native-private graph completeness claim.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('observations', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(summarize(args.observations), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
