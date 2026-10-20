import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from analyze_plane_flight_observations import summarize


def actor(x, valid=True):
    return {'identity_valid': valid, 'flags_valid': valid, 'hidden_bit80': False,
            'root': {'identity_valid': valid, 'scene_verified': valid, 'owner_matches': valid,
                     'transform_valid': valid, 'world_xyz': [x, 0, 0],
                     'flags_valid': valid, 'raw_188_191_hex': '200000000000000000'}}


def row():
    return {'schema': 'ac8-flight-observation-r4', 'units': 'UE_centimeters', 'stage': 'seed', 'pose_attempted': True,
            'source_after': actor(100), 'owned_after': actor(30100), 'requested_world': [30000, 0, 0]}


class AnalysisTests(unittest.TestCase):
    def test_world_units_and_request_mismatch(self):
        result = summarize([row()])
        stage = result['stages'][0]
        self.assertEqual(stage['source_distance_m'], 300)
        self.assertEqual(stage['request_error_m'], 1)
        self.assertTrue(stage['root_visible_bit20'])
        self.assertFalse(result['rendered_plane_verified'])

    def test_invalid_identity_cannot_report_pose_or_visibility(self):
        data = row(); data['owned_after'] = actor(30100, False)
        stage = summarize([data])['stages'][0]
        self.assertIsNone(stage['source_distance_m'])
        self.assertIsNone(stage['root_visible_bit20'])
        self.assertIsNone(stage['actor_hidden_bit80'])

    def test_nonfinite_and_wrong_schema_are_not_valid_measurements(self):
        data = row(); data['requested_world'][0] = float('nan')
        self.assertIsNone(summarize([data])['stages'][0]['request_error_m'])
        data['units'] = 'meters'
        with self.assertRaises(ValueError): summarize([data])

    def test_duplicate_stage_is_rejected(self):
        with self.assertRaises(ValueError): summarize([row(), row()])

    def test_cleanup_reference_is_model_not_a_move_call(self):
        data = row(); data['stage'] = 'before_destroy'; data['pose_attempted'] = False
        stage = summarize([data])['stages'][0]
        self.assertIsNone(stage['request_error_m'])
        self.assertEqual(stage['model_root_difference_m'], 1)
        self.assertEqual(stage['reference_kind'], 'current_model_world')


if __name__ == '__main__':
    unittest.main()
