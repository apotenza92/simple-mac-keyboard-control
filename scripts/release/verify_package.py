#!/usr/bin/env python3
"""Verify the actual distributed app and its signed Sparkle archive on macOS."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from contract import package, REPOSITORY


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.STDOUT).decode()


def verify(tag, channel, arch, assets, feeds):
    meta = package(tag, channel, arch)
    archive = assets / meta['asset']
    data = archive.read_bytes()
    feed = ET.parse(feeds / f'{channel}-{arch}.xml')
    enclosure = feed.find('./channel/item/enclosure')
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    expected = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{meta['asset']}"
    assert enclosure.get('url') == expected
    assert int(enclosure.get('length')) == len(data)
    assert feed.findtext('./channel/item/' + ns + 'version') == meta['build']
    with zipfile.ZipFile(archive) as zipped:
        assert all(not p.startswith('/') and '..' not in Path(p).parts for p in zipped.namelist())
    with tempfile.TemporaryDirectory() as temporary:
        run('ditto', '-x', '-k', str(archive), temporary)
        app = Path(temporary) / (meta['name'] + '.app')
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == meta['bundle_id']
        assert info['CFBundleVersion'] == meta['build']
        assert info['CFBundleShortVersionString'] == meta['version']
        assert info['LSMinimumSystemVersion'] == '14.4'
        assert info['SUFeedURL'] == f'https://raw.githubusercontent.com/{REPOSITORY}/main/appcasts/{channel}-{arch}.xml'
        assert info['SUVerifyUpdateBeforeExtraction'] is True
        public = Ed25519PublicKey.from_public_bytes(base64.b64decode(info['SUPublicEDKey']))
        signature = base64.b64decode(enclosure.get(ns + 'edSignature'), validate=True)
        public.verify(signature, data)
        try:
            public.verify(signature, data + b'tampered')
        except Exception:
            pass
        else:
            raise ValueError('Tampered update accepted')
        architectures = run('lipo', '-archs', str(app / 'Contents/MacOS/KeyControl')).split()
        assert architectures == ['arm64' if arch == 'arm64' else 'x86_64']
        run('codesign', '--verify', '--deep', '--strict', str(app))
        details = run('codesign', '-dvvv', str(app))
        assert 'Authority=' + os.environ['APPLE_SIGNING_IDENTITY'] in details
        assert 'TeamIdentifier=' + os.environ['APPLE_TEAM_ID'] in details
        assert 'runtime' in details
        run('xcrun', 'stapler', 'validate', str(app))
        run('spctl', '--assess', '--type', 'execute', str(app))
        prefix = str(Path(temporary) / 'certificate')
        run('codesign', '-d', '--extract-certificates=' + prefix, str(app))
        assert hashlib.sha256(Path(prefix + '0').read_bytes()).hexdigest().upper() == os.environ['APPLE_SIGNING_CERTIFICATE_SHA256'].upper()
    print(f'Verified {channel}/{arch}: identity, archive signature, tamper rejection, code signing, notarization, Gatekeeper')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('tag'); p.add_argument('channel'); p.add_argument('arch'); p.add_argument('assets', type=Path); p.add_argument('feeds', type=Path)
    args = p.parse_args()
    verify(args.tag, args.channel, args.arch, args.assets, args.feeds)
