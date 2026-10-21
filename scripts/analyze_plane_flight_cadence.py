"""Analyze bounded R6 cadence/pose samples; these metrics do not prove visual smoothness."""
import argparse
import json
import math
from pathlib import Path


def finite_vec(value):
    return isinstance(value, list) and len(value) == 3 and all(type(v) in (int, float) and math.isfinite(v) for v in value)


def distribution(values):
    if not values:
        return None
    ordered = sorted(values)
    return {'min': ordered[0], 'mean': sum(ordered) / len(ordered),
            'p50': ordered[(len(ordered) - 1) // 2],
            'p95': ordered[math.ceil(len(ordered) * .95) - 1], 'max': ordered[-1]}


def summarize(data):
    if data.get('schema') != 'ac8-flight-cadence-r6' or data.get('clock') != 'QPC' or data.get('time_units') != 'microseconds' or data.get('position_units') != 'UE_centimeters':
        raise ValueError('Unsupported cadence schema/units/clock')
    rows = data.get('samples')
    if not isinstance(rows, list) or len(rows) > 4096 or type(data.get('count')) is not int or data['count'] != len(rows):
        raise ValueError('Invalid bounded sample count')
    if type(data.get('dropped')) is not int or data['dropped'] < 0:
        raise ValueError('Invalid dropped count')
    times = ('elapsed_us', 'interval_us', 'state_us', 'model_us', 'pose_us', 'total_us', 'source_timestamp')
    errors, steps, rotations, residuals = [], [], [], []
    for i, row in enumerate(rows):
        if any(type(row.get(k)) is not int or row[k] < 0 for k in times):
            raise ValueError('Invalid time sample')
        if i and (row['elapsed_us'] <= rows[i-1]['elapsed_us'] or row['interval_us'] != row['elapsed_us'] - rows[i-1]['elapsed_us']):
            raise ValueError('Nonmonotonic or inconsistent cadence')
        if type(row.get('dt')) not in (float, int) or not math.isfinite(row['dt']) or not 0 < row['dt'] <= .100001:
            raise ValueError('Invalid native dt')
        if any(type(row.get(k)) is not bool for k in ('moved', 'success', 'dt_clamped')):
            raise ValueError('Missing motion status')
        for key in ('requested', 'rotation_degrees', 'actual'):
            if row.get(key) is not None and not finite_vec(row[key]):
                raise ValueError('Invalid pose vector')
        if row['moved'] and (not finite_vec(row.get('requested')) or not finite_vec(row.get('rotation_degrees'))):
            raise ValueError('Move lacks requested pose')
        if finite_vec(row.get('actual')) and row['moved']:
            errors.append(math.dist(row['actual'], row['requested']) / 100)
        if i and finite_vec(row.get('actual')) and finite_vec(rows[i-1].get('actual')):
            steps.append(math.dist(row['actual'], rows[i-1]['actual']) / 100)
        if i and row['moved'] and rows[i-1]['moved']:
            rotations.append(max(abs((b-a+180) % 360 - 180) for a,b in zip(rows[i-1]['rotation_degrees'], row['rotation_degrees'])))
        if i >= 2 and all(finite_vec(r.get('actual')) for r in rows[i-2:i+1]):
            a, b = rows[i-2:i]
            ratio = row['interval_us'] / b['interval_us']
            predicted = [y + (y-x) * ratio for x,y in zip(a['actual'], b['actual'])]
            residuals.append(math.dist(row['actual'], predicted) / 100)
    intervals = [r['interval_us']/1000 for r in rows[1:]]
    costs = {key: distribution([r[key]/1000 for r in rows]) for key in ('state_us', 'model_us', 'pose_us', 'total_us')}
    return {'schema': 'ac8-flight-cadence-analysis-r6', 'count': len(rows), 'dropped': data['dropped'],
            'cadence_ms': distribution(intervals),
            'observed_hz': 1000 / (sum(intervals)/len(intervals)) if intervals else None,
            'native_cost_ms': costs, 'failed_samples': sum(not r['success'] for r in rows),
            'dt_clamped_samples': sum(r['dt_clamped'] for r in rows),
            'distinct_source_timestamps': len({r['source_timestamp'] for r in rows}),
            'request_error_m': distribution(errors), 'actual_step_m': distribution(steps),
            'wrapped_rotation_step_degrees': distribution(rotations),
            'constant_velocity_prediction_residual_m': distribution(residuals),
            'visual_smoothness_verified': False,
            'limits': 'Large pose residuals may reflect maneuvers or corrections. Visual shaking requires user observation; sparse samples and missing readbacks are not proof of smoothness.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    args = parser.parse_args()
    if args.input.stat().st_size > 2 * 1024 * 1024 + 1:
        raise ValueError('Cadence file exceeds native serializer bound')
    print(json.dumps(summarize(json.loads(args.input.read_text(encoding='utf-8-sig'))), indent=2, allow_nan=False))
