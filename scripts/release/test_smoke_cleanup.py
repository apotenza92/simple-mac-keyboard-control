import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

class SmokeCleanupTests(unittest.TestCase):
    def test_hud_capture_failure_restores_the_already_applied_volume_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'scripts').mkdir();(root/'bin').mkdir()
            shutil.copyfile(Path(__file__).resolve().parents[1]/'e2e-smoke.sh',root/'scripts/e2e-smoke.sh')
            state=root/'state.json'
            state.write_text(json.dumps(dict(runtimeAudioState='active',runtimeAudioDevice='Test Interface',runtimeAccessibilityTrusted='1',runtimeEventTapRunning='1',runtimeInputMonitoringGranted='1',runtimeBrightnessHIDRunning='1',volumePercent='52',volumeMuted='0',runtimeHUDCount='0',calls=[])))
            def executable(path,text):path.write_text(text);path.chmod(0o755)
            header=f'#!{sys.executable}\nimport json,os,sys\np=os.environ["KEYCONTROL_SMOKE_STATE"]\ns=json.load(open(p))\n'
            executable(root/'bin/defaults',header+'print(s.get(sys.argv[-1],""))\n')
            executable(root/'scripts/send-media-key.swift',header+'''key=sys.argv[1]
s['calls'].append(key)
s['volumePercent']=str(int(s['volumePercent']) + (6 if key=='volume-up' else -6))
s.update(runtimeHUDCount=str(int(s['runtimeHUDCount'])+1),runtimeHUDKind='volume',runtimeHUDPercent=s['volumePercent'],runtimeHUDName='Test Interface',runtimeHUDVisible='1')
json.dump(s,open(p,'w'))
''')
            for name in ['pgrep','sleep']:executable(root/'bin'/name,'#!/bin/sh\nexit 0\n')
            executable(root/'bin/screencapture','#!/bin/sh\nexit 1\n')
            result=subprocess.run(['bash',str(root/'scripts/e2e-smoke.sh')],env=dict(os.environ,PATH=str(root/'bin')+os.pathsep+os.environ['PATH'],KEYCONTROL_SMOKE_STATE=str(state)),capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            after=json.loads(state.read_text())
            self.assertEqual(after['volumePercent'],'52')
            self.assertEqual(after['calls'],['volume-down','volume-up'])
