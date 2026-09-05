#!/usr/bin/env python3
"""Check public release bytes against the attested publication manifest."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import urllib.request

manifest=json.loads(Path(sys.argv[1]).read_text())
repo=manifest['source_repository'];tag=manifest['release_tag']
release=json.loads(subprocess.check_output(['gh','api',f'repos/{repo}/releases/tags/{tag}']))
if release['draft'] or not release.get('immutable') or release['prerelease'] != ('-beta.' in tag):
    raise SystemExit('Public release classification or immutability mismatch')
for artifact in manifest['artifacts']:
    digest=hashlib.sha256();size=0
    with urllib.request.urlopen(artifact['url'],timeout=60) as response:
        while block:=response.read(1024*1024):digest.update(block);size+=len(block)
    if digest.hexdigest()!=artifact['sha256'] or size!=artifact['size']:
        raise SystemExit('Public bytes differ: '+artifact['name'])
    print('Public bytes verified: '+artifact['name'])
