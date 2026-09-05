#!/usr/bin/env python3
"""Seal the exact native packages for Sparkle and the tap-owned publisher."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tarfile
import xml.etree.ElementTree as ET
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from contract import parse_tag, package, REPOSITORY

NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def prepare(tag, assets, output, private_key):
    meta = parse_tag(tag)
    key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(private_key.strip(), validate=True))
    public = plistlib.loads(Path('Resources/Info.plist').read_bytes())['SUPublicEDKey']
    if key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw) != base64.b64decode(public):
        raise ValueError('Signing key does not match the bundled public key')
    feeds = output / 'appcasts'
    casks = output / 'publication' / 'Casks'
    feeds.mkdir(parents=True)
    casks.mkdir(parents=True)
    artifacts = []
    filenames = []
    for channel in meta['channels']:
        token = 'simple-mac-keyboard-control' + ('@beta' if channel == 'beta' else '')
        filename = token + '.rb'
        filenames.append(filename)
        sections = []
        for arch in ('arm64', 'x64'):
            item = package(tag, channel, arch)
            path = assets / item['asset']
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            checksum = (assets / (item['asset'] + '.sha256')).read_text().split()
            if checksum != [digest, item['asset']]:
                raise ValueError('Package checksum mismatch: ' + item['asset'])
            url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{item['asset']}"
            signature = key.sign(data)
            key.public_key().verify(signature, data)
            artifacts.append(dict(name=item['asset'], url=url, size=len(data), sha256=digest, channel=channel, architecture=arch))
            rss = ET.Element('rss', version='2.0')
            feed = ET.SubElement(rss, 'channel')
            ET.SubElement(feed, 'title').text = item['name']
            release = ET.SubElement(feed, 'item')
            ET.SubElement(release, 'title').text = tag
            ET.SubElement(release, f'{{{NS}}}version').text = meta['build']
            ET.SubElement(release, f'{{{NS}}}shortVersionString').text = tag[1:]
            ET.SubElement(release, f'{{{NS}}}minimumSystemVersion').text = '14.4'
            ET.SubElement(release, 'description', {f'{{{NS}}}format': 'plain-text'}).text = (Path('release-notes') / (tag + '.md')).read_text()
            ET.SubElement(release, 'enclosure', {'url': url, 'length': str(len(data)), 'type': 'application/octet-stream', f'{{{NS}}}edSignature': base64.b64encode(signature).decode()})
            ET.indent(rss)
            ET.ElementTree(rss).write(feeds / f'{channel}-{arch}.xml', encoding='utf-8', xml_declaration=True)
            cask_url = url.replace(tag, 'v#{version}')
            sections.append(f'  on_{"arm" if arch == "arm64" else "intel"} do\n    sha256 "{digest}"\n\n    url "{cask_url}"\n  end')
        livecheck = '  livecheck do\n    url :url\n    strategy :github_latest\n  end' if channel == 'stable' else f"""  livecheck do
    url "https://api.github.com/repos/{REPOSITORY}/releases"
    strategy :json do |json|
      json
        .reject {{ |release| release["draft"] }}
        .map {{ |release| release["tag_name"].delete_prefix("v") }}
    end
  end"""
        (casks / filename).write_text(f'''cask "{token}" do
  version "{tag[1:]}"

{chr(10).join(sections)}

  name "{item['name']}"
  desc "Volume and brightness keys for external devices"
  homepage "https://github.com/{REPOSITORY}"

{livecheck}

  auto_updates true
  depends_on macos: :sonoma

  app "{item['name']}.app"

  zap trash: [
    "~/Library/Caches/{item['bundle_id']}",
    "~/Library/Preferences/{item['bundle_id']}.plist",
  ]
end
''')
    manifest = dict(schema_version=1, product='simple-mac-keyboard-control', source_repository=REPOSITORY,
        release_tag=tag, release_commit=os.environ['GITHUB_SHA'], channel='beta' if meta['prerelease'] else 'stable',
        casks=filenames, artifacts=artifacts,
        applications={c: package(tag,c,'arm64')['name'] + '.app' for c in meta['channels']},
        bundle_identifiers={c: package(tag,c,'arm64')['bundle_id'] for c in meta['channels']},
        architectures=['arm64','x64'], minimum_macos='14.4',
        native_validation=dict(workflow_run_id=int(os.environ['GITHUB_RUN_ID']), workflow_run_attempt=int(os.environ['GITHUB_RUN_ATTEMPT']), jobs=['Validate packages (arm64)', 'Validate packages (x64)']))
    root = output / 'publication'
    (root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (root / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n' for p in [root/'manifest.json', *sorted(casks.glob('*.rb'))]))
    with tarfile.open(output / 'homebrew-publication.tar.gz', 'w:gz') as archive:
        for p in sorted(root.rglob('*')):
            if p.is_file(): archive.add(p, arcname=str(p.relative_to(root)), recursive=False)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('tag'); parser.add_argument('assets', type=Path); parser.add_argument('output', type=Path)
    args = parser.parse_args()
    prepare(args.tag, args.assets, args.output, os.environ['SPARKLE_PRIVATE_ED_KEY'])
