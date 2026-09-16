#!/usr/bin/env python3
"""Bounded, real built-in display switching against the installed dev binary.

Requires an open MacBook and an active independent external screen. Exercises a
four-second disconnect, explicit restoration, then recovery after SIGKILL of
the prototype process. No media keys or audio pipelines are started here.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
EXE = Path.home() / 'Applications/KeyControl Dev.app/Contents/MacOS/KeyControl'
OUT = ROOT / 'build/display-prototype'


def status():
    return json.loads(subprocess.check_output(
        [str(EXE), '--display-prototype', 'status'], text=True, timeout=10))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    initial = status()
    target = next(s for s in initial if s['builtIn'] and s['online'] and s['active'])
    assert any(s['key'] != target['key'] and s['online'] and s['active']
               and not s['mirrored'] for s in initial), 'Independent external display required'
    report = {'executable_sha256': hashlib.sha256(EXE.read_bytes()).hexdigest(),
              'initial': initial, 'checks': [], 'status': 'failed'}
    try:
        for mode, expected in [('cycle', 0), ('crash', -9), ('external-cycle', 0), ('external-crash', -9)]:
            path = OUT / f'{mode}.log'
            with path.open('w') as log:
                result = subprocess.run([str(EXE), '--display-prototype', mode],
                                        stdout=log, stderr=log, timeout=20)
            assert result.returncode == expected, f'{mode} returned {result.returncode}; see {path}'
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                current = status()
                if all(any(s['key'] == old['key'] and s['online'] == old['online']
                           and s['active'] == old['active'] for s in current) for old in initial):
                    break
                time.sleep(.2)
            else:
                raise AssertionError(f'{mode}: original displays did not return')
            # The child's recovery log is written asynchronously after a crash.
            while time.monotonic() < deadline and 'Recovery: target restored and verified online.' not in path.read_text():
                time.sleep(.1)
            text = path.read_text()
            kind = 'external' if mode.startswith('external') else 'built-in'
            assert f'Verified {kind} offline' in text, f'{mode}: no verified disconnect'
            assert 'Recovery: target restored and verified online.' in text, f'{mode}: recovery did not complete'
            report['checks'].append({'mode': mode, 'returncode': result.returncode, 'after': current, 'log': text})
        report['status'] = 'passed'
    finally:
        # An explicit final restore is independent of the exercised parent/helper.
        try:
            recovery_codes = [subprocess.run([str(EXE), '--display-prototype', 'restore', old['key']], timeout=15).returncode
                              for old in initial if old['online']]
            report['final_restore_returncodes'] = recovery_codes
            report['final'] = status()
            if any(recovery_codes):
                report['status'] = 'failed'
        finally:
            (OUT / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    assert report['status'] == 'passed', 'Final restoration failed'
    print('Display prototype checks passed. Physical screen observations are not asserted.')


if __name__ == '__main__':
    main()
