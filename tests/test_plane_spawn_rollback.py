"""Failure injection into the offline policy; does not execute engine destruction."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from plane_spawn_rollback import Identity, Observation, Rollback, Seen

A, O, U, X = Seen.ABSENT, Seen.OWNED, Seen.UNKNOWN, Seen.OTHER


class RollbackTests(unittest.TestCase):
    def journal(self, count=3):
        j = Rollback(7, 9)
        for i, kind in enumerate(("dummy", "plane", "network")[:count]):
            j.acquired(kind, Identity(7, i + 20, 100 + i))
        j.retire()
        return j

    def test_failure_after_every_acquisition_drains_only_owned_resources(self):
        for count in range(4):
            for registered in (False, True) if count == 3 else (False,):
                with self.subTest(count=count, registered=registered):
                    j = self.journal(count)
                    s = {"registry": O if registered else A, "dummy": O if count else A,
                         "plane": O if count >= 2 else A, "network": O if count >= 3 else A}
                    actions = []
                    while True:
                        action = j.next_action(Observation(**s))
                        actions.append(action)
                        if action == "complete": break
                        # Repeated command without new evidence cannot advance cleanup.
                        self.assertEqual(j.next_action(Observation(**s)), action)
                        self.assertFalse(j.released)
                        if action.startswith("compare_owner"): s["registry"] = A
                        elif "plane_via" in action: s["plane"] = A
                        elif "dummy_via" in action: s["dummy"] = A
                        elif action == "wait_for_owned_network_retirement": s["network"] = A
                        else: self.fail(action)
                    self.assertTrue(j.released)
                    if registered:
                        self.assertEqual(actions[0], "compare_owner_then_unregister_on_game_thread")
                    self.assertEqual(j.next_action(Observation(U, U, U, U)), "complete")

    def test_registry_replaced_between_plan_and_execution_is_not_removed(self):
        j = self.journal()
        self.assertTrue(j.next_action(Observation(O, O, O, O)).startswith("compare_owner"))
        self.assertEqual(j.next_action(Observation(X, O, O, O)), "quarantine")
        self.assertFalse(j.released)

    def test_missing_serial_world_or_ambiguous_allocation_blocks_retry(self):
        for kwargs in ({"world_verified": False}, {}):
            j = self.journal()
            if not kwargs: j.allocation_outcome_unknown()
            self.assertEqual(j.next_action(Observation(A, A, A, A, **kwargs)), "quarantine")
            self.assertFalse(j.released)
        for resource in ("registry", "plane", "dummy", "network"):
            for state in (U, X):
                s = dict(registry=A, plane=A, dummy=A, network=A)
                s[resource] = state
                self.assertEqual(self.journal().next_action(Observation(**s)), "quarantine")

    def test_cannot_destroy_baseline_or_repossessed_dummy(self):
        self.assertEqual(self.journal(0).next_action(Observation(A, O, A, A)), "quarantine")
        self.assertEqual(self.journal(1).next_action(Observation(A, A, O, A, True)), "quarantine")
        # Destroying the plane can itself call PawnPendingDestroy on the dummy.
        self.assertEqual(self.journal().next_action(Observation(A, O, O, O, True)), "quarantine")

    def test_missing_or_invalid_observation_never_means_absent(self):
        for state in (None, "verified_absent", False, 0):
            with self.assertRaises(ValueError): Observation(state, state, state, state)
        with self.assertRaises(ValueError): Observation(A, A, A, A, world_verified=None)

    def test_generation_terminal_and_receipts_required(self):
        j = Rollback(1, 1)
        with self.assertRaises(ValueError): j.next_action(Observation(A, A, A, A))
        with self.assertRaises(ValueError): j.acquired("network", Identity(1, 1, 1))
        with self.assertRaises(ValueError): j.acquired("dummy", Identity(2, 1, 1))
        j.acquired("dummy", Identity(1, 1, 1))
        with self.assertRaises(ValueError): j.acquired("plane", Identity(1, 1, 1))
        j.retire()
        with self.assertRaises(ValueError): j.acquired("plane", Identity(1, 2, 1))

    def test_no_caches_freed_just_because_registry_absent(self):
        j = self.journal()
        self.assertEqual(j.next_action(Observation(A, A, A, O)), "wait_for_owned_network_retirement")
        self.assertFalse(j.released)


if __name__ == "__main__": unittest.main()
