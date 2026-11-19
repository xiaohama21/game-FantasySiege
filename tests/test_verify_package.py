"""Check package verification failure boundaries without launching Godot."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_package


class PackageVerificationBoundaries(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'reports/runtime').mkdir(parents=True)
        self.policy = {'renderer': 'mobile', 'render_thread_model': 'safe', 'managed_mesh_redraw': True,
                       'frame_group_count': 2, 'critical_instance_limit': 12}
        self.project_source = ('[application]\nconfig/version="0.1.3.0"\nconfig/features=PackedStringArray("4.7", "Mobile")\n'
                               '[rendering]\nrenderer/rendering_method="mobile"\nrenderer/rendering_method.mobile="mobile"\n'
                               'driver/threads/thread_model=1\n[fantasy_siege]\nvisuals/managed_mesh_redraw=true\n'
                               'visuals/frame_group_count=2\nvisuals/critical_instance_limit=12\n')
        (self.root / 'project.godot').write_text(self.project_source)

    def suite_fixture(self, suite='full'):
        cases = []
        names = verify_package.run_checks.CPU_CASES if suite == 'logic' else verify_package.run_checks.CASES
        for name in names:
            case = verify_package.run_checks.CASES[name]
            record = {'case': name, 'passed': True}
            if case.report_hashes or case.script_hashes:
                paths = [relative for _, relative in case.report_hashes] + list(case.script_hashes)
                for relative in paths:
                    path = self.root / relative
                    if not path.exists():
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text('fixture input: ' + relative + '\n', encoding='utf-8')
                context = verify_package.run_checks.case_artifact_context(case, self.root)
                report = {'passed': True, 'checks': 1, 'failures': [], 'program_version': '0.1.3.0', **context, **dict(case.required_report_values)}
                if case.final_phase:
                    report['phase'] = case.final_phase
                path = self.root / 'reports' / case.report_file
                path.write_text(json.dumps(report), encoding='utf-8')
                record.update(artifact_sha256=context, report_sha256=verify_package.sha(path))
            cases.append(record)
        return {'passed': True, 'program_version': '0.1.3.0', 'state': 'complete', 'suite': suite, 'cases': cases}

    def change_study_report(self, suite, name, key, value):
        case = verify_package.run_checks.CASES[name]
        path = self.root / 'reports' / case.report_file
        report = json.loads(path.read_text(encoding='utf-8'))
        report[key] = value
        path.write_text(json.dumps(report), encoding='utf-8')
        next(item for item in suite['cases'] if item['case'] == name)['report_sha256'] = verify_package.sha(path)

    def art_fixture(self):
        captures = []
        names = ['art_' + str(index) for index in range(22)] + list(verify_package.STUDY_ART_CAPTURES)
        for name in names:
            path = self.root / 'reports/runtime' / (name + '.png')
            path.write_bytes(('fixture ' + name).encode())
            captures.append({'name': name, 'path': 'res://reports/runtime/' + name + '.png',
                             'sha256': verify_package.sha(path), 'size': [1280, 720]})
        study_path = self.root / 'resources/studies.json'
        study_path.parent.mkdir(parents=True, exist_ok=True)
        study_path.write_text('{}', encoding='utf-8')
        return {'root_window_mode': 1, 'screenshots': len(captures), 'captures': captures, 'portrait_count': 12,
                'text_overflows': [], 'audio_shutdown_clean': True, 'studies_sha256': verify_package.sha(study_path)}

    def execute(self, payload=None, output='COMPLETE {}\n', name='case', marker='COMPLETE', exit_code=0, stderr=''):
        def fake_run(*args, **kwargs):
            if payload is not None:
                path = self.root / 'reports/current.json'
                path.write_text(json.dumps(payload), encoding='utf-8')
                timestamp = time.time_ns()
                os.utime(path, ns=(timestamp, timestamp))
            return subprocess.CompletedProcess(args[0], exit_code, stdout=output, stderr=stderr)
        with patch.object(verify_package.subprocess, 'run', side_effect=fake_run), redirect_stdout(io.StringIO()):
            return verify_package.execute(self.root, name, ['unused'], marker, ['reports/current.json'], '0.1.3.0', 1)

    def test_fresh_report_and_anchored_marker_pass(self):
        self.assertTrue(self.execute({'passed': True, 'program_version': '0.1.3.0'})['passed'])

    def test_old_pass_is_removed_when_process_writes_nothing(self):
        (self.root / 'reports/current.json').write_text('{"passed":true}')
        self.assertFalse(self.execute()['passed'])

    def test_missing_report_preserves_parse_error_and_process_exit_code(self):
        stdout = 'Godot Engine startup\n'
        stderr = 'SCRIPT ERROR: Parse Error: Cannot infer studied_gallery type\n   at: res://tests/ArtReview.gd:412\n'
        result = self.execute(output=stdout, name='art_review', marker='ART_REVIEW_COMPLETE', exit_code=1, stderr=stderr)
        self.assertFalse(result['passed'])
        self.assertEqual(result['exit_code'], 1)
        log = (self.root / result['log']).read_text(encoding='utf-8')
        self.assertTrue(log.startswith(stdout))
        self.assertIn(stderr.strip(), log)
        self.assertIn('[PACKAGE_VERIFICATION_EXCEPTION] FileNotFoundError:', log)
        self.assertLess(log.index('SCRIPT ERROR'), log.index('[PACKAGE_VERIFICATION_EXCEPTION]'))
        self.assertTrue(any('SCRIPT ERROR: Parse Error:' in error for error in result['errors']))

    def test_timeout_preserves_mixed_partial_output_and_failure(self):
        timeout = subprocess.TimeoutExpired(['unused'], 1, output=b'partial engine output', stderr='SCRIPT ERROR: stalled')
        with patch.object(verify_package.subprocess, 'run', side_effect=timeout), redirect_stdout(io.StringIO()):
            result = verify_package.execute(self.root, 'case', ['unused'], 'COMPLETE', ['reports/current.json'], '0.1.3.0', 1)
        self.assertFalse(result['passed'])
        self.assertIsNone(result['exit_code'])
        log = (self.root / result['log']).read_text(encoding='utf-8')
        self.assertIn('partial engine output', log)
        self.assertIn('SCRIPT ERROR: stalled', log)
        self.assertIn('[PACKAGE_VERIFICATION_EXCEPTION] TimeoutExpired:', log)

    def test_start_failure_records_reason_without_unbound_process(self):
        with patch.object(verify_package.subprocess, 'run', side_effect=FileNotFoundError('missing Godot')), redirect_stdout(io.StringIO()):
            result = verify_package.execute(self.root, 'case', ['unused'], 'COMPLETE', ['reports/current.json'], '0.1.3.0', 1)
        self.assertFalse(result['passed'])
        self.assertIsNone(result['exit_code'])
        log = (self.root / result['log']).read_text(encoding='utf-8')
        self.assertIn('FileNotFoundError: missing Godot', log)
        self.assertNotIn('UnboundLocalError', log)

    def test_invalid_report_shape_and_wrong_version_fail(self):
        self.assertFalse(self.execute([])['passed'])
        self.assertFalse(self.execute({'passed': True, 'version': '0.1.2.0'})['passed'])

    def test_error_leak_and_embedded_marker_fail(self):
        for output in ('COMPLETE {}\nerror: script failed\n', 'COMPLETE {}\nLeaked instance: audio\n', 'prefix COMPLETE {}\n'):
            with self.subTest(output=output):
                self.assertFalse(self.execute({'passed': True}, output)['passed'])

    def test_partial_suite_cannot_be_package_pass(self):
        self.assertFalse(self.execute({'passed': True, 'state': 'complete', 'suite': 'single', 'cases': [{'case': 'MainFlow', 'passed': True}]}, name='checks')['passed'])
        full = self.suite_fixture()
        self.assertTrue(self.execute(full, name='checks')['passed'])

    def test_old_five_and_seven_case_summaries_cannot_pass_current_suites(self):
        for suite, old_names in (('logic', tuple(verify_package.run_checks.CPU_CASES)[:5]),
                                 ('full', tuple(verify_package.run_checks.CPU_CASES)[:5] + verify_package.run_checks.VISUAL_CASES)):
            with self.subTest(suite=suite):
                current = self.suite_fixture(suite)
                old = {**current, 'cases': [item for item in current['cases'] if item['case'] in old_names]}
                result = self.execute(old, name='checks_background' if suite == 'logic' else 'checks')
                self.assertFalse(result['passed'])
                self.assertTrue(any('completed ' in error for error in result['errors']))

    def test_study_runner_and_dedicated_report_hashes_cannot_be_forged(self):
        for name in ('StudyProfileSmoke', 'StudyCombatSmoke', 'StudyUISmoke'):
            for key in ('artifact_sha256', 'report_sha256'):
                with self.subTest(case=name, field=key):
                    suite = self.suite_fixture()
                    record = next(item for item in suite['cases'] if item['case'] == name)
                    record[key] = 'forged'
                    result = self.execute(suite, name='checks')
                    self.assertFalse(result['passed'])
                    self.assertTrue(any('SHA differs: ' + name in error for error in result['errors']))

    def test_study_dedicated_report_must_exist_and_match_package_inputs(self):
        for name in ('StudyProfileSmoke', 'StudyCombatSmoke', 'StudyUISmoke'):
            with self.subTest(case=name, kind='missing'):
                suite = self.suite_fixture()
                case = verify_package.run_checks.CASES[name]
                (self.root / 'reports' / case.report_file).unlink()
                result = self.execute(suite, name='checks')
                self.assertFalse(result['passed'])
                self.assertIn('study structured report missing: ' + name, result['errors'])
            case = verify_package.run_checks.CASES[name]
            for key in verify_package.run_checks.case_artifact_context(case, self.root):
                with self.subTest(case=name, field=key):
                    suite = self.suite_fixture()
                    self.change_study_report(suite, name, key, 'forged')
                    result = self.execute(suite, name='checks')
                    self.assertFalse(result['passed'])
                    self.assertIn('study report input SHA differs: ' + name + '/' + key, result['errors'])

    def test_study_dedicated_report_requires_success_count_version_and_final_phase(self):
        invalid = (('passed', False), ('failures', ['broken assertion']), ('checks', 0),
                   ('checks', True), ('program_version', '0.1.2.0'), ('program_version', None), ('phase', 'checkpoint'))
        for key, value in invalid:
            with self.subTest(field=key, value=value):
                suite = self.suite_fixture()
                self.change_study_report(suite, 'StudyCombatSmoke', key, value)
                self.assertFalse(self.execute(suite, name='checks')['passed'])

    def test_study_combat_package_report_requires_exact_actual_spawn_matrix(self):
        for matrix in (None, 0, 107, 109, '108', True):
            with self.subTest(matrix_cases=matrix):
                suite = self.suite_fixture()
                self.change_study_report(suite, 'StudyCombatSmoke', 'matrix_cases', matrix)
                result = self.execute(suite, name='checks')
                self.assertFalse(result['passed'])
                self.assertIn('study structured report required value differs: StudyCombatSmoke/matrix_cases', result['errors'])

    def test_study_input_change_after_runner_report_cannot_pass_package(self):
        for relative in ('resources/studies.json', 'scripts/core/UnitStats.gd',
                         'scripts/combat/SiegeBattle.gd', 'resources/units.json', 'scripts/ui/Main.gd'):
            with self.subTest(input=relative):
                suite = self.suite_fixture()
                with (self.root / relative).open('a', encoding='utf-8') as file:
                    file.write('changed after runner report\n')
                self.assertFalse(self.execute(suite, name='checks')['passed'])

    def test_duplicate_or_failed_study_case_cannot_complete_suite(self):
        for kind in ('duplicate', 'failed'):
            with self.subTest(kind=kind):
                suite = self.suite_fixture()
                record = next(item for item in suite['cases'] if item['case'] == 'StudyUISmoke')
                if kind == 'duplicate':
                    record['case'] = 'StudyProfileSmoke'
                else:
                    record['passed'] = False
                self.assertFalse(self.execute(suite, name='checks')['passed'])

    def test_payload_hash_and_path_boundary_fail(self):
        payload = self.root / 'scene.gd'
        payload.write_text('original')
        manifest = {'files': [{'path': 'scene.gd', 'bytes': payload.stat().st_size, 'sha256': verify_package.sha(payload)}]}
        self.assertEqual(verify_package.payload_check(self.root, manifest), [])
        payload.write_text('modified')
        self.assertTrue(verify_package.payload_check(self.root, manifest))
        manifest['files'][0]['path'] = '../outside.gd'
        self.assertIn('outside package', verify_package.payload_check(self.root, manifest)[0])

    def test_only_exact_verbose_existing_nvapi_profile_is_diagnostic(self):
        message = 'NVAPI: Error creating application: NVAPI_EXECUTABLE_ALREADY_IN_USE(code -167)'
        self.assertEqual(verify_package.run_checks.fatal_lines(message), [])
        self.assertEqual(verify_package.run_checks.diagnostic_lines(message), [message])
        self.assertTrue(verify_package.run_checks.fatal_lines(message.replace('-167', '-999')))
        self.assertTrue(verify_package.run_checks.fatal_lines('ERROR: ' + message))

    def test_default_renderer_is_read_from_package(self):
        path = self.root / 'project.godot'
        for renderer in ('mobile', 'gl_compatibility'):
            path.write_text('[rendering]\nrenderer/rendering_method="' + renderer + '"\n')
            self.assertEqual(verify_package.project_renderer(self.root), renderer)
        path.write_text('[rendering]\n')
        with self.assertRaises(ValueError):
            verify_package.project_renderer(self.root)

    def test_foreground_performance_cannot_use_minimized_or_partial_population(self):
        good = {'window_mode': 0, 'window_visible': True, 'sample_frames': 300, 'focused_frames': 300,
                'hud_visible_frames': 300, 'total_instances': 64, 'native_instances': 64, 'alive_min': 64,
                'visible_min': 64, 'real_renderer': True, 'rendering_adapter': 'GTX1050',
                'actual_rendering_method': 'mobile', 'playback_multiplier': 1.0, 'p95_frame_ms': 31.0, 'fps_average': 45.0,
                'budget_valid_frames': 300, 'native_instances_min': 64, 'native_instances_max': 64, 'alive_max': 64,
                'visible_max': 64, 'production_renderer': 'mobile', 'render_thread_model': 'safe',
                'production_managed_mesh_redraw': True, 'production_frame_group_count': 2, 'critical_instance_limit': 12,
                'production_policy_override': False, 'managed_instances_min': 64, 'managed_instances_max': 64,
                'key_instances_60hz_min': 12, 'key_instances_60hz_max': 12,
                'low_priority_instances_min': 52, 'low_priority_instances_max': 52,
                'low_priority_frame_groups': {'2': 52, '3': 0, '4': 0},
                'frame_group_counts_min': {'2': 52, '3': 0, '4': 0}, 'frame_group_counts_max': {'2': 52, '3': 0, '4': 0},
                'viewport_size': '(1280, 720)', 'display_window_size': '(1280, 720)', 'maximum_live_floating_numbers': 3}
        self.assertEqual(verify_package.performance_check(good, 64, self.policy), [])
        for key, value in [('window_mode', 1), ('focused_frames', 299), ('native_instances', 63),
                           ('actual_rendering_method', 'gl_compatibility'), ('p95_frame_ms', float('nan')),
                           ('native_instances_min', 63), ('budget_valid_frames', 299), ('managed_instances_min', 63),
                           ('key_instances_60hz_min', 11), ('low_priority_instances_max', 53),
                           ('frame_group_counts_min', {'2': 0, '3': 0, '4': 52}), ('production_policy_override', True),
                           ('production_frame_group_count', 4), ('render_thread_model', 'separate'),
                           ('display_window_size', '(640, 360)'), ('maximum_live_floating_numbers', 0)]:
            with self.subTest(key=key):
                self.assertTrue(verify_package.performance_check({**good, key: value}, 64, self.policy))
        self.assertTrue(verify_package.performance_check(good, 24, self.policy))
        self.assertTrue(verify_package.performance_check(good, 64, self.policy, 2.0))
        self.assertEqual(verify_package.performance_check({**good, 'playback_multiplier': 2.0}, 64, self.policy, 2.0), [])

    def test_production_config_must_match_renderer_and_have_explicit_budget(self):
        path = self.root / 'project.godot'
        self.assertEqual(verify_package.project_policy(self.root), self.policy)
        for old, new in [('renderer/rendering_method.mobile="mobile"', 'renderer/rendering_method.mobile="gl_compatibility"'),
                         ('"4.7", "Mobile"', '"4.7", "GL Compatibility"'),
                         ('driver/threads/thread_model=1', 'driver/threads/thread_model=2'),
                         ('visuals/frame_group_count=2', 'visuals/frame_group_count=0'),
                         ('visuals/critical_instance_limit=12', 'visuals/critical_instance_limit=0'),
                         ('visuals/managed_mesh_redraw=true', '')]:
            with self.subTest(setting=old):
                path.write_text(self.project_source.replace(old, new))
                with self.assertRaises(ValueError):
                    verify_package.project_policy(self.root)

    def native_fixture(self):
        visuals, models = {}, []
        total = 4
        for index in range(21):
            visual_id = 'd69_' + str(index).zfill(3)
            actions = ['action_' + str(action) for action in range(20 if index == 20 else 10)]
            directory = self.root / 'assets/actors' / str(index).zfill(3)
            directory.mkdir(parents=True)
            (directory / 'actor.spine-json').write_text(json.dumps({'animations': dict.fromkeys(actions, {}), 'skins': [{'name': 'default'}]}))
            visuals[visual_id] = {'data': 'res://assets/actors/' + str(index).zfill(3) + '/actor-data.tres'}
            comparisons = len(actions) * 10
            models.append({'id': visual_id, 'raw_actions': len(actions), 'raw_action_names': actions,
                           'skins': ['default'], 'comparisons': comparisons})
            total += comparisons
        (self.root / 'resources').mkdir(exist_ok=True)
        (self.root / 'resources/visuals.json').write_text(json.dumps(visuals))
        return list(visuals), models, total

    def test_mesh_totals_cannot_replace_per_asset_action_coverage(self):
        visual_ids, models, comparisons = self.native_fixture()
        good = {'resource_count': 21, 'raw_animation_count': 220, 'native_visual_ids': visual_ids, 'models': models,
                'actual_rendering_method': 'mobile', 'rendering_adapter': 'GTX1050', 'real_renderer': True,
                'render_thread_model': 'safe', 'max_pixel_difference': 0, 'comparisons': comparisons}
        self.assertEqual(verify_package.mesh_redraw_check(good, self.root, self.policy), [])
        for key, value in [('actual_rendering_method', 'gl_compatibility'), ('max_pixel_difference', 1),
                           ('raw_animation_count', 219), ('comparisons', comparisons - 1),
                           ('models', models[:-1] + models[:1])]:
            with self.subTest(key=key):
                self.assertTrue(verify_package.mesh_redraw_check({**good, key: value}, self.root, self.policy))
        missing_action = {**models[0], 'raw_action_names': models[0]['raw_action_names'][:-1]}
        self.assertTrue(verify_package.mesh_redraw_check({**good, 'models': [missing_action] + models[1:]}, self.root, self.policy))

    def test_playback_requires_production_identity_and_all_visual_ids(self):
        visual_ids, _, _ = self.native_fixture()
        good = {'native_visuals': 21, 'native_visual_ids': visual_ids, 'actual_rendering_method': 'mobile',
                'real_renderer': True, 'render_thread_model': 'safe', 'managed_mesh_redraw': True,
                'production_managed_mesh_redraw': True, 'production_policy_override': False, 'playback_policy': 'production',
                'tested_speeds': [0, 1, 2], 'tested_sample_rates': [30, 60], 'tested_frame_groups': [2, 3, 4],
                'group_switch_keeps_pending_delta': True, 'reconfigure_and_free': True}
        self.assertEqual(verify_package.playback_check(good, self.root, self.policy, True), [])
        for key, value in [('native_visual_ids', visual_ids[:-1] + visual_ids[:1]), ('playback_policy', 'managed_candidate'),
                           ('production_policy_override', True), ('managed_mesh_redraw', False), ('tested_speeds', [1]),
                           ('actual_rendering_method', 'gl_compatibility')]:
            with self.subTest(key=key):
                self.assertTrue(verify_package.playback_check({**good, key: value}, self.root, self.policy, True))
        control = {**good, 'managed_mesh_redraw': False, 'production_policy_override': True, 'playback_policy': 'unmanaged_control'}
        self.assertEqual(verify_package.playback_check(control, self.root, self.policy, False), [])

    def test_native_total_cannot_replace_unique_ids_or_each_raw_animation_count(self):
        visual_ids, models, _ = self.native_fixture()
        results = [{'visual_id': visual_id, 'passed': True, 'animation_count': model['raw_actions']}
                   for visual_id, model in zip(visual_ids, models)]
        config_sha = verify_package.sha(self.root / 'resources/visuals.json')
        report = {'results': results, 'selected_visual_ids': visual_ids, 'config_unchanged': True,
                  'config_sha256_before': config_sha, 'config_sha256_after': config_sha,
                  'update_status_requested': False, 'config_write_performed': False}
        self.assertEqual(verify_package.native_check(report, self.root), [])
        self.assertTrue(verify_package.native_check({**report, 'results': results[:-1] + results[:1]}, self.root))
        wrong_counts = [{**results[0], 'animation_count': 9}, {**results[1], 'animation_count': 11}] + results[2:]
        self.assertEqual(sum(item['animation_count'] for item in wrong_counts), 220)
        self.assertTrue(verify_package.native_check({**report, 'results': wrong_counts}, self.root))
        self.assertTrue(verify_package.native_check({**report, 'results': [{**results[0], 'passed': False}] + results[1:]}, self.root))
        for key, value in [('config_unchanged', False), ('config_sha256_before', 'old'),
                           ('config_sha256_after', 'old'), ('update_status_requested', True),
                           ('config_write_performed', True), ('selected_visual_ids', visual_ids[:-1])]:
            with self.subTest(key=key):
                self.assertTrue(verify_package.native_check({**report, key: value}, self.root))

    def test_offscreen_playback_requires_minimized_vulkan_without_performance(self):
        good = {'background': True, 'performance_measured': False, 'root_window_mode': 1,
                'display_window_mode': 1, 'actual_rendering_driver': 'vulkan', 'background_host_valid_resources': 21}
        self.assertEqual(verify_package.offscreen_check(good, 'playback', self.root), [])
        for key, value in [('background', False), ('performance_measured', True), ('root_window_mode', 0),
                           ('display_window_mode', 0), ('actual_rendering_driver', 'opengl3'),
                           ('background_host_valid_resources', 20)]:
            with self.subTest(key=key):
                self.assertTrue(verify_package.offscreen_check({**good, key: value}, 'playback', self.root))

    def test_offscreen_mesh_requires_every_capture_and_full_transparent_viewports(self):
        viewport = {'size': [1000, 760], 'transparent_bg': True, 'disable_3d': True}
        good = {'background': True, 'performance_measured': False, 'root_window_mode': 1,
                'display_window_mode': 1, 'actual_rendering_driver': 'vulkan', 'comparisons': 2624,
                'background_host_valid_captures': 2624, 'viewports': [viewport, viewport.copy()]}
        self.assertEqual(verify_package.offscreen_check(good, 'mesh_redraw', self.root), [])
        for key, value in [('background_host_valid_captures', 2623), ('comparisons', 220),
                           ('viewports', [viewport]), ('viewports', [viewport, {**viewport, 'transparent_bg': False}])]:
            with self.subTest(key=key, value=value):
                self.assertTrue(verify_package.offscreen_check({**good, key: value}, 'mesh_redraw', self.root))

    def test_hidden_render_launch_sets_hidden_startup_without_relaxing_logs(self):
        payload = {'passed': True, 'program_version': '0.1.3.0', 'background': True, 'performance_measured': False,
                   'root_window_mode': 1, 'display_window_mode': 1, 'actual_rendering_driver': 'vulkan'}
        def fake_run(command, **kwargs):
            if os.name == 'nt':
                self.assertEqual(kwargs['startupinfo'].wShowWindow, 0)
            (self.root / 'reports/current.json').write_text(json.dumps(payload))
            return subprocess.CompletedProcess(command, 0, stdout='COMPLETE\n', stderr='ERROR: failed offscreen capture')
        with patch.object(verify_package.subprocess, 'run', side_effect=fake_run), redirect_stdout(io.StringIO()):
            result = verify_package.execute(self.root, 'case', ['unused'], 'COMPLETE', ['reports/current.json'], '0.1.3.0', 1, hidden_render=True)
        self.assertTrue(result['hidden_render'])
        self.assertFalse(result['passed'])
        self.assertTrue(result['errors'])

    def test_offscreen_art_requires_all_image_hashes_and_audio_exit(self):
        good = self.art_fixture()
        self.assertEqual(verify_package.offscreen_check(good, 'art_review', self.root), [])
        self.assertTrue(verify_package.offscreen_check({**good, 'audio_shutdown_clean': False}, 'art_review', self.root))
        (self.root / 'reports/runtime/art_0.png').write_bytes(b'changed')
        self.assertTrue(verify_package.offscreen_check(good, 'art_review', self.root))

    def test_offscreen_art_rejects_old_counts_and_missing_studied_views(self):
        good = self.art_fixture()
        self.assertEqual(good['screenshots'], 32)
        for count in (22, 30):
            with self.subTest(old_count=count):
                old = {**good, 'screenshots': count, 'captures': good['captures'][:count]}
                self.assertTrue(verify_package.offscreen_check(old, 'art_review', self.root))
        for name in verify_package.STUDY_ART_CAPTURES:
            with self.subTest(missing=name):
                renamed = [{**item, 'name': 'replacement'} if item['name'] == name else item for item in good['captures']]
                result = verify_package.offscreen_check({**good, 'captures': renamed}, 'art_review', self.root)
                self.assertIn('Offscreen art must include all ten study-state and studied-hero captures', result)

    def test_offscreen_art_requires_current_study_configuration_hash(self):
        good = self.art_fixture()
        self.assertTrue(verify_package.offscreen_check({**good, 'studies_sha256': 'forged'}, 'art_review', self.root))
        (self.root / 'resources/studies.json').write_text('{"changed": true}', encoding='utf-8')
        self.assertTrue(verify_package.offscreen_check(good, 'art_review', self.root))

    def test_offscreen_phase_uses_only_hidden_cases_and_never_marks_delivery_ready(self):
        self.native_fixture()
        (self.root / 'resources/units.json').write_text('{}')
        (self.root / 'resources/stages.json').write_text('[]')
        (self.root / 'reports/build_manifest.json').write_text(json.dumps({'program_version': '0.1.3.0', 'files': []}))
        # An unrelated incomplete full-run report must not affect this phase.
        (self.root / 'reports/main_flow.json').write_text('invalid stale full report')
        (self.root / 'reports/package_verification.json').write_text('keep-full-result')
        observed = []
        def fake_execute(package, name, command, marker, reports, version, timeout, hidden_render=False):
            observed.append((name, command, hidden_render))
            log = 'reports/package_' + name + '.log'
            (package / log).write_text('COMPLETE\n')
            return {'case': name, 'passed': True, 'log': log}
        with patch.object(verify_package, 'execute', side_effect=fake_execute), \
             patch.object(verify_package, 'payload_check', return_value=[]) as payload, \
             patch.object(verify_package, 'portrait_check', return_value=[]) as portraits, \
             redirect_stdout(io.StringIO()):
            code = verify_package.main(['--package', str(self.root), '--phase', 'offscreen'])
        self.assertEqual(code, 0)
        self.assertEqual([item[0] for item in observed], ['playback', 'playback_unmanaged', 'mesh_redraw', 'art_review'])
        self.assertTrue(all(item[2] for item in observed))
        self.assertTrue(all('background' in command for name, command, _ in observed if name != 'art_review'))
        self.assertEqual(payload.call_count, 2)
        self.assertEqual(portraits.call_count, 2)
        summary = json.loads((self.root / 'reports/package_offscreen.json').read_text())
        self.assertTrue(summary['passed'])
        self.assertFalse(summary['delivery_ready'])
        self.assertFalse(summary['performance_verified'])
        self.assertEqual(summary['verification_phase'], 'offscreen')
        self.assertEqual((self.root / 'reports/package_verification.json').read_text(), 'keep-full-result')

    def test_background_suite_requires_all_cpu_checks(self):
        logic = self.suite_fixture('logic')
        self.assertTrue(self.execute(logic, name='checks_background')['passed'])
        self.assertFalse(self.execute({**logic, 'cases': logic['cases'][:-1]}, name='checks_background')['passed'])


if __name__ == '__main__':
    unittest.main()
