#!/usr/bin/env python3
"""Exercise an already permitted development app; retain machine-readable evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

DOMAIN = 'com.apotenza.KeyControl.dev'
APP = Path.home() / 'Applications/KeyControl Dev.app'
ROOT = Path(__file__).resolve().parents[2]


def read(key):
    p = subprocess.run(['defaults', 'read', DOMAIN, key], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def running():
    return subprocess.run(['pgrep', '-f', '^' + str(APP / 'Contents/MacOS/KeyControl') + '$'], stdout=subprocess.DEVNULL).returncode == 0


def wait(predicate, label):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if predicate(): return
        time.sleep(.1)
    raise RuntimeError('Timed out: ' + label)


def main():
    p = argparse.ArgumentParser(); p.add_argument('--controls', action='store_true'); p.add_argument('--output', type=Path, default=ROOT/'build/lifecycle-result.json'); args=p.parse_args()
    if not running(): raise SystemExit('Run scripts/run-dev.sh and grant permissions before this check')
    initial = {k: read(k) for k in ['runtimeAudioState','runtimeAudioDevice','volumePercent','volumeMuted','brightnessPercent','runtimeBrightnessMode']}
    if initial['runtimeAudioState'] not in ('active','native'): raise SystemExit('Audio must already be active or native')
    report = dict(source_dirty=bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True).strip()), source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(), executable_sha256=hashlib.sha256((APP/'Contents/MacOS/KeyControl').read_bytes()).hexdigest(), initial=initial, checks=[], status='failed')
    try:
        if args.controls:
            if initial['runtimeAudioState'] != 'active' or read('runtimeAccessibilityTrusted') != '1' or read('runtimeEventTapRunning') != '1':
                raise RuntimeError('Media-key smoke requires a permitted, active fixed-volume pipeline')
            if int(initial['volumePercent'] or 0) < 6 or initial['volumeMuted'] != '0' or int(initial['brightnessPercent'] or 0) < 6:
                raise RuntimeError('Existing key smoke requires unmuted volume and brightness at least 6%; values were not changed')
            subprocess.run([str(ROOT/'scripts/e2e-smoke.sh')],check=True)
            report['checks'].append('real-media-keys-and-HUD')
        subprocess.run(['osascript','-e',f'tell application id "{DOMAIN}" to quit'],check=True)
        wait(lambda:not running(),'normal quit')
        wait(lambda:read('runtimeAudioState')=='stopped','pipeline cleanup')
        report['checks'].append('normal-quit-stops-pipeline')
        subprocess.run(['open','-na',str(APP)],check=True)
        wait(lambda:running() and read('runtimeAudioState')==initial['runtimeAudioState'],'relaunch recovery')
        for key in ['runtimeAudioDevice','volumePercent','volumeMuted']:
            if read(key)!=initial[key]: raise RuntimeError('Relaunch changed ' + key)
        report['checks'].append('relaunch-restores-output-and-saved-gain')
        report['status']='passed'
    finally:
        if not running(): subprocess.run(['open','-na',str(APP)],check=True)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('Lifecycle checks passed; physical/audible observations are not asserted')

if __name__=='__main__': main()
