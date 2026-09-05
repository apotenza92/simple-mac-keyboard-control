#!/usr/bin/env python3
"""Install the candidate through real Sparkle in a disposable previous-release copy."""
import argparse
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from contract import package, REPOSITORY


def execute(*args):
    return subprocess.check_output(args,stderr=subprocess.STDOUT)


def retains_newer_beta(previous_build, meta):
    return meta['channel']=='beta' and not meta['prerelease'] and int(previous_build)>int(meta['build'])


def gate(tag,channel,arch,assets,feeds,output):
    meta=package(tag,channel,arch)
    url=f'https://raw.githubusercontent.com/{REPOSITORY}/main/appcasts/{channel}-{arch}.xml'
    try:
        old_feed=ET.fromstring(urllib.request.urlopen(url,timeout=30).read())
    except urllib.error.HTTPError as error:
        if error.code==404 and tag=='v0.1.0':
            output.write_text(json.dumps({'status':'baseline-only','reason':'First public release; no previous version exists','channel':channel,'arch':arch})+'\n')
            print('First-release baseline: actual N-1 install test begins with the next release')
            return
        raise
    old_url=old_feed.find('./channel/item/enclosure').get('url')
    if not old_url.startswith(f'https://github.com/{REPOSITORY}/releases/download/'):
        raise ValueError('Previous package URL escapes the release repository')
    configuration=Path(f'/tmp/keycontrol-sparkle-test-{os.getuid()}.json')
    if configuration.exists(): raise RuntimeError('An update-test session already exists')
    with tempfile.TemporaryDirectory(prefix='keycontrol-update-test-') as raw:
        root=Path(raw).resolve(); previous=root/'previous.zip'
        urllib.request.urlretrieve(old_url,previous)
        execute('ditto','-x','-k',str(previous),str(root))
        app=root/(meta['name']+'.app'); info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        execute('codesign','--verify','--deep','--strict',str(app))
        execute('spctl','--assess','--type','execute',str(app))
        details=execute('codesign','-dvvv',str(app)).decode()
        if 'TeamIdentifier=27JL2VERNC' not in details or info['CFBundleIdentifier']!=meta['bundle_id']:
            raise ValueError('Previous app identity mismatch')
        if retains_newer_beta(info['CFBundleVersion'],meta):
            output.write_text(json.dumps({'status':'retained-newer-beta','previous_build':info['CFBundleVersion'],'candidate_build':meta['build'],'channel':channel,'arch':arch})+'\n')
            return
        if int(info['CFBundleVersion'])>=int(meta['build']): raise ValueError('Candidate must advance the previous build')
        server_root=root/'server';server_root.mkdir()
        shutil.copyfile(assets/meta['asset'],server_root/meta['asset'])
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(server_root)))
        worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
        tree=ET.parse(feeds/f'{channel}-{arch}.xml')
        tree.find('./channel/item/enclosure').set('url',f'http://127.0.0.1:{server.server_port}/{meta["asset"]}')
        tree.write(server_root/'feed.xml',encoding='utf-8',xml_declaration=True)
        result=root/'result.txt'
        descriptor=os.open(configuration,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(descriptor,'w') as stream:
            json.dump(dict(bundlePath=str(app),resultPath=str(result),expectedBuild=meta['build'],expiresAt=time.time()+300,feedURL=f'http://127.0.0.1:{server.server_port}/feed.xml'),stream)
        process=None
        try:
            with (root/'app.log').open('w') as log:
                process=subprocess.Popen([str(app/'Contents/MacOS/KeyControl')],stdout=log,stderr=log)
                deadline=time.monotonic()+240
                while time.monotonic()<deadline:
                    if result.exists():
                        value=result.read_text()
                        if value.startswith('error:'): raise RuntimeError(value)
                        if value=='installed-and-relaunched:'+meta['build']:break
                    time.sleep(.25)
                else:raise RuntimeError('Sparkle did not install and relaunch within 240 seconds')
            execute('codesign','--verify','--deep','--strict',str(app))
            installed=plistlib.loads((app/'Contents/Info.plist').read_bytes())
            if installed['CFBundleVersion']!=meta['build'] or installed['CFBundleIdentifier']!=meta['bundle_id']:
                raise RuntimeError('Installed bundle does not match candidate')
            output.write_text(json.dumps({'status':'passed','previous_build':info['CFBundleVersion'],'candidate_build':meta['build'],'channel':channel,'arch':arch})+'\n')
        finally:
            configuration.unlink(missing_ok=True)
            if process and process.poll() is None: process.terminate();process.wait(timeout=10)
            subprocess.run(['pkill','-f','^'+str(app/'Contents/MacOS/KeyControl')+'$'],check=False)
            server.shutdown();server.server_close();worker.join(timeout=5)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('tag');p.add_argument('channel');p.add_argument('arch');p.add_argument('assets',type=Path);p.add_argument('feeds',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();gate(a.tag,a.channel,a.arch,a.assets,a.feeds,a.output)
