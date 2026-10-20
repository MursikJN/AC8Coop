"""Arithmetic evidence tests. No process/game access, no native ABI claims."""
import copy
import math
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import plane_full_state as state


def row():
    fields = {key: {"values": [0] * count} for key, (count, _) in state.SCHEMA.items()}
    fields["0x8f8"]["values"] = [0, 0, 0, 1]
    fields["0x920"]["values"] = [0, 0, 0, 1]
    fields["0x868"]["values"] = [1]
    fields["0x1f8"]["values"] = [1, 0, 0]
    return {"fields": fields, "position_scale": {"values": [10.0]}}


def inputs():
    return {"0x58dc": 0, "0x6c8": 1., "0xfe4": .2, "0xfe8": .4,
            "0xfec": .1, "0xff0": .6, "0xff4": -.25, "0xff8": .75,
            "0x1313": 0, "0x1314": 0, "0x1315": 0, "0x13d1": 0,
            "0xffc": 0, "mode_object": None}


class FullStateTests(unittest.TestCase):
    def test_old_capture_is_explicitly_incomplete_and_never_native_ready(self):
        source = row(); del source["position_scale"]; before = copy.deepcopy(source)
        mapped = state.map_observation(source)
        self.assertEqual(source, before)
        self.assertEqual(mapped["missing"], ["runtime_position_scale", "preflight_input_sources", "same_domain_native_clock_snapshot"])
        self.assertIsNone(mapped["primary"]["0x2c"])
        self.assertIsNone(mapped["cache160"]["0x20"])
        self.assertIsNone(mapped["cache170"])
        self.assertIsNone(mapped["primary"]["0x8"])
        self.assertFalse(mapped["native_apply_ready"])

    def test_runtime_scale_changes_position_and_aux_vector_not_input_or_rotation(self):
        source = row()
        source["fields"]["0x908"]["values"] = [1, 2, 3]
        source["fields"]["0x160"]["values"] = [1, 2, 3, .1, .2, .3]
        old = state.map_observation(source)
        source["position_scale"]["values"] = [100.0]
        new = state.map_observation(source)
        self.assertEqual(new["primary"]["0x2c"], 300)
        self.assertEqual(new["cache160"]["0x20"], 300.)
        self.assertEqual(old["primary"]["0x2c"], 30)
        self.assertEqual(new["primary"]["0x38"], old["primary"]["0x38"])
        for bad in (0, -100, math.nan, math.inf):
            source["position_scale"]["values"] = [bad]
            with self.assertRaises(ValueError): state.map_observation(source)

    def test_selected_position_quantization_truncates_toward_zero(self):
        source = row()
        source["fields"]["0x908"]["values"] = [1.29, -2.89, 3.19]
        source["fields"]["0x930"]["values"] = [-4.12, 5.16, -6.19]
        p = state.map_observation(source)["primary"]
        self.assertEqual([p[k] for k in ("0x2c", "0x30", "0x34")], [31, -12, -28])
        source["fields"]["0x868"]["values"] = [0]
        p = state.map_observation(source)["primary"]
        self.assertEqual([p[k] for k in ("0x2c", "0x30", "0x34")], [-61, 41, 51])

    def test_native_quaternion_basis_mapping_without_euler_labels(self):
        for axis, expected in [(0, (-30, 0, 0)), (1, (0, -30, 0)), (2, (0, 0, 30))]:
            source = row()
            q = [0., 0., 0., math.cos(math.pi / 12)]
            q[axis] = math.sin(math.pi / 12)
            source["fields"]["0x8f8"]["values"] = q
            p = state.map_observation(source)["primary"]
            for key, angle in zip(("0x38", "0x3c", "0x40"), expected):
                self.assertAlmostEqual(p[key], angle, delta=0.00002)

    def test_atan_polynomial_quadrants_and_origin(self):
        for y, x in [(0, 0), (1, 0), (0, -1), (-1, 0), (1, 1), (-.2, -.7), (.8, -.3)]:
            self.assertAlmostEqual(state.native_atan2_approx(y, x), math.atan2(y, x), delta=0.000002)

    def test_direction_threshold_and_reordering(self):
        source = row(); source["fields"]["0x1f8"]["values"] = [3, 4, 0]
        p = state.map_observation(source)["primary"]
        self.assertEqual(p["0x20"], 0)
        self.assertAlmostEqual(p["0x24"], -.6)
        self.assertAlmostEqual(p["0x28"], .8)
        source["fields"]["0x1f8"]["values"] = [1e-6, 0, 0]
        p = state.map_observation(source)["primary"]
        self.assertAlmostEqual(p["0x24"], -1e-6)

    def test_aux_140_round_trip_against_independent_consumer_mapping(self):
        source = row(); f = source["fields"]
        f["0x128"]["values"] = [1.25, -2.5, 3.75]
        f["0x140"]["values"] = list(range(11, 18))
        f["0x108"]["values"] = [18.5]
        f["0x124"]["values"] = [1, 5, 9]
        c = state.map_observation(source)["cache140"]
        self.assertEqual((-c["0xc"], c["0x10"], c["0x8"]), (1.25, -2.5, 3.75))
        self.assertEqual([c[hex(o)] for o in range(0x14, 0x30, 4)], list(range(11, 18)))
        self.assertEqual(c["0x30"], 18.5)
        self.assertEqual((c["0x34"] >> 7, c["0x34"] & 7, (c["0x34"] >> 3) & 15), (1, 5, 9))

    def test_aux_packing_uses_byte_truncation_not_assumed_bitfield_ranges(self):
        source = row(); source["fields"]["0x124"]["values"] = [255, 254, 253]
        self.assertEqual(state.map_observation(source)["cache140"]["0x34"], 254)

    def test_aux150_and160_axis_scaling(self):
        source = row(); f = source["fields"]
        f["0x210"]["values"] = [1, 2, 3]
        f["0x38"]["values"] = [4, 5, 6]
        f["0x60"]["values"] = [7, 8]
        f["0x160"]["values"] = [9, 10, 11, math.pi/6, -math.pi/3, math.pi/2]
        m = state.map_observation(source)
        self.assertEqual(list(m["cache150"].values()), [3, -1, 2, 6, -4, 5, 7, 8])
        self.assertEqual(list(m["cache160"].values()), [110, -90, 100, -30, 60, 90])

    def test_input_clamp_and_raw_packed_flag_sources(self):
        s = inputs(); s.update({"0x6c8": 2., "0x1313": 1, "0x1314": 1, "0x13d1": 1})
        m = state.map_input(s, 1 << 9)
        self.assertEqual(m["0x8"], 1)
        self.assertEqual(m["0xc"], 1)
        self.assertEqual(m["0x10"], -.5)
        self.assertEqual(m["0x20"], 30)
        self.assertEqual(m["0x1c"], state.f32(.4))

    def test_input_override_requires_no_chain_and_has_exact_packed_four(self):
        self.assertEqual(state.map_input({"0x58dc": 1}, 0),
                         {"0x8": 0, "0xc": 0, "0x10": 0, "0x14": 0, "0x18": 0, "0x1c": 0, "0x20": 4})

    def test_input_bit0_chain_child_overrides_mode_predicate(self):
        s = inputs()
        s["mode_object"] = {"state_108": 4, "actor": None}
        self.assertEqual(state.input_bit0(s, 0), 1)
        s["mode_object"]["actor"] = {"flag_b29": 0, "child": {"flag_10": 0}}
        self.assertEqual(state.input_bit0(s, 0), 0)
        s["mode_object"]["state_108"] = 0
        s["mode_object"]["actor"]["child"]["flag_10"] = 1
        self.assertEqual(state.input_bit0(s, 0), 1)
        self.assertEqual(state.input_bit0({}, 1 << 17), 0)

    def test_missing_chain_is_not_treated_as_observed_null(self):
        s = inputs(); del s["mode_object"]
        with self.assertRaises(KeyError): state.map_input(s, 0)

    def test_native_timestamp_rebases_qpc_and_uses_signed_adjustment(self):
        origin = (16777216 + 2) * 10_000_000
        t = state.native_timestamp(qpc_ticks=30_000_000, seconds_per_tick=1e-7,
                                   clock08=origin, clock18=100_000_000, clock20=-5)
        self.assertEqual(t, 109_999_995)
        with self.assertRaises(ValueError):
            state.native_timestamp(qpc_ticks=1, seconds_per_tick=0, clock08=0, clock18=0, clock20=0)

    def test_complete_logical_snapshot_still_cannot_apply(self):
        result = state.map_observation(row(), input_sources=inputs(),
                    clock=dict(qpc_ticks=0, seconds_per_tick=1e-7, clock08=0, clock18=0, clock20=0))
        self.assertTrue(result["logical_fields_complete"])
        self.assertFalse(result["native_apply_ready"])

    def test_rejects_incomplete_nonfinite_and_out_of_range_source(self):
        source = row(); source["fields"]["0x8b0"]["values"] = [-1]
        with self.assertRaises(ValueError): state.map_observation(source)
        source = row(); source["fields"]["0x908"]["values"][0] = 1e12
        with self.assertRaises(ValueError): state.map_observation(source)
        source = row(); source["fields"]["0x128"]["values"][0] = math.nan
        with self.assertRaises(ValueError): state.map_observation(source)
        source = row(); source["fields"]["0x140"]["values"].pop()
        with self.assertRaises(ValueError): state.map_observation(source)

    def test_sampler_adapter_keeps_clock_as_interval(self):
        source = row()
        s = inputs()
        source["actor_fields"] = {k: {"values": [v]} for k, v in s.items() if k != "mode_object"}
        source["actor_fields"]["0xfe4"] = {"values": [s[k] for k in ("0xfe4", "0xfe8", "0xfec", "0xff0", "0xff4", "0xff8")]}
        source["input_chain"] = {"status": "observed_nonatomic", "actor+18c8": "0x0"}
        source["clock"] = {"status": "observed_nonatomic", "fields_08_10_18_20": {"values": [0, 0, 0, 0]},
                           "scale": {"values": [1e-7]}, "qpc_before": 100, "qpc_after": 110}
        m = state.map_initialization_observation(source)
        self.assertIsNotNone(m["cache170"])
        self.assertIsNone(m["primary"]["0x8"])
        self.assertEqual(m["missing"], ["native_clock_point_not_selected"])
        self.assertLessEqual(*m["native_timestamp_bracket"])
        source["input_chain"] = {"status": "unavailable"}
        self.assertIsNone(state.map_initialization_observation(source)["cache170"])


if __name__ == "__main__":
    unittest.main()
