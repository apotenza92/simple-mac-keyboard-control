#!/usr/bin/env python3
"""Exercise installed dev-app native controls and quit/crash display recovery.

Runs actual display switches. Requires both screens on and all KeyControl app
instances closed; it does not assert human observation or physical cable tests.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
EXE = Path.home() / 'Applications/KeyControl Dev.app/Contents/MacOS/KeyControl'
DOMAIN = 'com.apotenza.KeyControl.dev'
OUT = ROOT / 'build/display-menu'


def state():
    return json.loads(subprocess.check_output([str(EXE), '--display-prototype', 'status'], text=True, timeout=10))


def read(key):
    result = subprocess.run(['defaults', 'read', DOMAIN, key], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def main():
    assert subprocess.run(['pgrep', '-x', 'KeyControl'], stdout=subprocess.DEVNULL).returncode != 0, 'Quit running KeyControl apps before this test'
    initial = state()
    assert len(initial) == 2 and all(s['online'] and s['active'] for s in initial), 'Two active displays required'
    OUT.mkdir(parents=True, exist_ok=True)
    report = {'status': 'failed', 'initial': initial, 'checks': [],
              'executable_sha256': hashlib.sha256(EXE.read_bytes()).hexdigest()}
    try:
        for mode, expected in [('quit', 0), ('crash', -9)]:
            with (OUT / f'{mode}.log').open('w') as log:
                result = subprocess.run([str(EXE), '--display-menu-smoke', f'--display-menu-{mode}'],
                                        stdout=log, stderr=log, timeout=60)
            assert result.returncode == expected, f'{mode}: unexpected exit {result.returncode}'
            assert read('runtimeDisplayMenuSmokeStatus') == f'ready-for-{mode}', read('runtimeDisplayMenuSmokeError')
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                after = state()
                restored = all(any(s['key'] == old['key'] and s['online'] and s['active'] for s in after) for old in initial)
                helpers_gone = subprocess.run(['pgrep', '-x', 'KeyControl'], stdout=subprocess.DEVNULL).returncode != 0
                if restored and helpers_gone:
                    break
                time.sleep(.2)
            else:
                raise AssertionError('Displays or helper processes did not return to baseline')
            report['checks'].append({'mode': mode, 'returncode': result.returncode,
                'native_checks': read('runtimeDisplayMenuSmokeChecks'), 'after': after})
        report['status'] = 'passed'
    finally:
        try:
            recovery_codes = [subprocess.run([str(EXE), '--display-prototype', 'restore', s['key']], timeout=15).returncode for s in initial]
            report['final'] = state()
            if any(recovery_codes): report['status'] = 'failed'
        finally:
            (OUT / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    assert report['status'] == 'passed'
    print('Native controls, exact tooltip, last-display guard, normal quit and actual app SIGKILL recovery passed.')


if __name__ == '__main__':
    main()
