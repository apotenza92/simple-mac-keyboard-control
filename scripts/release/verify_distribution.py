#!/usr/bin/env python3
"""Verify public distribution; pending tap/feed propagation is never a success."""
import argparse
import base64
import plistlib
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from contract import REPOSITORY, parse_tag, package
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature


class IntegrityError(ValueError):
    pass

PAGE = f'https://apotenza92.github.io/simple-mac-keyboard-control/'
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read()


def select(releases, channel):
    candidates = []
    for release in releases:
        try:
            meta = parse_tag(release['tag_name'])
        except (ValueError, KeyError):
            continue
        if release['draft'] or release['prerelease'] != meta['prerelease']:
            continue
        if channel == 'stable' and meta['prerelease']:
            continue
        candidates.append((int(meta['build']), release))
    if not candidates:
        raise ValueError('No public release for ' + channel)
    return max(candidates, key=lambda value: value[0])[1]


def check_feed(data, artifact, tag):
    item = ET.fromstring(data).find('./channel/item')
    enclosure = item.find('enclosure') if item is not None else None
    if (item is None or enclosure is None
            or item.findtext(NS + 'version') != parse_tag(tag)['build']
            or enclosure.get('url') != artifact['url']
            or enclosure.get('length') != str(artifact['size'])
            or not enclosure.get(NS + 'edSignature')):
        raise ValueError('Feed does not match ' + artifact['name'])


def bundle(tag, root):
    directory = root / tag
    directory.mkdir(exist_ok=True)
    path = directory / 'homebrew-publication.tar.gz'
    subprocess.run(['gh', 'release', 'download', tag, '--repo', REPOSITORY,
                    '--pattern', path.name, '--dir', str(directory)], check=True, capture_output=True)
    result = subprocess.run(['gh', 'attestation', 'verify', str(path), '--repo', REPOSITORY,
                             '--signer-workflow', REPOSITORY + '/.github/workflows/release.yml'],
                            capture_output=True)
    if result.returncode:
        raise IntegrityError('Publication attestation was not verified')
    with tarfile.open(path) as archive:
        # Read only known regular files; never extract archive paths to disk.
        files = {}
        for name in ['manifest.json', 'Casks/simple-mac-keyboard-control.rb',
                     'Casks/simple-mac-keyboard-control@beta.rb']:
            try:
                member = archive.getmember(name)
            except KeyError:
                continue
            if not member.isfile() or member.size > 100000:
                raise IntegrityError('Invalid publication member: ' + name)
            files[name] = archive.extractfile(member).read()
    manifest = json.loads(files['manifest.json'])
    if manifest['source_repository'] != REPOSITORY or manifest['release_tag'] != tag:
        raise IntegrityError('Publication identity mismatch')
    for artifact in manifest['artifacts']:
        expected = package(tag, artifact['channel'], artifact['architecture'])['asset']
        url = f'https://github.com/{REPOSITORY}/releases/download/{tag}/{expected}'
        if artifact['url'] != url or artifact['name'] != expected:
            raise IntegrityError('Untrusted artifact URL')
        data = fetch(url)
        if len(data) != artifact['size'] or hashlib.sha256(data).hexdigest() != artifact['sha256']:
            raise IntegrityError('Public package bytes differ: ' + expected)
        files[artifact['name']] = data
    return manifest, files


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tag')
    parser.add_argument('--wait-seconds', type=int, default=0)
    args = parser.parse_args()
    parse_tag(args.tag)
    deadline = time.monotonic() + args.wait_seconds
    report = {'requested_tag': args.tag, 'status': 'partial', 'checks': {}, 'errors': []}
    with tempfile.TemporaryDirectory() as temporary:
        cache = {}
        while True:
            errors = []
            def check(name, action):
                try:
                    action()
                    report['checks'][name] = 'passed'
                except (IntegrityError, InvalidSignature) as error:
                    report['status'] = 'failed'
                    report['errors'] = [f'{name}: integrity verification failed: {error}']
                    Path('distribution-status.json').write_text(json.dumps(report, indent=2) + '\n')
                    raise SystemExit(report['errors'][0])
                except Exception as error:
                    report['checks'][name] = 'failed'
                    # Do not print subprocess output, which can contain signed URLs.
                    errors.append(f'{name}: {type(error).__name__}: {error}')
            releases = json.loads(subprocess.check_output([
                'gh', 'api', '--paginate', '--slurp', f'repos/{REPOSITORY}/releases?per_page=100']))
            releases = [release for page in releases for release in page]
            def publication(tag):
                if tag not in cache:
                    directory = Path(temporary) / tag
                    if directory.exists():
                        (directory / 'homebrew-publication.tar.gz').unlink(missing_ok=True)
                    release = next(r for r in releases if r['tag_name'] == tag)
                    if release['draft'] or not release.get('immutable'):
                        raise IntegrityError('Release is not public and immutable')
                    cache[tag] = bundle(tag, Path(temporary))
                return cache[tag]
            check('requested release bytes and attestation', lambda: publication(args.tag))
            for channel in ['stable', 'beta']:
                def channel_check(channel=channel):
                    tag = select(releases, channel)['tag_name']
                    manifest, files = publication(tag)
                    token = 'simple-mac-keyboard-control' + ('@beta' if channel == 'beta' else '')
                    name = 'Casks/' + token + '.rb'
                    remote = fetch('https://raw.githubusercontent.com/apotenza92/homebrew-tap/main/' + name)
                    if remote != files[name]:
                        raise ValueError('Public cask has not converged to ' + tag)
                    for arch in ['arm64', 'x64']:
                        artifact = next(a for a in manifest['artifacts'] if a['channel'] == channel and a['architecture'] == arch)
                        feed = fetch(f'https://raw.githubusercontent.com/{REPOSITORY}/main/appcasts/{channel}-{arch}.xml')
                        check_feed(feed, artifact, tag)
                        signature = ET.fromstring(feed).find('./channel/item/enclosure').get(NS + 'edSignature')
                        key = plistlib.loads(Path('Resources/Info.plist').read_bytes())['SUPublicEDKey']
                        Ed25519PublicKey.from_public_bytes(base64.b64decode(key)).verify(
                            base64.b64decode(signature), files[artifact['name']])
                check(channel + ' cask and feeds', channel_check)
            for name in ['index.html', 'downloads.js', 'release-model.mjs', 'style.css']:
                def page_check(name=name):
                    if fetch(PAGE + name) != (Path('docs') / name).read_bytes():
                        raise ValueError('Deployed page differs from reviewed source: ' + name)
                check('page ' + name, page_check)
            report['errors'] = errors
            report['status'] = 'partial' if errors else 'passed'
            Path('distribution-status.json').write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(report), flush=True)
            if not errors or time.monotonic() >= deadline:
                break
            time.sleep(min(60, max(0, deadline - time.monotonic())))
    if report['status'] != 'passed':
        raise SystemExit('Partial publication: see distribution-status.json')


if __name__ == '__main__':
    main()
