"""Check package verification failure boundaries without launching Godot."""
from contextlib import redirect_stdout
from functools import lru_cache
import io
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import time
import unittest
import zlib
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_package


@lru_cache(maxsize=None)
def fixture_png(width=1280, height=720, color=6):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = (b'\0' + bytes(width * (4 if color == 6 else 3))) * height
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, color, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


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
            if name == 'MainFlow':
                report = self.main_flow_fixture()
                path = self.root / 'reports/main_flow.json'
                path.write_text(json.dumps(report), encoding='utf-8')
                record['report_sha256'] = verify_package.sha(path)
            if case.report_hashes or case.script_hashes:
                paths = [relative for _, relative in case.report_hashes] + list(case.script_hashes)
                for relative in paths:
                    path = self.root / relative
                    if not path.exists():
                        path.parent.mkdir(parents=True, exist_ok=True)
                        text = '> 文档 v0.5.7 · fixture\n' if relative == 'docs/GAME_DESIGN.md' else 'fixture input: ' + relative + '\n'
                        path.write_text(text, encoding='utf-8')
                context = verify_package.run_checks.case_artifact_context(case, self.root)
                report = {'passed': True, 'checks': 1, 'failures': [], 'program_version': '0.1.3.0', **context, **dict(case.required_report_values)}
                if case.final_phase:
                    report['phase'] = case.final_phase
                path = self.root / 'reports' / case.report_file
                path.write_text(json.dumps(report), encoding='utf-8')
                record.update(artifact_sha256=context, report_sha256=verify_package.sha(path))
            cases.append(record)
        return {'passed': True, 'program_version': '0.1.3.0', 'state': 'complete', 'suite': suite, 'cases': cases}

    def main_flow_fixture(self):
        context = {}
        for key, relative in (('units_sha256', 'resources/units.json'), ('stages_sha256', 'resources/stages.json')):
            path = self.root / relative
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{}', encoding='utf-8')
            context[key] = verify_package.sha(path)
        captures = []
        for name in verify_package.run_checks.MAIN_FLOW_CAPTURES:
            path = self.root / 'reports/runtime' / (name + '.png')
            path.write_bytes(fixture_png())
            captures.append({'name': name, 'path': 'res://reports/runtime/' + name + '.png', 'sha256': verify_package.sha(path), 'size': [1280, 720], 'window_mode': 0, 'display_window_mode': 0, 'window_visible': True, 'focused': True, 'actual_rendering_driver': 'vulkan'})
        return {'passed': True, 'checks': 1, 'failures': [], 'program_version': '0.1.3.0', 'real_spine': True, 'audio_shutdown_clean': True, 'normal_window_close': True, 'screenshots': 15, 'host_observed_frames': 20, 'host_normal_window_frames': 20, 'host_focused_frames': 20, 'engine_input_dispatch_verified': True, 'os_input_verified': False, 'capture_states': captures, **context}

    def change_study_report(self, suite, name, key, value):
        case = verify_package.run_checks.CASES[name]
        path = self.root / 'reports' / case.report_file
        report = json.loads(path.read_text(encoding='utf-8'))
        report[key] = value
        path.write_text(json.dumps(report), encoding='utf-8')
        next(item for item in suite['cases'] if item['case'] == name)['report_sha256'] = verify_package.sha(path)

    def font_fixture(self):
        for key, relative in verify_package.FONT_ART_HASHES:
            if key == 'font_manifest_sha256': continue
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(('fixture font input: ' + relative).encode())
        license_path = self.root / 'assets/fonts/OFL.txt'
        license_path.write_text('SIL OPEN FONT LICENSE Version 1.1\n', encoding='utf-8')
        active = {'family': 'Noto Sans SC', 'file': 'NotoSansSC.ttf',
                  'sha256': verify_package.sha(self.root / 'assets/fonts/NotoSansSC.ttf'),
                  'license': 'OFL.txt', 'license_sha256': verify_package.sha(license_path),
                  'source_url': 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf',
                  'body_weight': 400, 'emphasis_weight': 600,
                  'engine_family_aliases': ['Noto Sans SC', 'Noto Sans SC Thin']}
        (self.root / 'assets/fonts/manifest.json').write_text(json.dumps({'schema': 1, 'active': active}), encoding='utf-8')
        return {**{key: verify_package.sha(self.root / relative) for key, relative in verify_package.FONT_ART_HASHES},
                'ui_font_family': 'Noto Sans SC', 'body_weight': 400, 'emphasis_weight': 600,
                'font_engine_families': {'body': 'Noto Sans SC Thin', 'emphasis': 'Noto Sans SC Thin'},
                'font_engine_weights': {'body': 400.0, 'emphasis': 600.0},
                'font_engine_coordinates': {'body': [{verify_package.FONT_WEIGHT_TAG: 400.0}],
                                            'emphasis': [{verify_package.FONT_WEIGHT_TAG: 600.0}]},
                'font_glyph_check': True, 'font_glyph_characters': verify_package.FONT_ART_REQUIRED_CHARACTERS,
                'font_glyph_missing': [], 'font_glyph_variants': [400, 600]}

    def art_fixture(self):
        captures = []
        identities = ['guanyu', 'zhaoyun', 'zhugeliang', 'diaochan', 'lubu', 'iron_guard', 'ember_archer',
                      'rune_medic', 'rivet_gunner', 'moon_mage', 'star_hammer', 'spirit_beast']
        base = ['art_camp'] + ['art_hero_' + key for key in identities] + ['art_hero_collection_lower', 'art_squad', 'art_squad_lower',
                'art_chapter_1_left', 'art_chapter_1_right', 'art_chapter_2_left', 'art_chapter_2_right', 'art_gallery_hero', 'art_gallery_boss']
        names = base + list(verify_package.STUDY_ART_CAPTURES) + list(verify_package.BRIEFING_ART_CAPTURES) + list(verify_package.RESULT_ART_CAPTURES) + list(verify_package.SETTINGS_ART_CAPTURES)
        units_path = self.root / 'resources/units.json'
        units_path.parent.mkdir(parents=True, exist_ok=True)
        units_path.write_text(json.dumps({key: {'playable': True} for key in identities}), encoding='utf-8')
        for name in names:
            path = self.root / 'reports/runtime' / (name + '.png')
            path.write_bytes(fixture_png())
            captures.append({'name': name, 'path': 'res://reports/runtime/' + name + '.png',
                             'sha256': verify_package.sha(path), 'size': [1280, 720]})
        study_path = self.root / 'resources/studies.json'
        study_path.parent.mkdir(parents=True, exist_ok=True)
        study_path.write_text('{}', encoding='utf-8')
        extra_hashes = {}
        for key, relative in (('briefings_sha256', 'resources/briefings.json'), ('briefing_script_sha256', 'scripts/core/BattleBriefing.gd'),
                              ('main_sha256', 'scripts/ui/Main.gd'), ('stat_badge_sha256', 'scripts/ui/StatBadge.gd'),
                              ('battle_script_sha256', 'scripts/combat/SiegeBattle.gd'), ('settings_panel_sha256', 'scripts/ui/SettingsPanel.gd')):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}', encoding='utf-8')
            extra_hashes[key] = verify_package.sha(path)
        return {'root_window_mode': 1, 'screenshots': len(captures), 'captures': captures, 'portrait_count': 12,
                'text_overflows': [], 'audio_shutdown_clean': True, 'studies_sha256': verify_package.sha(study_path), **extra_hashes,
                **self.font_fixture(), **self.navigation_fixture(captures, identities)}

    def navigation_fixture(self, captures, identities):
        roster = identities[:8]
        by_name = {item['name']: item for item in captures}
        for name, page, prefix, selected in [('art_hero_spirit_beast', '英魂', 'HeroList', 'spirit_beast'),
                                              ('art_study_siege', '研修', 'StudyList', 'rivet_gunner'),
                                              ('art_squad', '编队', 'SquadList', None), ('art_squad_lower', '编队', 'SquadList', None)]:
            value = {'page': page, 'scroll_name': prefix + 'Scroll', 'grid_name': prefix + 'Grid', 'restore_ready': True,
                     'scroll_vertical': 180, 'view_rect': [254, 98, 442, 535]}
            if selected is not None:
                value.update(selected_id=selected, selected_card='HeroCard_' + selected, selected_rect=[254, 250, 207, 158],
                             selected_visible=True, selected_metadata=True)
            else:
                value.update(saved_roster=roster, cards=[{'unit_id': key, 'card_name': 'HeroCard_' + key, 'button_name': 'RosterToggle_' + key,
                            'slot': roster.index(key)+1 if key in roster else 0, 'button_slot': roster.index(key)+1 if key in roster else 0,
                            'button_text': '%d号位 · 移出' % (roster.index(key)+1) if key in roster else '加入编队'} for key in identities])
            by_name[name]['navigation'] = value
        digest = 'a' * 64
        return {'settings_navigation': {
            'failed': {'capture': 'art_settings_save_failed', 'control_names': ['SaveAndReturn', 'LeaveWithoutSave', 'UnsavedConsequence'],
                       'button_text': '暂不保存并返回', 'consequence_text': '本次设置立即生效，但尚未保存。\n若之后仍未保存，重启会恢复上次已保存的设置。',
                       'modal_active': True, 'save_failed': True, 'consequence_visible': True, 'runtime_preview_retained': True,
                       'dirty_retained': True, 'paused': True, 'preferences_before_sha256': digest, 'preferences_after_sha256': digest},
            'returned': {'capture': 'art_settings_temporary_return', 'modal_closed': True, 'pause_restored': True,
                         'battle_snapshot_unchanged': True, 'runtime_preview_retained': True, 'dirty_retained': True,
                         'cold_reloaded_previous_settings': True, 'preferences_before_sha256': digest, 'preferences_after_sha256': digest,
                         'profile_before_sha256': digest, 'profile_after_sha256': digest}}}

    def execute(self, payload=None, output='COMPLETE {}\n', name='case', marker='COMPLETE', exit_code=0, stderr='', hidden_render=False):
        def fake_run(*args, **kwargs):
            if name == 'checks' and isinstance(payload, dict) and any(case.get('case') == 'MainFlow' for case in payload.get('cases', [])):
                self.main_flow_fixture()  # The mock process creates the captures after cleanup.
            if payload is not None:
                path = self.root / 'reports/current.json'
                path.write_text(json.dumps(payload), encoding='utf-8')
                timestamp = time.time_ns()
                os.utime(path, ns=(timestamp, timestamp))
            return subprocess.CompletedProcess(args[0], exit_code, stdout=output, stderr=stderr)
        with patch.object(verify_package.subprocess, 'run', side_effect=fake_run), redirect_stdout(io.StringIO()):
            return verify_package.execute(self.root, name, ['unused'], marker, ['reports/current.json'], '0.1.3.0', 1, hidden_render=hidden_render)

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

    def test_previous_suite_cannot_omit_new_battle_and_result_checks(self):
        for suite_name in ('logic', 'full'):
            with self.subTest(suite=suite_name):
                suite = self.suite_fixture(suite_name)
                suite['cases'] = [item for item in suite['cases'] if item['case'] not in ('BattleReportSmoke', 'ResultUISmoke')]
                failures = verify_package.suite_check(suite, self.root, suite_name, '0.1.3.0')
                self.assertTrue(any('completed' in item and '-case' in item for item in failures), failures)

    def test_partial_suite_cannot_be_package_pass(self):
        self.assertFalse(self.execute({'passed': True, 'state': 'complete', 'suite': 'single', 'cases': [{'case': 'MainFlow', 'passed': True}]}, name='checks')['passed'])
        full = self.suite_fixture()
        self.assertTrue(self.execute(full, name='checks')['passed'])

    def test_old_five_and_seven_case_summaries_cannot_pass_current_suites(self):
        for suite, old_names in (('logic', tuple(verify_package.run_checks.CPU_CASES)[:5]),
                                 ('full', tuple(verify_package.run_checks.CPU_CASES)[:5] + verify_package.run_checks.VISUAL_CASES),
                                 ('logic', tuple(verify_package.run_checks.CPU_CASES)[:8]),
                                 ('full', tuple(verify_package.run_checks.CPU_CASES)[:8] + verify_package.run_checks.VISUAL_CASES)):
            with self.subTest(suite=suite):
                current = self.suite_fixture(suite)
                old = {**current, 'cases': [item for item in current['cases'] if item['case'] in old_names]}
                result = self.execute(old, name='checks_background' if suite == 'logic' else 'checks')
                self.assertFalse(result['passed'])
                self.assertTrue(any('completed ' in error for error in result['errors']))

    def test_study_runner_and_dedicated_report_hashes_cannot_be_forged(self):
        for name in ('StudyProfileSmoke', 'StudyCombatSmoke', 'StudyUISmoke', 'BriefingSmoke', 'BriefingUISmoke'):
            for key in ('artifact_sha256', 'report_sha256'):
                with self.subTest(case=name, field=key):
                    suite = self.suite_fixture()
                    record = next(item for item in suite['cases'] if item['case'] == name)
                    record[key] = 'forged'
                    result = self.execute(suite, name='checks')
                    self.assertFalse(result['passed'])
                    self.assertTrue(any('SHA differs: ' + name in error for error in result['errors']))

    def test_study_dedicated_report_must_exist_and_match_package_inputs(self):
        for name in ('StudyProfileSmoke', 'StudyCombatSmoke', 'StudyUISmoke', 'BriefingSmoke', 'BriefingUISmoke'):
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

    def test_briefing_package_reports_require_current_design_stages_and_full_matrix(self):
        for name in ('BriefingSmoke', 'BriefingUISmoke'):
            for key, expected in verify_package.run_checks.CASES[name].required_report_values:
                values = (None, True, str(expected), expected + 1, float(expected)) if type(expected) is int else (None, True, '0.5.4', '0.5.5')
                for value in values:
                    with self.subTest(case=name, field=key, value=value):
                        suite = self.suite_fixture()
                        self.change_study_report(suite, name, key, value)
                        result = self.execute(suite, name='checks')
                        self.assertFalse(result['passed'])
                        self.assertIn('study structured report required value differs: ' + name + '/' + key, result['errors'])

    def test_study_input_change_after_runner_report_cannot_pass_package(self):
        for relative in ('resources/studies.json', 'scripts/core/UnitStats.gd',
                         'scripts/combat/SiegeBattle.gd', 'resources/units.json', 'scripts/ui/Main.gd',
                         'docs/GAME_DESIGN.md', 'resources/briefings.json', 'scripts/core/BattleBriefing.gd', 'resources/stages.json', 'scripts/ui/StatBadge.gd'):
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
                'normal_window_frames': 300, 'full_resolution_frames': 300, 'actual_rendering_driver': 'vulkan',
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
                           ('display_window_size', '(640, 360)'), ('maximum_live_floating_numbers', 0),
                           ('actual_rendering_driver', 'opengl3'), ('actual_rendering_driver', None),
                           ('normal_window_frames', 299), ('full_resolution_frames', 299),
                           ('normal_window_frames', 300.0), ('full_resolution_frames', 300.0),
                           ('sample_frames', 300.0)]:
            with self.subTest(key=key):
                self.assertTrue(verify_package.performance_check({**good, key: value}, 64, self.policy))
        self.assertTrue(verify_package.performance_check(good, 24, self.policy))
        self.assertTrue(verify_package.performance_check(good, 64, self.policy, 2.0))
        self.assertEqual(verify_package.performance_check({**good, 'playback_multiplier': 2.0}, 64, self.policy, 2.0), [])
        for key in ('actual_rendering_driver', 'normal_window_frames', 'full_resolution_frames'):
            with self.subTest(missing=key):
                missing = good.copy()
                del missing[key]
                self.assertTrue(verify_package.performance_check(missing, 64, self.policy))

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
        (self.root / 'reports/runtime/art_camp.png').write_bytes(b'changed')
        self.assertTrue(verify_package.offscreen_check(good, 'art_review', self.root))

    def test_offscreen_art_rejects_old_counts_and_missing_studied_views(self):
        good = self.art_fixture()
        self.assertEqual(good['screenshots'], 56)
        for count in (22, 30, 32, 50, 54):
            with self.subTest(old_count=count):
                old = {**good, 'screenshots': count, 'captures': good['captures'][:count]}
                self.assertTrue(verify_package.offscreen_check(old, 'art_review', self.root))
        for name in verify_package.STUDY_ART_CAPTURES:
            with self.subTest(missing=name):
                renamed = [{**item, 'name': 'replacement'} if item['name'] == name else item for item in good['captures']]
                result = verify_package.offscreen_check({**good, 'captures': renamed}, 'art_review', self.root)
                self.assertIn('Offscreen art must include all ten study-state and studied-hero captures', result)

    def test_result_art_requires_all_four_outcome_and_recovery_views(self):
        for name in verify_package.RESULT_ART_CAPTURES:
            with self.subTest(capture=name):
                good = self.art_fixture()
                next(item for item in good['captures'] if item['name'] == name)['name'] = 'unrelated_result'
                failures = verify_package.offscreen_check(good, 'art_review', self.root)
                self.assertTrue(any('four result-report captures' in item for item in failures), failures)

    def test_settings_art_requires_both_named_failure_and_return_views_and_current_script(self):
        for name in verify_package.SETTINGS_ART_CAPTURES:
            with self.subTest(capture=name):
                good = self.art_fixture()
                next(item for item in good['captures'] if item['name'] == name)['name'] = 'unrelated_settings'
                failures = verify_package.offscreen_check(good, 'art_review', self.root)
                self.assertTrue(any('both failed-settings and temporary-return captures' in item for item in failures), failures)
        for kind in ('missing', 'forged', 'changed_after_capture'):
            with self.subTest(script=kind):
                good = self.art_fixture()
                if kind == 'missing': good.pop('settings_panel_sha256')
                elif kind == 'forged': good['settings_panel_sha256'] = 'old-settings-script'
                else: (self.root/'scripts/ui/SettingsPanel.gd').write_text('new settings UI')
                self.assertTrue(any('settings_panel_sha256' in item for item in verify_package.offscreen_check(good, 'art_review', self.root)))

    def test_navigation_art_rejects_self_reported_visibility_outside_actual_viewport(self):
        for key, value in [('selected_visible', False), ('selected_rect', [254, 700, 207, 158]),
                           ('selected_rect', [254, 250, True, 158]), ('selected_rect', [254, 250, float('nan'), 158]),
                           ('selected_id', 'guanyu'), ('selected_card', 'invented-card'), ('restore_ready', False),
                           ('scroll_name', 'old-scroll'), ('scroll_vertical', True), ('view_rect', [0, 0, 1920, 1080])]:
            with self.subTest(field=key):
                good = self.art_fixture()
                next(item for item in good['captures'] if item['name']=='art_hero_spirit_beast')['navigation'][key] = value
                self.assertTrue(verify_package.navigation_art_check(good, self.root))

    def test_navigation_art_slots_must_match_actual_saved_roster_and_all_twelve_cards(self):
        for key, value in [('slot', 8), ('button_slot', False), ('button_text', '已出战 · 移出'),
                           ('button_name', 'invented-toggle'), ('card_name', 'old-card')]:
            with self.subTest(field=key):
                good = self.art_fixture()
                navigation = next(item for item in good['captures'] if item['name']=='art_squad')['navigation']
                navigation['cards'][0][key] = value
                self.assertTrue(verify_package.navigation_art_check(good, self.root))
        for field, value in [('saved_roster', []), ('saved_roster', ['guanyu']*2), ('saved_roster', ['unknown']), ('cards', [])]:
            with self.subTest(field=field,value=value):
                good = self.art_fixture()
                next(item for item in good['captures'] if item['name']=='art_squad')['navigation'][field] = value
                self.assertTrue(verify_package.navigation_art_check(good, self.root))

    def test_settings_art_requires_visible_conditional_consequences_and_disk_runtime_invariants(self):
        for phase, key, value in [('failed','control_names',[]), ('failed','button_text','暂时返回'),
                                  ('failed','consequence_text','详情请看tooltip'), ('failed','consequence_visible',False),
                                  ('failed','modal_active',False), ('failed','preferences_after_sha256','b'*64),
                                  ('returned','modal_closed',False), ('returned','pause_restored',False),
                                  ('returned','dirty_retained',False), ('returned','runtime_preview_retained',False),
                                  ('returned','cold_reloaded_previous_settings',False), ('returned','profile_after_sha256','b'*64)]:
            with self.subTest(phase=phase,field=key):
                good = self.art_fixture();good['settings_navigation'][phase][key] = value
                self.assertTrue(verify_package.navigation_art_check(good, self.root))

    def test_preferences_suite_requires_new_settings_script_and_cold_return_evidence(self):
        for key,value in [('settings_panel_sha256','old-script'), ('user_prefs_sha256','old-prefs'),
                          ('temporary_return_verified',False), ('cold_reloaded_previous_settings',False), ('retry_saved_after_failure',False)]:
            with self.subTest(field=key):
                suite=self.suite_fixture('logic')
                self.change_study_report(suite,'PreferencesSmoke',key,value)
                self.assertTrue(verify_package.suite_check(suite,self.root,'logic','0.1.3.0'))

    def test_result_art_requires_the_current_battle_bookkeeping_script(self):
        for value in (None, 'expired'):
            with self.subTest(value=value):
                good = self.art_fixture()
                good['battle_script_sha256'] = value
                failures = verify_package.offscreen_check(good, 'art_review', self.root)
                self.assertTrue(any('battle_script_sha256' in item for item in failures), failures)

    def test_offscreen_art_requires_all_eighteen_briefing_views(self):
        good = self.art_fixture()
        self.assertEqual(len(verify_package.BRIEFING_ART_CAPTURES), 18)
        for name in verify_package.BRIEFING_ART_CAPTURES:
            with self.subTest(missing=name):
                renamed = [{**item, 'name': 'replacement'} if item['name'] == name else item for item in good['captures']]
                result = verify_package.offscreen_check({**good, 'captures': renamed}, 'art_review', self.root)
                self.assertIn('Offscreen art must include all eighteen battle-briefing captures', result)

    def test_offscreen_art_requires_current_briefing_configuration_and_script(self):
        for key, relative in (('briefings_sha256', 'resources/briefings.json'), ('briefing_script_sha256', 'scripts/core/BattleBriefing.gd')):
            for kind in ('missing', 'forged', 'changed'):
                with self.subTest(field=key, kind=kind):
                    good = self.art_fixture()
                    if kind == 'missing':
                        good.pop(key)
                    elif kind == 'forged':
                        good[key] = 'forged'
                    else:
                        (self.root / relative).write_text('changed after capture', encoding='utf-8')
                    self.assertIn('Offscreen briefing art SHA differs from this package: ' + key, verify_package.offscreen_check(good, 'art_review', self.root))

    def test_offscreen_art_requires_current_study_configuration_hash(self):
        good = self.art_fixture()
        self.assertTrue(verify_package.offscreen_check({**good, 'studies_sha256': 'forged'}, 'art_review', self.root))
        (self.root / 'resources/studies.json').write_text('{"changed": true}', encoding='utf-8')
        self.assertTrue(verify_package.offscreen_check(good, 'art_review', self.root))

    def test_art_reports_cannot_omit_or_reuse_expired_main_and_shared_widget(self):
        for hidden in (False, True):
            for key, relative in (('main_sha256', 'scripts/ui/Main.gd'), ('stat_badge_sha256', 'scripts/ui/StatBadge.gd')):
                for kind in ('missing', 'forged', 'changed_after_capture'):
                    with self.subTest(hidden_render=hidden, field=key, kind=kind):
                        good = {'passed': True, 'program_version': '0.1.3.0', **self.art_fixture()}
                        if kind == 'missing':
                            good.pop(key)
                        elif kind == 'forged':
                            good[key] = 'expired UI source'
                        else:
                            (self.root / relative).write_text('new UI source after capture', encoding='utf-8')
                        result = self.execute(good, name='art_review', hidden_render=hidden)
                        self.assertFalse(result['passed'])
                        self.assertIn('Offscreen UI art SHA differs from this package: ' + key, result['errors'])

    def test_art_font_hashes_require_current_theme_binary_manifest_and_variants(self):
        for hidden in (False, True):
            for key, relative in verify_package.FONT_ART_HASHES:
                for kind in ('missing', 'forged', 'changed_after_capture'):
                    with self.subTest(hidden_render=hidden, field=key, kind=kind):
                        good = {'passed': True, 'program_version': '0.1.3.0', **self.art_fixture()}
                        if kind == 'missing': good.pop(key)
                        elif kind == 'forged': good[key] = 'old font input'
                        else: (self.root / relative).write_bytes(b'new font input after capture')
                        result = self.execute(good, name='art_review', hidden_render=hidden)
                        self.assertFalse(result['passed'])
                        self.assertIn('Offscreen font art SHA differs from this package: ' + key, result['errors'])

    def test_art_font_requires_actual_family_weights_and_complete_glyph_coverage(self):
        good = self.font_fixture()
        self.assertEqual(verify_package.font_art_check(good, self.root), [])
        for key, value in (('ui_font_family', 'ZCOOL Kuaile'), ('body_weight', 100), ('body_weight', 400.0),
                           ('emphasis_weight', 400), ('emphasis_weight', 600.0), ('font_glyph_check', False),
                           ('font_glyph_check', 1), ('font_glyph_characters', '0123456789'),
                           ('font_glyph_missing', ['400:21147:力']), ('font_glyph_missing', None),
                           ('font_glyph_variants', [400]), ('font_glyph_variants', [400.0, 600.0])):
            with self.subTest(field=key, value=value):
                self.assertTrue(verify_package.font_art_check({**good, key: value}, self.root))
        for key in ('ui_font_family', 'body_weight', 'emphasis_weight', 'font_glyph_check',
                    'font_glyph_characters', 'font_glyph_missing', 'font_glyph_variants', 'font_engine_families'):
            with self.subTest(missing=key):
                missing = good.copy()
                missing.pop(key)
                self.assertTrue(verify_package.font_art_check(missing, self.root))

    def test_art_font_manifest_cannot_relabel_source_or_ignore_license(self):
        for key, value in (('family', 'ZCOOL Kuaile'), ('file', '../other.ttf'), ('license', '../other.txt'),
                           ('sha256', 'forged'), ('license_sha256', 'forged'), ('body_weight', 100),
                           ('emphasis_weight', 400), ('engine_family_aliases', ['ZCOOL Kuaile'])):
            with self.subTest(field=key):
                good = self.font_fixture()
                path = self.root / 'assets/fonts/manifest.json'
                manifest = json.loads(path.read_text())
                manifest['active'][key] = value
                path.write_text(json.dumps(manifest))
                good['font_manifest_sha256'] = verify_package.sha(path)
                self.assertTrue(verify_package.font_art_check(good, self.root))
        good = self.font_fixture()
        path = self.root / 'assets/fonts/OFL.txt'
        path.write_text('unrelated permission text')
        manifest_path = self.root / 'assets/fonts/manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['active']['license_sha256'] = verify_package.sha(path)
        manifest_path.write_text(json.dumps(manifest))
        good['font_manifest_sha256'] = verify_package.sha(manifest_path)
        self.assertIn('Current font OFL license is missing or changed', verify_package.font_art_check(good, self.root))

    def test_art_font_engine_name_must_match_verified_internal_alias(self):
        good = self.font_fixture()
        self.assertEqual(verify_package.font_art_check(good, self.root), [])
        for engine in ({'body': 'Noto Sans SC', 'emphasis': 'Other family'},
                       {'body': 'Noto Sans SC'}, {'body': 'Noto Sans SC', 'emphasis': 'Noto Sans SC', 'other': 'Noto Sans SC'}):
            with self.subTest(engine=engine):
                self.assertIn('Offscreen font engine families differ from verified source metadata',
                              verify_package.font_art_check({**good, 'font_engine_families': engine}, self.root))

    def test_art_font_declared_weights_cannot_replace_native_textserver_observation(self):
        good = self.font_fixture()
        self.assertEqual(verify_package.font_art_check(good, self.root), [])
        for field in ('font_engine_weights', 'font_engine_coordinates'):
            with self.subTest(missing=field):
                old_property_only = good.copy()
                old_property_only.pop(field)
                self.assertTrue(verify_package.font_art_check(old_property_only, self.root))
        for observed in ({'body': 100, 'emphasis': 100}, {'body': 400.5, 'emphasis': 600},
                         {'body': True, 'emphasis': 600}, {'body': 400, 'emphasis': float('nan')},
                         {'body': 400}, None):
            with self.subTest(actual_weights=observed):
                self.assertTrue(verify_package.font_art_check({**good, 'font_engine_weights': observed}, self.root))

    def test_art_font_requires_wght_coordinates_on_every_native_font_rid(self):
        good = self.font_fixture()
        for body in ([], [{}], [{'wght': 400}], [{verify_package.FONT_WEIGHT_TAG: 100}],
                     [{verify_package.FONT_WEIGHT_TAG: 400}, {verify_package.FONT_WEIGHT_TAG: 100}],
                     [{verify_package.FONT_WEIGHT_TAG: 400.5}], [{verify_package.FONT_WEIGHT_TAG: True}],
                     [None], None):
            with self.subTest(body_coordinates=body):
                coordinates = {'body': body, 'emphasis': [{verify_package.FONT_WEIGHT_TAG: 600}]}
                self.assertTrue(verify_package.font_art_check({**good, 'font_engine_coordinates': coordinates}, self.root))
        # Several RIDs are valid only when all their actual coordinates match.
        coordinates = {'body': [{verify_package.FONT_WEIGHT_TAG: 400}, {verify_package.FONT_WEIGHT_TAG: 400.0}],
                       'emphasis': [{verify_package.FONT_WEIGHT_TAG: 600}, {verify_package.FONT_WEIGHT_TAG: 600.0}]}
        self.assertEqual(verify_package.font_art_check({**good, 'font_engine_coordinates': coordinates}, self.root), [])

    def test_full_and_offscreen_art_reject_property_only_or_thin_font_reports(self):
        for hidden in (False, True):
            with self.subTest(hidden_render=hidden):
                good = {'passed': True, 'program_version': '0.1.3.0', **self.art_fixture()}
                for key in ('font_engine_weights', 'font_engine_coordinates'):
                    stale = good.copy()
                    stale.pop(key)
                    self.assertFalse(self.execute(stale, name='art_review', hidden_render=hidden)['passed'])
                thin = {**good, 'font_engine_weights': {'body': 100, 'emphasis': 100},
                        'font_engine_coordinates': {'body': [{}], 'emphasis': [{}]}}
                self.assertFalse(self.execute(thin, name='art_review', hidden_render=hidden)['passed'])

    def test_full_and_offscreen_art_use_the_same_complete_capture_gate(self):
        for hidden in (False, True):
            with self.subTest(hidden_render=hidden):
                good = {'passed': True, 'program_version': '0.1.3.0', **self.art_fixture()}
                self.assertTrue(self.execute(good, name='art_review', hidden_render=hidden)['passed'])
                for key, value in (('captures', []), ('screenshots', 32), ('screenshots', 50.0), ('studies_sha256', 'forged'), ('briefings_sha256', 'forged'), ('briefing_script_sha256', 'forged'), ('main_sha256', 'forged'), ('stat_badge_sha256', 'forged'), ('portrait_count', 11), ('text_overflows', ['cropped']), ('audio_shutdown_clean', False), ('root_window_mode', 0)):
                    with self.subTest(field=key):
                        self.assertFalse(self.execute({**good, key: value}, name='art_review', hidden_render=hidden)['passed'])

    def test_art_rejects_missing_truncated_and_wrong_actual_png_even_with_matching_sha(self):
        for raw in (None, b'not PNG', b'\x89PNG\r\n\x1a\n', fixture_png()[:-1], fixture_png(640, 360)):
            with self.subTest(bytes=None if raw is None else len(raw)):
                good = self.art_fixture()
                path = self.root / 'reports/runtime/art_camp.png'
                if raw is None:
                    path.unlink()
                else:
                    path.write_bytes(raw)
                    good['captures'][0]['sha256'] = verify_package.sha(path)
                self.assertTrue(verify_package.offscreen_check(good, 'art_review', self.root))

    def test_mainflow_requires_complete_host_observation_and_input_scope(self):
        good = self.main_flow_fixture()
        self.assertEqual(verify_package.main_flow_check(good, self.root), [])
        for key, value in (('host_observed_frames', 0), ('host_observed_frames', True), ('host_normal_window_frames', 19), ('host_normal_window_frames', 20.0), ('host_focused_frames', None), ('host_focused_frames', 19), ('engine_input_dispatch_verified', False), ('os_input_verified', True), ('capture_states', []), ('capture_states', None), ('screenshots', 32)):
            with self.subTest(field=key, value=value):
                self.assertTrue(verify_package.main_flow_check({**good, key: value}, self.root))

    def test_mainflow_capture_identity_host_size_and_hash_must_correspond(self):
        for key, value in (('window_mode', 1), ('window_mode', False), ('display_window_mode', 1), ('window_visible', False), ('focused', False), ('actual_rendering_driver', 'opengl3'), ('size', [1280.0, 720.0]), ('sha256', 'forged'), ('name', '06_chapter_two'), ('path', 'res://reports/runtime/06_chapter_two.png'), ('path', 'res://../outside.png')):
            with self.subTest(field=key, value=value):
                report = self.main_flow_fixture()
                report['capture_states'][0][key] = value
                self.assertTrue(verify_package.main_flow_check(report, self.root))

    def test_mainflow_rejects_actual_png_size_or_truncation_with_matching_hash(self):
        for raw in (fixture_png(640, 360), fixture_png()[:-1]):
            with self.subTest(bytes=len(raw)):
                report = self.main_flow_fixture()
                path = self.root / 'reports/runtime/01_campaign.png'
                path.write_bytes(raw)
                report['capture_states'][0]['sha256'] = verify_package.sha(path)
                self.assertTrue(verify_package.main_flow_check(report, self.root))

    def test_full_suite_consumes_shared_mainflow_and_dedicated_report_sha(self):
        for kind in ('missing', 'forged_sha', 'incomplete_host'):
            with self.subTest(kind=kind):
                suite = self.suite_fixture()
                record = next(case for case in suite['cases'] if case['case'] == 'MainFlow')
                path = self.root / 'reports/main_flow.json'
                if kind == 'missing':
                    path.unlink()
                elif kind == 'forged_sha':
                    record['report_sha256'] = 'forged'
                else:
                    report = json.loads(path.read_text(encoding='utf-8'))
                    report['host_focused_frames'] -= 1
                    path.write_text(json.dumps(report), encoding='utf-8')
                    record['report_sha256'] = verify_package.sha(path)
                self.assertFalse(self.execute(suite, name='checks')['passed'])

    def test_full_spine_still_rejects_background_reports(self):
        for name in ('playback', 'playback_unmanaged', 'mesh_redraw'):
            with self.subTest(case=name), patch.object(verify_package, 'playback_check', return_value=[]), patch.object(verify_package, 'mesh_redraw_check', return_value=[]):
                result = self.execute({'passed': True, 'program_version': '0.1.3.0', 'background': True}, name=name)
                self.assertFalse(result['passed'])
                self.assertIn('Full verification cannot reuse an offscreen Spine report', result['errors'])

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
