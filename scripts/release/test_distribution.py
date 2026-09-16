import unittest
from unittest.mock import patch
from verify_distribution import select, check_feed, repository_file

class DistributionTests(unittest.TestCase):
    def test_repository_files_use_one_fresh_revision_per_pass(self):
        revisions = {}
        with patch('verify_distribution.subprocess.check_output', return_value='a' * 40 + '\n') as revision, \
             patch('verify_distribution.fetch', return_value=b'content') as fetch:
            repository_file('owner/repo', 'one', revisions)
            repository_file('owner/repo', 'two', revisions)
            self.assertEqual(revision.call_count, 1)
            self.assertEqual(fetch.call_args.args[0], 'https://raw.githubusercontent.com/owner/repo/' + 'a' * 40 + '/two')
            repository_file('owner/repo', 'one', {})
            self.assertEqual(revision.call_count, 2)

    def test_beta_may_be_newer_than_stable(self):
        releases = [dict(tag_name=t, draft=False, prerelease='beta' in t)
                    for t in ['v0.1.2', 'v0.2.0-beta.1']]
        self.assertEqual(select(releases, 'stable')['tag_name'], 'v0.1.2')
        self.assertEqual(select(releases, 'beta')['tag_name'], 'v0.2.0-beta.1')
        releases[1]['draft'] = True
        self.assertEqual(select(releases, 'beta')['tag_name'], 'v0.1.2')

    def test_stale_or_wrong_feed_fails(self):
        artifact = dict(name='test', url='https://example.org/test.zip', size=12)
        xml = '<rss xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><s:version>100290000</s:version><enclosure url="https://example.org/test.zip" length="12" s:edSignature="signature"/></item></channel></rss>'
        check_feed(xml, artifact, 'v0.1.2')
        for incorrect in [xml.replace('100290000', '100190000'), xml.replace('length="12"', 'length="13"'), xml.replace('test.zip', 'wrong.zip')]:
            with self.assertRaises(ValueError): check_feed(incorrect, artifact, 'v0.1.2')
