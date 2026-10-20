"""Summarize R4 read-only observations; never infer that a plane was rendered."""
import argparse
import json
import math
from pathlib import Path


def finite_vector(value):
    return (isinstance(value, list) and len(value) == 3
            and all(type(x) in (int, float) and math.isfinite(x) for x in value))


def actor_position(actor):
    root = actor.get('root', {})
    if (actor.get('identity_valid') and root.get('identity_valid')
            and root.get('scene_verified') and root.get('owner_matches')
            and root.get('transform_valid') and finite_vector(root.get('world_xyz'))):
        return root['world_xyz']
    return None


def distance_m(a, b):
    if finite_vector(a) and finite_vector(b):
        return math.dist(a, b) / 100
    return None


def summarize(rows):
    stages = []
    seen = set()
    for row in rows:
        if row.get('schema') != 'ac8-flight-observation-r4' or row.get('units') != 'UE_centimeters':
            raise ValueError('Unexpected observation schema or units')
        stage = row.get('stage')
        if stage not in {'seed', 't1', 't5', 't10', 'before_destroy'} or stage in seen:
            raise ValueError('Unknown or duplicate observation stage')
        seen.add(stage)
        source, owned = row.get('source_after', {}), row.get('owned_after', {})
        source_pos, owned_pos = actor_position(source), actor_position(owned)
        requested = row.get('requested_world')
        root = owned.get('root', {})
        flags = root.get('raw_188_191_hex')
        visible_bit = None
        if (owned.get('identity_valid') and root.get('identity_valid')
                and root.get('scene_verified') and root.get('owner_matches')
                and root.get('flags_valid') and isinstance(flags, str) and len(flags) == 18):
            visible_bit = bool(bytes.fromhex(flags)[0] & 0x20)
        stages.append({
            'stage': stage, 'elapsed_ms': row.get('elapsed_ms'),
            'pose_attempted': row.get('pose_attempted'), 'move_returned': row.get('move_returned'),
            'source_world_cm': source_pos, 'owned_world_cm': owned_pos,
            'requested_world_cm': requested if finite_vector(requested) else None,
            'reference_kind': ('move_argument' if row.get('pose_attempted') else 'current_model_world'),
            'request_error_m': (distance_m(owned_pos, requested) if row.get('pose_attempted') else None),
            'model_root_difference_m': (distance_m(owned_pos, requested) if not row.get('pose_attempted') else None),
            'source_distance_m': distance_m(owned_pos, source_pos),
            'source_to_owned_delta_m': ([ (b-a)/100 for a,b in zip(source_pos, owned_pos)]
                                      if source_pos is not None and owned_pos is not None else None),
            'actor_hidden_bit80': (owned.get('hidden_bit80') if owned.get('identity_valid')
                                   and owned.get('flags_valid') else None),
            'root_visible_bit20': visible_bit,
        })
    return {'schema': 'ac8-flight-observation-analysis-r4', 'sample_count': len(stages),
            'missing_stages': sorted({'seed', 't1', 't5', 't10', 'before_destroy'} - seen),
            'rendered_plane_verified': False,
            'limits': 'Coordinates and flags do not prove camera visibility, mesh readiness or rendering.',
            'stages': stages}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    args = parser.parse_args()
    if args.input.stat().st_size > 11 * 1024 * 1024:
        raise ValueError('Observation file exceeds five bounded R4 frames')
    rows = [json.loads(line) for line in args.input.read_text(encoding='utf-8-sig').splitlines() if line.strip()]
    if len(rows) > 5:
        raise ValueError('More than five observation frames')
    print(json.dumps(summarize(rows), ensure_ascii=False, indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
