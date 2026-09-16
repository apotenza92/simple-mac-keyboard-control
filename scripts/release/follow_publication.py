#!/usr/bin/env python3
"""Follow an authorized release and promptly reconcile its Homebrew publication.

Run locally with an authenticated gh CLI that can dispatch the tap workflow.
This does not create a release or bypass any of its validation jobs.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from contract import REPOSITORY, parse_tag

TAP = 'apotenza92/homebrew-tap'
ROOT = Path(__file__).resolve().parents[2]


def api(endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))


def validate_run(run, tag, sha):
    if (run.get('path') != '.github/workflows/release.yml'
            or run.get('event') != 'push' or run.get('head_branch') != tag
            or run.get('head_sha') != sha):
        raise ValueError('Run does not match the requested release tag and workflow')
    if run['status'] == 'completed' and run['conclusion'] != 'success':
        raise ValueError('Release failed or was cancelled; Homebrew was not dispatched')
    return run['status'] == 'completed'


def follow(tag, run_id, timeout):
    parse_tag(tag)
    sha = api(f'repos/{REPOSITORY}/commits/{tag}')['sha']
    deadline = time.monotonic() + timeout
    previous = None
    while True:
        run = api(f'repos/{REPOSITORY}/actions/runs/{run_id}')
        complete = validate_run(run, tag, sha)
        status = (run['status'], run.get('conclusion'))
        if status != previous:
            print(f'Release {tag}: {status[0]} {status[1] or ""}', flush=True)
            previous = status
        if complete:
            break
        if time.monotonic() >= deadline:
            raise TimeoutError('Release still pending; rerun this command to resume')
        time.sleep(min(15, max(0, deadline - time.monotonic())))
    subprocess.run(['gh', 'workflow', 'run', 'reconcile-keycontrol.yml', '--repo', TAP], check=True)
    print('Homebrew reconciliation dispatched; checking public distribution.', flush=True)
    subprocess.run([sys.executable, str(ROOT / 'scripts/release/verify_distribution.py'), tag,
                    '--wait-seconds', '2400', '--output',
                    str(ROOT / 'build/releases' / tag / 'distribution-status.json')], cwd=ROOT, check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('run_id', type=int)
    parser.add_argument('--timeout', type=int, default=2700)
    args = parser.parse_args()
    follow(args.tag, args.run_id, args.timeout)
