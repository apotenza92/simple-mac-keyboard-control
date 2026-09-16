import unittest
from unittest.mock import patch
from follow_publication import follow, validate_run


class FollowPublicationTests(unittest.TestCase):
    def run_record(self, **changes):
        return dict(dict(path='.github/workflows/release.yml', event='push',
                         head_branch='v0.1.3', head_sha='abc', status='completed',
                         conclusion='success'), **changes)

    def test_only_matching_successful_release_can_dispatch(self):
        self.assertTrue(validate_run(self.run_record(), 'v0.1.3', 'abc'))
        for change in [dict(conclusion='failure'), dict(conclusion='cancelled'),
                       dict(head_sha='other'), dict(head_branch='v0.1.2'),
                       dict(path='.github/workflows/ci.yml'), dict(event='workflow_dispatch')]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_run(self.run_record(**change), 'v0.1.3', 'abc')

    def test_dispatch_follows_release_success_and_precedes_verification(self):
        pending = self.run_record(status='in_progress', conclusion=None)
        with patch('follow_publication.api', side_effect=[{'sha': 'abc'}, pending, self.run_record()]), \
             patch('follow_publication.time.sleep'), patch('follow_publication.subprocess.run') as run:
            follow('v0.1.3', 123, 60)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[0].args[0][0:4], ['gh', 'workflow', 'run', 'reconcile-keycontrol.yml'])
        self.assertIn('--wait-seconds', run.call_args_list[1].args[0])

    def test_failure_never_dispatches(self):
        with patch('follow_publication.api', side_effect=[{'sha': 'abc'}, self.run_record(conclusion='failure')]), \
             patch('follow_publication.subprocess.run') as run, self.assertRaises(ValueError):
            follow('v0.1.3', 123, 60)
        run.assert_not_called()
