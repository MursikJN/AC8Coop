"""Native r13 phase gates only; engine observations are simulated, not gameplay proof."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DLL = ROOT / 'build/shared-session-r13/ac8_local_session_r13.dll'
os.environ['AC8_LOCAL_DLL_TEST'] = str(DLL)
from test_local_bridge import command, read, wait


def trial():
    folder = ROOT / 'build' / ('hangar-session-' + time.strftime('%Y%m%d-%H%M%S'))
    host, guest = folder / 'host', folder / 'guest'
    host.mkdir(parents=True);guest.mkdir()
    token = str(secrets.randbelow(2**53 - 1) + 1)
    children = []
    environment = dict(os.environ, AC8_LOCAL_HANGAR='25201480')
    def start(role, output, port):
        children.append(subprocess.Popen([sys.executable,str(ROOT/'scripts/test_local_bridge.py'),'--worker',role,str(output),token,str(port)],env=environment))
    def both(key, value):
        return read(host).get(key) == read(guest).get(key) == value
    try:
        start('host', host, 0)
        port = wait(lambda: read(host).get('port'), 'host missing')
        start('guest', guest, port)
        wait(lambda: read(guest).get('connected') == '1', 'guest missing')
        command(host,1,2,6,1)
        wait(lambda: read(guest).get('mission') == '6','mission missing')
        command(guest,1,3,23)
        wait(lambda: read(host).get('guest_aircraft') == '23','plane missing')
        command(host,2,10,0)
        assert read(host)['reject'] == '5'
        command(host,3,1,1);command(guest,2,1,1)
        wait(lambda: both('ready_mask','3'),'lobby readiness missing')
        command(host,4,10,0)
        wait(lambda: both('phase','3') and both('ready_mask','0'),'hangar loading reset missing')
        command(guest,3,1,1)
        wait(lambda: read(guest).get('request_confirmed') == '3','guest refusal missing')
        assert read(guest)['reject'] == '2'
        command(host,5,11,23,24)
        assert read(host)['reject'] == '4'
        command(host,6,11,7,23)
        wait(lambda: both('phase','4') and both('ready_mask','0'),'hangar phase missing')
        command(host,7,6,0)
        assert read(host)['reject'] == '5'
        command(host,8,1,1);command(guest,4,1,1)
        wait(lambda: both('ready_mask','3'),'second readiness missing')
        command(host,9,6,0)
        wait(lambda: both('phase','5') and both('ready_mask','0'),'sortie phase missing')
        command(host,10,12,0)
        wait(lambda: both('phase','6'),'flight observation not accepted')
        result = dict(result='passed',test='native_phase_gates_with_simulated_engine_observations',
                      lobby_and_hangar_readiness_separate=True,early_sortie_rejected=True,wrong_plane_observation_rejected=True,
                      guest_ready_during_loading_rejected=True,gameplay_tested=False,evidence=str(folder))
        (folder/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(result,indent=2))
    finally:
        for output in (host,guest):(output/'stop').touch()
        for child in children:
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.terminate();child.wait(timeout=5)
        if any(p.returncode for p in children):raise AssertionError('Native worker shutdown failed')


if __name__ == '__main__':trial()
