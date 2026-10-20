"""Failure-injection tests of offline first-state requests, not a native test."""
from dataclasses import replace, FrozenInstanceError
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import plane_first_state as first
from plane_motion_wire import Binding
from plane_spawn_rollback import Identity, Observation, Rollback, Seen


def source_row():
    fields = {key: {"values": [0] * count} for key, (count, _) in first.full.SCHEMA.items()}
    fields["0x868"]["values"] = [1]
    fields["0x8f8"]["values"] = [0., 0., 0., 1.]
    fields["0x920"]["values"] = [0., 0., 0., 1.]
    fields["0x908"]["values"] = [1., 2., 3.]
    fields["0x1f8"]["values"] = [1., 0., 0.]
    return {"index": 0, "fields": fields,
            "actor_fields": {"0x58dc": {"values": [1]}},  # proven override, no unavailable defaults
            "input_chain": {"status": "unavailable"},
            "clock": {"status": "observed_nonatomic", "qpc_before": 1000, "qpc_after": 1100,
                      "fields_08_10_18_20": {"values": [0, 0, 123456, 0]}, "scale": {"values": [1e-7]}}}


class FirstStateTests(unittest.TestCase):
    def setUp(self):
        self.binding = Binding(11, 22, 33, 44, 55)
        self.capture = first.Capture("sender-session-instance", "a" * 64, 0)
        self.scale = first.ScaleEvidence(self.capture.process_instance, 100., "b" * 64)
        self.config = "c" * 64
        self.snapshot = first.stage_capture(source_row(), self.binding, self.capture, self.config, scale_evidence=self.scale)
        self.rollback = Rollback(7, 55)
        self.plane, self.network = Identity(7, 101, 21), Identity(7, 102, 22)
        self.rollback.acquired("plane", self.plane)
        self.rollback.acquired("network", self.network)
        self.stage = first.FirstState(self.snapshot, self.rollback, "receiver-session-instance")
        self.guard = first.Guard("receiver-session-instance", self.plane, self.network, self.config,
                                 "owned-barrier-1", 5, True, True, True, True, True, True, 100., 2, "fallback_7d6f0c0")
        self.clock = first.ReceiverClockPoint(self.guard.receiver_process, self.guard.barrier_token, 5,
                                             5000, 1e-7, 167772160000000, 9000, 0)

    def assert_retired(self):
        self.assertFalse(self.stage.native_updates_enabled)
        self.assertFalse(self.stage.motion_gate.ready)
        self.assertTrue(self.stage.motion_gate.retired)
        self.assertTrue(self.rollback.retired)

    def test_real_clock_bracket_is_not_a_receiver_clock_point(self):
        result = self.stage.prepare_request(self.guard)
        self.assertEqual(result["blocked"], "native_point_unselected")
        self.assertFalse(result["executed"])
        self.assertIsNone(self.stage.commit)
        self.assertFalse(self.stage.motion_gate.ready)

    def test_sender_clock_point_and_stale_barrier_point_are_rejected(self):
        with self.assertRaises(ValueError):
            self.stage.prepare_request(self.guard, replace(self.clock, receiver_process=self.capture.process_instance))
        self.assert_retired()

    def test_clock_revision_must_match_current_receiver_observation(self):
        with self.assertRaises(ValueError):
            self.stage.prepare_request(self.guard, replace(self.clock, observation_revision=4))
        self.assert_retired()

    def test_snapshot_is_fixed_one_row_and_source_mutation_cannot_mix_state(self):
        row = source_row()
        frozen = first.stage_capture(row, self.binding, self.capture, self.config, scale_evidence=self.scale)
        before = frozen.sha256
        row["fields"]["0x908"]["values"][0] = 999
        self.assertEqual(frozen.sha256, before)
        with self.assertRaises(FrozenInstanceError): frozen.document = b"changed"
        with self.assertRaises(ValueError):
            first.stage_capture(row, self.binding, replace(self.capture, row_index=1), self.config, scale_evidence=self.scale)

    def test_runtime_scale_never_defaults_to_ten_or_another_process(self):
        with self.assertRaises(ValueError):
            first.stage_capture(source_row(), self.binding, self.capture, self.config)
        with self.assertRaises(ValueError):
            first.stage_capture(source_row(), self.binding, self.capture, self.config,
                                scale_evidence=replace(self.scale, process_instance="other"))
        row = source_row(); row["position_scale"] = {"values": [100.]}
        self.assertEqual(json.loads(first.stage_capture(row, self.binding, self.capture, self.config).document)
                         ["movement"]["primary"]["0x2c"], 300)

    def test_incomplete_input_cannot_stage_even_with_pose_and_clock(self):
        row = source_row(); row["actor_fields"] = {"0x58dc": {"values": [0]}}
        with self.assertRaises(ValueError):
            first.stage_capture(row, self.binding, self.capture, self.config, scale_evidence=self.scale)

    def test_full_scalar_plan_excludes_dynamicarrays_headers_vtables(self):
        plan = self.stage.prepare_request(self.guard, self.clock)
        self.assertEqual(len(plan.writes), 46)
        by_target = {}
        for scalar in plan.writes:
            by_target.setdefault(scalar.target, {})[scalar.offset] = scalar.value
        self.assertEqual(set(by_target), {"primary", "cache140", "cache150", "cache160", "cache170", "owned_plane"})
        self.assertEqual(by_target["primary"][8], 14000)
        self.assertEqual(by_target["owned_plane"][0x3c38], 14000)
        self.assertEqual(by_target["primary"][0x2c], 300)
        self.assertEqual(set(by_target["primary"]), {8, *range(0x20, 0x4c, 4)})
        self.assertEqual(by_target["cache170"][0x20], 4)
        self.assertFalse(self.stage.motion_gate.ready)

    def test_every_unverified_gate_retires_before_commit(self):
        for field in ("identities_current", "configuration_current", "update_barrier_held",
                      "cache_ownership_verified", "delta_arrays_empty_verified", "models_configured"):
            with self.subTest(field=field):
                self.setUp()
                with self.assertRaises(ValueError): self.stage.prepare_request(replace(self.guard, **{field: False}), self.clock)
                self.assert_retired()
                self.assertIsNone(self.stage.commit)

    def test_identity_config_and_plane_generation_changes_retire(self):
        for changed in (replace(self.guard, plane=Identity(7, 101, 99)),
                        replace(self.guard, configuration_digest="d" * 64),
                        replace(self.guard, receiver_process="different-process"),
                        replace(self.guard, receiver_position_scale=10.),
                        replace(self.guard, remote_role=1),
                        replace(self.guard, update_route="unknown")):
            self.setUp()
            with self.assertRaises(ValueError): self.stage.prepare_request(changed, self.clock)
            self.assert_retired()
        self.setUp(); self.rollback.plane_generation += 1
        with self.assertRaises(ValueError): self.stage.prepare_request(self.guard, self.clock)
        self.assert_retired()

    def test_commit_request_is_not_ready_and_partial_readback_fails(self):
        plan = self.stage.prepare_request(self.guard, self.clock)
        with self.assertRaises(ValueError):
            self.stage.verify_readback(replace(self.guard, revision=6), first.Readback(plan.sha256, plan.writes[:-1], plan.sha256))
        self.assert_retired()

    def test_mismatched_value_duplicate_or_wrong_model_receipt_fails(self):
        for variant in ("value", "duplicate", "model"):
            self.setUp(); plan = self.stage.prepare_request(self.guard, self.clock)
            scalars = plan.writes
            models = plan.sha256
            if variant == "value": scalars = (replace(scalars[0], value=.25),) + scalars[1:]
            elif variant == "duplicate": scalars = scalars + (scalars[0],)
            else: models = "0" * 64
            with self.assertRaises(ValueError):
                self.stage.verify_readback(replace(self.guard, revision=6), first.Readback(plan.sha256, scalars, models))
            self.assert_retired()

    def test_ready_requires_fresh_guard_after_all_readbacks_and_remains_request_only(self):
        plan = self.stage.prepare_request(self.guard, self.clock)
        self.stage.verify_readback(replace(self.guard, revision=6), first.Readback(plan.sha256, plan.writes, plan.sha256))
        ready = self.stage.ready_request(replace(self.guard, revision=7))
        self.assertFalse(ready["executed"])
        self.assertFalse(ready["native_updates_enabled"])
        self.assertFalse(self.stage.motion_gate.ready)
        self.assertFalse(self.stage.native_updates_enabled)

    def test_barrier_loss_after_readback_still_fails_closed(self):
        plan = self.stage.prepare_request(self.guard, self.clock)
        self.stage.verify_readback(replace(self.guard, revision=6), first.Readback(plan.sha256, plan.writes, plan.sha256))
        with self.assertRaises(ValueError): self.stage.ready_request(replace(self.guard, revision=7, update_barrier_held=False))
        self.assert_retired()
        cleanup = Observation(Seen.ABSENT, Seen.OWNED, Seen.ABSENT, Seen.OWNED)
        self.assertEqual(self.rollback.next_action(cleanup), "destroy_owned_plane_via_world_actor_path")

    def test_unknown_commit_outcome_prevents_ready_and_quarantines_cleanup(self):
        plan = self.stage.prepare_request(self.guard, self.clock)
        self.rollback.allocation_outcome_unknown()
        with self.assertRaises(ValueError):
            self.stage.verify_readback(replace(self.guard, revision=6), first.Readback(plan.sha256, plan.writes, plan.sha256))
        self.assert_retired()
        cleanup = Observation(Seen.ABSENT, Seen.OWNED, Seen.ABSENT, Seen.OWNED)
        self.assertEqual(self.rollback.next_action(cleanup), "quarantine")


if __name__ == "__main__": unittest.main()
