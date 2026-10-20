"""Summarize an explicit capture; never silently substitute another snapshot."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser()
parser.add_argument('--session', type=Path, required=True)
parser.add_argument('--stamp', required=True)
args = parser.parse_args()
if not all(c.isdigit() or c == '-' for c in args.stamp):
    parser.error('Invalid snapshot stamp')
inputs = args.session / f'player-input-{args.stamp}.tsv'
profile = args.session / f'player-profile-{args.stamp}.tsv'
with inputs.open(encoding='utf-8') as f:
    rows = list(csv.DictReader(f, delimiter='\t'))
if not rows:
    raise SystemExit('No input samples')

def values(key):
    return [float(r[key]) for r in rows if r[key] != 'NA']

def stats(key):
    v = values(key)
    return None if not v else dict(min=min(v), max=max(v), median=statistics.median(v),
                                  nonzero_samples=sum(abs(x) > .001 for x in v))

raw = list(csv.reader(profile.open(encoding='utf-8'), delimiter='\t'))
settings = {}
references = {}
for kind, owner, field, value in raw:
    if kind == 'value':
        settings.setdefault(owner, {})[field] = value
    elif kind == 'reference':
        references.setdefault(owner, {})[field] = value

coverage = {}
for key in ['Gamepad_LeftX', 'Gamepad_LeftY', 'InputRoll', 'InputPitch']:
    v = values(key)
    coverage[key] = dict(positive_samples=sum(x > .2 for x in v),
                         negative_samples=sum(x < -.2 for x in v))
# These counts establish coverage, not flight-model equivalence or a calibrated curve.
adequate = all(c['positive_samples'] >= 10 and c['negative_samples'] >= 10
               for c in coverage.values())
mapping = {}
for source, target in [('Gamepad_LeftX', 'InputRoll'), ('Gamepad_LeftY', 'InputPitch'),
                       ('Gamepad_RightTriggerAxis', 'InputThrottle'),
                       ('Gamepad_LeftTriggerAxis', 'InputBrake')]:
    pairs = [(float(r[source]), float(r[target])) for r in rows
             if r[source] != 'NA' and r[target] != 'NA']
    mapping[source] = dict(target=target, samples=len(pairs),
                          max_absolute_difference=max(abs(a-b) for a,b in pairs),
                          active_samples=sum(abs(a) > .2 for a,b in pairs))
result = dict(
    stamp=args.stamp,
    sources={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [inputs, profile]},
    sample_count=len(rows), last_scheduled_delay_ms=float(rows[-1]['scheduled_delay_ms']),
    contiguous_samples=[int(float(r['sample'])) for r in rows] == list(range(len(rows))),
    sufficient_bidirectional_axis_coverage=adequate, axis_coverage=coverage,
    observed_input_mapping=mapping,
    statistics={k: stats(k) for k in rows[0] if k not in ['sample', 'scheduled_delay_ms']},
    object_count=sum(r[0] == 'object' for r in raw),
    read_errors=[r for r in raw if r[0] == 'read_error'],
    limits=[r for r in raw if r[0] == 'limit'],
    reflected_settings=settings, object_references=references,
    limitations=['Discovery snapshot, not a complete transferable aircraft profile.',
                 'Object identities and references are session evidence, not portable configuration.',
                 'Struct, array, curve and table contents are not captured.',
                 'Scheduled delay is not a measured frame timestamp.',
                 'Input coverage does not prove equivalent player and AI flight models.'])
output = args.session / f'player-profile-summary-{args.stamp}.json'
output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(dict(output=str(output), samples=len(rows), axis_coverage=coverage,
                     sufficient_bidirectional_axis_coverage=adequate,
                     object_count=result['object_count'], read_errors=len(result['read_errors']),
                     limits=len(result['limits'])), ensure_ascii=False, indent=2))
