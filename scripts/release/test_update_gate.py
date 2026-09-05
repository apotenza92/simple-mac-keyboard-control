import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from update_gate import gate

class UpdateGateTests(unittest.TestCase):
    def test_only_first_release_can_establish_missing_feed_baseline(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'result.json'
            with patch('urllib.request.urlopen',side_effect=HTTPError('test',404,'missing',None,None)):
                gate('v0.1.0','stable','arm64',Path(d),Path(d),path)
                self.assertEqual(json.loads(path.read_text())['status'],'baseline-only')
                with self.assertRaises(HTTPError):gate('v0.1.1','stable','arm64',Path(d),Path(d),path)
    def test_server_failure_is_not_a_baseline(self):
        with tempfile.TemporaryDirectory() as d:
            with patch('urllib.request.urlopen',side_effect=HTTPError('test',503,'unavailable',None,None)):
                with self.assertRaises(HTTPError):gate('v0.1.0','stable','arm64',Path(d),Path(d),Path(d)/'result')
