"""Exercise the actual Lua-loadable local DLL in two isolated Python processes."""
import ctypes
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DLL = Path(os.environ.get('AC8_LOCAL_DLL_TEST', ROOT / 'build/shared-session-r12/ac8_local_session_r12.dll'))


def read(folder):
    try:
        return dict(line.split('\t', 1) for line in (folder / 'shared-session-status.tsv').read_text().splitlines())
    except (FileNotFoundError, PermissionError, ValueError):
        return {}


def wait(predicate, message, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(.02)
    raise AssertionError(message)


def command(folder, request, op, arg0, arg1=0):
    state = read(folder)
    data = dict(request=request, epoch=state['epoch'], revision=state['revision'], op=op, arg0=arg0, arg1=arg1)
    (folder / 'shared-session-command.tsv').write_bytes(''.join(f'{k}\t{v}\n' for k, v in data.items()).encode('ascii'))
    wait(lambda: int(read(folder).get('request_ack', '0')) == request, 'command not acknowledged')


def worker(role, output, token, port):
    os.environ.update(AC8_LOCAL_SESSION='25201480', AC8_LOCAL_ROLE=role, AC8_LOCAL_PORT=port,
                      AC8_LOCAL_TOKEN=token, AC8_COOP_RECON_OUTPUT=output)
    library = ctypes.CDLL(str(DLL))
    library.luaopen_ac8_local_start.argtypes = [ctypes.c_void_p]
    library.luaopen_ac8_local_stop.argtypes = [ctypes.c_void_p]
    library.luaopen_ac8_local_start(None)
    end = time.monotonic() + 45
    while time.monotonic() < end and not (Path(output) / 'stop').exists():
        time.sleep(.02)
    library.luaopen_ac8_local_stop(None)
    wait(lambda: read(Path(output)).get('transport') == 'stopped', 'worker did not stop')
    library.ac8_local_wait_stopped.argtypes = [ctypes.c_ulong]
    assert library.ac8_local_wait_stopped(5000) == 1, 'worker thread did not exit'


def trial():
    output = ROOT / 'build' / ('local-bridge-' + time.strftime('%Y%m%d-%H%M%S'))
    host, guest = output / 'host', output / 'guest'
    host.mkdir(parents=True); guest.mkdir()
    token = str(secrets.randbelow(2**53 - 1) + 1)
    children = []
    def start(role, folder, port):
        process = subprocess.Popen([sys.executable, __file__, '--worker', role, str(folder), token, str(port)])
        children.append(process)
    try:
        start('host', host, 0)
        port = wait(lambda: read(host).get('port'), 'host did not listen')
        start('guest', guest, port)
        wait(lambda: read(guest).get('connected') == '1', 'guest not connected')
        command(host, 1, 2, 1, 2)
        wait(lambda: read(guest).get('mission') == '1', 'selection not replicated')
        command(guest, 1, 2, 99, 3)
        assert read(guest)['reject'] == '1', 'guest selection must be rejected'
        command(host, 2, 1, 1)
        command(guest, 2, 1, 1)
        wait(lambda: read(host).get('ready_mask') == read(guest).get('ready_mask') == '3', 'ready not replicated')
        command(host, 3, 2, 6, 3)
        wait(lambda: read(guest).get('mission') == '6' and read(guest).get('ready_mask') == '0', 'selection did not reset ready')
        # The host receives no user commands here. Keepalive must prevent the 15-second idle timeout.
        time.sleep(16)
        for folder in (host, guest):
            assert read(folder)['transport'] == 'connected', 'idle connection lost'
        result = dict(result='passed', test='actual_dll_two_process_control', idle_seconds=16,
                      guest_selection_rejected=True, ready_both=True, host_change_resets_ready=True,
                      gameplay_tested=False, output=str(output))
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
    finally:
        for folder in (host, guest):
            (folder / 'stop').touch()
        for child in children:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.terminate(); child.wait(timeout=5)
        if any(child.returncode != 0 for child in children):
            raise AssertionError('DLL worker process failed')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        worker(*sys.argv[2:])
    else:
        trial()
