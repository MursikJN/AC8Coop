"""Actual panel controller against a native host process, including disconnect/rejoin."""
import hashlib
import importlib.util
import json
from pathlib import Path
import secrets
import subprocess
import sys
import time

from test_local_bridge import ROOT, DLL, command, read, wait

spec = importlib.util.spec_from_file_location('ac8_guest_panel', ROOT / 'coop/guest_simulator.py')
panel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(panel)


def trial():
    folder = ROOT / 'build' / ('guest-simulator-' + time.strftime('%Y%m%d-%H%M%S'))
    host, guest = folder / 'host', folder / 'guest'
    host.mkdir(parents=True);guest.mkdir()
    token = str(secrets.randbelow(2**53 - 1) + 1)
    process = subprocess.Popen([sys.executable, str(ROOT / 'scripts/test_local_bridge.py'), '--worker', 'host', str(host), token, '0'])
    client = None
    try:
        port = wait(lambda: read(host).get('port'), 'host missing')
        descriptor = dict(address='127.0.0.1', port=port, token=token, host_pid=process.pid,
                          host_output=str(host), guest_output=str(guest), guest_dll=str(DLL),
                          guest_dll_sha256=hashlib.sha256(DLL.read_bytes()).hexdigest().upper())
        session = folder / 'simulator-session.json'
        session.write_text(json.dumps(descriptor), encoding='utf-8')
        client = panel.GuestClient(session)
        def until(predicate, message):
            def tick():
                client.poll()
                return predicate()
            return wait(tick, message)
        client.connect()
        until(lambda: client.connected, 'panel did not connect')
        command(host, 1, 2, 1, 2)
        until(lambda: client.snapshot.get('mission') == '1', 'mission missing')
        client.choose_plane(23)
        until(lambda: client.pending is None, 'plane not confirmed')
        assert read(host)['guest_aircraft'] == client.snapshot['guest_aircraft'] == '23'
        assert client.snapshot['request_confirmed'] == '1'
        command(host, 2, 1, 1)
        client.ready()
        until(lambda: client.pending is None and client.snapshot['ready_mask'] == '3', 'ready not confirmed')
        client.choose_plane(24)  # opaque protocol test key; no invented game model mapping
        until(lambda: client.pending is None and client.snapshot['guest_aircraft'] == '24', 'changed plane missing')
        assert read(host)['ready_mask'] == '1', 'plane change must clear only guest readiness'
        client.ready()
        until(lambda: client.pending is None and client.snapshot['ready_mask'] == '3', 'second ready failed')
        command(host, 3, 2, 6, 3)
        until(lambda: client.snapshot['mission'] == '6' and client.snapshot['ready_mask'] == '0', 'host settings reset failed')
        # Force a stale revision and require an explicit host rejection to return to the panel.
        client.snapshot['revision'] = '1'
        client.choose_plane(23)
        until(lambda: client.pending is None, 'rejection not acknowledged')
        assert client.snapshot['reject'] == '3'
        assert 'изменил настройки' in client.message
        client.disconnect()
        until(lambda: not client.active and not client.stopping, 'panel did not stop')
        wait(lambda: read(host).get('connected') == '0' and read(host).get('guest_aircraft') == '0', 'host did not clear guest on disconnect')
        client.connect()
        until(lambda: client.connected, 'same host did not accept rejoin')
        assert client.snapshot['mission'] == '6' and client.snapshot['ready_mask'] == '0'
        client.choose_plane(23)
        until(lambda: client.pending is None and read(host).get('guest_aircraft') == '23', 'rejoined selection failed')
        result = dict(result='passed', test='guest_panel_controller_with_native_host', connect=True,
                      plane_selection=True, plane_change_resets_guest_ready=True, both_ready=True,
                      host_selection_resets_both=True, explicit_rejection=True, same_host_reconnect=True,
                      gameplay_tested=False, evidence=str(folder))
        (folder / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(result, indent=2))
    finally:
        if client and client.active:
            client.disconnect()
            wait(lambda: (client.poll() or not client.active), 'guest cleanup')
        (host / 'stop').touch()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate();process.wait(timeout=5)
        if process.returncode != 0:
            raise AssertionError(f'Host DLL worker failed: {process.returncode}')


if __name__ == '__main__':
    trial()
