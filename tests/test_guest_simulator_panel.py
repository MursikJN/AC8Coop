"""A temporary atomic-status read conflict must not produce a false disconnect."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('guest_panel', ROOT / 'coop/guest_simulator.py')
panel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(panel)


class PanelStatusTests(unittest.TestCase):
    def client(self):
        client = panel.GuestClient.__new__(panel.GuestClient)
        client.output = ROOT / 'build/unused-test-path'
        client.session = {'token': '123'}
        client.active = True
        client.stopping = False
        client.pending = None
        client.snapshot = {'connected': '1', 'have_snapshot': '1'}
        client.message = 'Хост подтвердил: F-14D'
        client.started_at = time.time_ns() - 30_000_000_000
        client.last_seen = time.monotonic()
        client.last_stamp = 0
        client.sequence = 0
        client.library = SimpleNamespace(ac8_local_wait_stopped=lambda _: 1)
        return client

    def test_single_read_conflict_preserves_confirmed_connection(self):
        client = self.client()
        with patch.object(panel, 'read_status', return_value=({}, 0)):
            client.poll()
        self.assertTrue(client.connected)
        self.assertEqual(client.message, 'Хост подтвердил: F-14D')

    def test_stale_status_disables_commands_and_reports_no_response(self):
        client = self.client();client.last_seen -= 9
        with patch.object(panel, 'read_status', return_value=({}, 0)):
            client.poll()
        self.assertFalse(client.connected)
        self.assertIn('Нет ответа', client.message)

    def test_previous_run_token_does_not_replace_current_snapshot(self):
        client = self.client()
        with patch.object(panel, 'read_status', return_value=({'config_token':'122','connected':'0'}, time.time_ns())):
            client.poll()
        self.assertTrue(client.connected)

    def test_stopped_status_waits_for_actual_native_thread_exit(self):
        client = self.client();client.stopping = True
        client.library.ac8_local_wait_stopped = lambda _: 0
        state = dict(config_token='123',transport='stopped',request_ack='0')
        with patch.object(panel, 'read_status', return_value=(state, time.time_ns())):
            client.poll()
        self.assertTrue(client.active)
        client.library.ac8_local_wait_stopped = lambda _: 1
        with patch.object(panel, 'read_status', return_value=(state, time.time_ns())):
            client.poll()
        self.assertFalse(client.active)
        self.assertFalse(client.stopping)
