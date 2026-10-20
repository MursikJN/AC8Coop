"""Summarize saved menu TSVs without attaching to or changing the game."""
import argparse
import csv
import hashlib
import json
from pathlib import Path


def summarize(path):
    raw = path.read_bytes()
    rows = list(csv.reader(raw.decode('utf-8-sig').splitlines(), delimiter='\t'))
    if any(len(row) != 4 for row in rows):
        raise ValueError(f'Malformed TSV: {path}')
    values = {}
    roots = {}
    summary = {}
    for kind, owner, name, value in rows:
        if kind in ('value', 'reference'):
            values.setdefault(owner, {})[name] = value
        elif kind == 'instance' and name == 'LiveMenuBase':
            roots[owner] = value
        elif kind == 'summary':
            summary[name] = value
    if not summary:
        raise ValueError(f'No completion record: {path}')
    candidates = []
    for owner, cls in roots.items():
        data = values.get(owner, {})
        if data.get('Visibility') != '0':
            continue
        candidates.append({
            'object': owner, 'class': cls, 'visibility_raw': '0',
            'page_settings': data.get('RootPageSettingsData'),
            'command_list': data.get('CommandList') or data.get('WBP_MenuCommon_MainList_000'),
            'squadron': data.get('WBP_MenuCommon_HangarSquadron_000'),
        })
    return {
        'file': path.name, 'sha256': hashlib.sha256(raw).hexdigest(),
        'capture_sequence': int(path.stem.rsplit('-', 1)[1]), 'summary': summary,
        'root_candidates_visibility_zero': candidates,
        'visibility_caveat': 'Not proof of viewport attachment or parent visibility; correlate with user report.',
    }, values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--session', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--minimum-sequence', type=int, default=3)
    args = parser.parse_args()
    captures = []
    previous_values = None
    for path in sorted(args.session.glob('menus-*.tsv')):
        if int(path.stem.rsplit('-', 1)[1]) < args.minimum_sequence:
            continue
        capture, values = summarize(path)
        if previous_values is not None:
            changes = []
            for owner, fields in values.items():
                for name, value in fields.items():
                    old = previous_values.get(owner, {}).get(name)
                    if old is not None and old != value:
                        changes.append({'object': owner, 'field': name, 'before': old, 'after': value})
            capture['changed_existing_fields'] = changes
        captures.append(capture)
        previous_values = values
    report = {
        'method': 'Saved reflected values only; no UI function calls, screenshots or code execution in target',
        'captures': captures,
        'all_complete_within_selected_queries': bool(captures) and all(
            c['summary'].get('complete_within_queries') == 'true' for c in captures),
        'limitations': ['Selection excludes unrelated widget details.',
                        'UI class names do not establish safe command invocation or network integration.',
                        'Runtime object addresses are process-scoped and must not be reused.'],
    }
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'captures': len(captures), 'complete': report['all_complete_within_selected_queries'],
                      'output': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
