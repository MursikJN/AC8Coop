import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from analyze_plane_flight_cadence import summarize


def fixture():
    rows = []
    for i in range(3):
        rows.append(dict(elapsed_us=i*16000, interval_us=16000 if i else 0,
                         state_us=100, model_us=50, pose_us=100, total_us=250,
                         source_timestamp=i+100, dt=.016, dt_clamped=False,
                         moved=True, success=True, requested=[i*100,0,0], actual=[i*100,0,0],
                         rotation_degrees=[0,179 if i%2 == 0 else -179,0]))
    return dict(schema='ac8-flight-cadence-r6', clock='QPC', time_units='microseconds',
                position_units='UE_centimeters', count=3, dropped=0, samples=rows)


class CadenceAnalysisTests(unittest.TestCase):
    def test_units_cadence_and_wrapped_rotation(self):
        r = summarize(fixture())
        self.assertEqual(r['observed_hz'], 62.5)
        self.assertEqual(r['actual_step_m']['max'], 1)
        self.assertEqual(r['wrapped_rotation_step_degrees']['max'], 2)
        self.assertEqual(r['constant_velocity_prediction_residual_m']['max'], 0)
        self.assertEqual(r['native_cost_ms']['total_us']['max'], .25)
        self.assertFalse(r['visual_smoothness_verified'])

    def test_missing_readback_is_not_zero_error(self):
        f = fixture()
        for row in f['samples']:
            row['actual'] = None
        self.assertIsNone(summarize(f)['request_error_m'])

    def test_discontinuous_pose_is_measured_without_claiming_cause(self):
        f = fixture(); f['samples'][2]['actual'][0] += 500
        r = summarize(f)
        self.assertEqual(r['request_error_m']['max'], 5)
        self.assertEqual(r['constant_velocity_prediction_residual_m']['max'], 5)
        self.assertFalse(r['visual_smoothness_verified'])

    def test_wrong_units_and_nonfinite_values_are_rejected(self):
        for key, val in [('time_units','seconds'), ('position_units','meters'), ('clock','wall')]:
            f = fixture(); f[key] = val
            with self.assertRaises(ValueError): summarize(f)
        f = fixture(); f['samples'][0]['actual'][0] = float('nan')
        with self.assertRaises(ValueError): summarize(f)

    def test_time_and_count_inconsistency_are_rejected(self):
        f = fixture(); f['samples'][1]['interval_us'] = 17000
        with self.assertRaises(ValueError): summarize(f)
        f = fixture(); f['count'] = 4097
        with self.assertRaises(ValueError): summarize(f)

    def test_empty_trace_and_failures_are_explicit(self):
        f = fixture(); f.update(count=0, samples=[])
        self.assertIsNone(summarize(f)['observed_hz'])
        f = fixture(); f['samples'][0].update(success=False, dt_clamped=True)
        r = summarize(f)
        self.assertEqual(r['failed_samples'], 1)
        self.assertEqual(r['dt_clamped_samples'], 1)


if __name__ == '__main__': unittest.main()
