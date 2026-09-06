import base64
import hashlib
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat, PrivateFormat, NoEncryption
from prepare_publication import prepare
from install_feeds import install
from contract import parse_tag, package


class PublicationTests(unittest.TestCase):
    def test_channel_isolation_signatures_and_downgrade(self):
        for tag, expected in [('v0.1.0', 4), ('v0.2.0-beta.1', 2)]:
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as temporary:
                previous = Path.cwd()
                try:
                    os.chdir(temporary)
                    root = Path('.')
                    key = Ed25519PrivateKey.generate()
                    Path('Resources').mkdir(); Path('release-notes').mkdir(); Path('assets').mkdir()
                    Path('Resources/Info.plist').write_bytes(plistlib.dumps({'SUPublicEDKey': base64.b64encode(key.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)).decode()}))
                    Path(f'release-notes/{tag}.md').write_text('Test release')
                    for channel in parse_tag(tag)['channels']:
                        for arch in ['arm64','x64']:
                            asset = package(tag,channel,arch)['asset']; data=(channel+arch).encode()
                            Path('assets',asset).write_bytes(data)
                            Path('assets',asset+'.sha256').write_text(hashlib.sha256(data).hexdigest()+'  '+asset+'\n')
                    private=base64.b64encode(key.private_bytes(Encoding.Raw,PrivateFormat.Raw,NoEncryption())).decode()
                    with patch.dict(os.environ,GITHUB_SHA='a'*40,GITHUB_RUN_ID='1',GITHUB_RUN_ATTEMPT='1'):
                        prepare(tag,Path('assets'),Path('out'),private)
                    self.assertEqual(len(list(Path('out/appcasts').glob('*.xml'))),expected)
                    for cask in Path('out/publication/Casks').glob('*.rb'):
                        self.assertIn('v#{version}', cask.read_text())
                        self.assertNotIn('sha256 :no_check', cask.read_text())
                        if '@beta' in cask.name:
                            self.assertIn('strategy :github_releases do |json|', cask.read_text())
                            self.assertNotIn('api.github.com', cask.read_text())
                            self.assertNotIn('release["prerelease"]', cask.read_text())
                    Path('installed').mkdir(); install(Path('out/appcasts'),Path('installed'))
                    before={p.name:p.read_bytes() for p in Path('installed').glob('*.xml')}
                    install(Path('out/appcasts'),Path('installed'))
                    self.assertEqual(before,{p.name:p.read_bytes() for p in Path('installed').glob('*.xml')})
                    wrong=Ed25519PrivateKey.generate().private_bytes(Encoding.Raw,PrivateFormat.Raw,NoEncryption())
                    with self.assertRaises(ValueError): prepare(tag,Path('assets'),Path('wrong'),base64.b64encode(wrong).decode())
                finally: os.chdir(previous)

if __name__ == '__main__': unittest.main()
