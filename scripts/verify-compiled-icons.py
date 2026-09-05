#!/usr/bin/env python3
"""Bind architecture-independent native icon catalogs to their exact vector inputs."""
import hashlib
import json
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
files = sorted(p for name in ('AppIcon', 'AppIconBeta') for p in (root/'Resources'/f'{name}.icon').rglob('*') if p.is_file())
files += sorted(p for p in (root/'Resources/CompiledIcons').rglob('*') if p.is_file() and p.name != 'checksums.json')
digests = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
manifest = root/'Resources/CompiledIcons/checksums.json'
if '--record' in sys.argv:
    manifest.write_text(json.dumps(digests,indent=2)+'\n')
elif json.loads(manifest.read_text()) != digests:
    raise SystemExit('Native icon sources/catalogs changed. Run scripts/compile-icons.sh with Xcode 26 on a supported Mac.')
else:
    print('Native icon sources and compiled catalogs verified')
