import unittest
from verify_distribution import select, check_feed

class DistributionTests(unittest.TestCase):
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
