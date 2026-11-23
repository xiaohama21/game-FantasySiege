"""Verify native-runner byte preservation and failure gates with mocked processes."""
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_spine
import qa_mock


class NativeVerificationBoundaries(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='FantasySiegeNativeTests_')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'resources').mkdir()
        (self.root / 'reports/spine_probes').mkdir(parents=True)
        (self.root / 'project.godot').write_text('[application]\nconfig/version="0.1.3.0"\n')
        self.keys = ['d69_' + str(index).zfill(3) for index in range(21)]
        self.config = {key: {'status': 'converted', 'name': '独立素材 ' + key} for key in self.keys}
        self.config[self.keys[1]]['status'] = 'visual_checked'
        self.config[self.keys[2]]['status'] = 'performance_checked'
        self.original = b'\xef\xbb\xbf' + json.dumps(self.config, ensure_ascii=False, separators=(',', ' : ')).encode('utf-8') + b'\r\n'
        self.path = self.root / 'resources/visuals.json'
        self.path.write_bytes(self.original)
        qa_mock.scripts(self.root)
        root_patch = patch.object(verify_spine, 'ROOT', self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def success(self, command, **kwargs):
        qa_mock.emit(command, self.root)
        self.assertEqual(command[command.index('--path') + 1], str(self.root))
        self.assertIn('--headless', command)
        user_start = command.index("--") + 1
        key = command[user_start]
        path = Path(command[user_start + 1])
        self.assertFalse(path.exists(), 'each native report must be cleared before launch')
        path.write_text(json.dumps({'passed': True, 'native': True, 'visual_id': key,
                                    'errors': [], 'animations': [{'name': 'idle', 'visible_samples': 36}]}))
        return subprocess.CompletedProcess(command, 0, stdout='SPINE_PROBE_COMPLETE {}\n', stderr='')

    def run_verify(self, callback=None, keys=None, update=False):
        chosen = keys or self.keys
        args = ['--godot', 'unused-engine.exe', '--ids', ','.join(key.removeprefix('d69_') for key in chosen)]
        if update:
            args.append('--update-status')
        with patch.object(verify_spine.subprocess, 'run', side_effect=callback or self.success) as engine, redirect_stdout(io.StringIO()):
            code = verify_spine.main(args)
        report = json.loads((self.root / 'reports/spine_verify.json').read_text())
        return code, report, engine.call_count

    def assert_original_bytes(self, report):
        digest = hashlib.sha256(self.original).hexdigest()
        self.assertEqual(self.path.read_bytes(), self.original)
        self.assertTrue(report['config_unchanged'])
        self.assertFalse(report['config_write_performed'])
        self.assertEqual(report['config_sha256_before'], digest)
        self.assertEqual(report['config_sha256_after'], digest)

    def test_all_21_isolated_probes_keep_nonstandard_recipe_bytes_and_current_scope(self):
        (self.root / 'reports/spine_verify.json').write_text('{"results":[{"visual_id":"stale_old_pass","passed":true}]}')
        code, report, count = self.run_verify()
        self.assertEqual(code, 0)
        self.assertEqual(count, 21)
        self.assertEqual(report['selected_visual_ids'], self.keys)
        self.assertEqual([item['visual_id'] for item in report['results']], self.keys)
        self.assertFalse(report['update_status_requested'])
        self.assert_original_bytes(report)

    def test_failed_and_leaking_probes_never_write_default_recipes(self):
        for failure in ('nonzero', 'SCRIPT ERROR: failed', 'Leaked instance: SpineSprite', 'ObjectDB instances leaked at exit'):
            with self.subTest(failure=failure):
                def noisy(command, **kwargs):
                    response = self.success(command, **kwargs)
                    if command[command.index("--") + 1] == self.keys[0]:
                        if failure == 'nonzero':
                            response.returncode = 1
                        else:
                            response.stderr = failure
                    return response
                code, report, count = self.run_verify(noisy)
                self.assertEqual(code, 1)
                self.assertEqual(count, 21)
                self.assertFalse(report['results'][0]['passed'])
                self.assert_original_bytes(report)

    def test_embedded_or_prefix_completion_markers_are_rejected(self):
        for output in ('prefix SPINE_PROBE_COMPLETE {}\n', 'SPINE_PROBE_COMPLETE_FAILED\n'):
            with self.subTest(output=output):
                def wrong_marker(command, **kwargs):
                    response = self.success(command, **kwargs)
                    response.stdout = output
                    return response
                code, report, _ = self.run_verify(wrong_marker, [self.keys[0]])
                self.assertEqual(code, 1)
                self.assertIn('completion_marker_missing', report['results'][0]['errors'])
                self.assert_original_bytes(report)

    def test_timeout_and_missing_fresh_report_cannot_reuse_old_native_pass(self):
        key = self.keys[0]
        (self.root / 'reports/spine_probes' / (key + '.json')).write_text('{"passed":true}')
        def missing(command, **kwargs):
            self.assertFalse(Path(command[command.index("--") + 2]).exists())
            return subprocess.CompletedProcess(command, 0, stdout='SPINE_PROBE_COMPLETE {}\n', stderr='')
        code, report, _ = self.run_verify(missing, [key])
        self.assertEqual(code, 1)
        self.assertIn('fresh_report_missing', report['results'][0]['errors'])
        self.assert_original_bytes(report)
        def timeout(command, **kwargs):
            raise subprocess.TimeoutExpired(command, 50, output=b'partial native output', stderr='ERROR: stopped')
        code, report, _ = self.run_verify(timeout, [key])
        self.assertEqual(code, 1)
        self.assertIn('timeout', report['results'][0]['errors'])
        self.assertIn('ERROR: stopped', (self.root / 'reports/spine_probes' / (key + '.log')).read_text())
        self.assert_original_bytes(report)

    def test_explicit_author_update_changes_only_selected_runtime_status(self):
        code, report, count = self.run_verify(keys=[self.keys[0]], update=True)
        self.assertEqual(code, 0)
        self.assertEqual(count, 1)
        updated = json.loads(self.path.read_text(encoding='utf-8'))
        self.assertEqual(updated[self.keys[0]]['status'], 'runtime_pass')
        for key in self.keys[1:]:
            self.assertEqual(updated[key], self.config[key])
        self.assertTrue(report['update_status_requested'])
        self.assertTrue(report['config_write_performed'])
        self.assertFalse(report['config_unchanged'])
        self.assertEqual(report['results'][0]['previous_status'], 'converted')

    def test_explicit_success_preserves_higher_validation_grades_and_format(self):
        code, report, _ = self.run_verify(keys=self.keys[1:3], update=True)
        self.assertEqual(code, 0)
        self.assertTrue(report['update_status_requested'])
        self.assert_original_bytes(report)

    def test_external_recipe_change_is_detected_without_overwriting_it(self):
        mutated = self.original + b'\n'
        def changed(command, **kwargs):
            response = self.success(command, **kwargs)
            self.path.write_bytes(mutated)
            return response
        code, report, _ = self.run_verify(changed, [self.keys[0]])
        self.assertEqual(code, 1)
        self.assertEqual(self.path.read_bytes(), mutated)
        self.assertFalse(report['config_unchanged'])
        self.assertFalse(report['config_write_performed'])
        self.assertIn('source configuration changed during verification', report['failures'])


if __name__ == '__main__':
    unittest.main()
