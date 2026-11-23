"""Exercise runner failure boundaries without launching Godot or rendering."""
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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import run_checks
import qa_mock


@lru_cache(maxsize=None)
def fixture_png(width=1280, height=720, color=6):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = (b'\0' + bytes(width * (4 if color == 6 else 3))) * height
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, color, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


class StrictRunnerBoundaries(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="fantasysiege_checks_")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "reports").mkdir()
        (self.root / "project.godot").write_text('config_version=5\n[application]\nconfig/version="0.1.3.0"\n', encoding="utf-8")
        for case in run_checks.CASES.values():
            paths = [relative for _, relative in case.report_hashes] + list(case.script_hashes)
            for relative in paths:
                path = self.root / relative
                if not path.exists():
                    path.parent.mkdir(parents=True, exist_ok=True)
                    text = "> 文档 v0.5.7 · fixture\n" if relative == "docs/GAME_DESIGN.md" else "fixture input: " + relative + "\n"
                    path.write_text(text, encoding="utf-8")
        qa_mock.scripts(self.root)
        root_patch = patch.object(run_checks, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def case_for(self, command):
        name = command[command.index("--script") + 1].rsplit("/", 1)[-1].removesuffix(".gd")
        return run_checks.CASES[name]

    def payload(self, case):
        data = {"passed": True, "checks": 1, "failures": [], "program_version": "0.1.3.0"}
        if case.final_phase:
            data["phase"] = case.final_phase
        data.update(run_checks.case_artifact_context(case))
        data.update(dict(case.required_report_values))
        if case.name == 'MainFlow':
            data.update(self.main_flow_fixture())
        if case.name == 'CampaignJourney':
            data['restart'] = {'qa_startup': qa_mock.record(self.root, 'journey_child')}
        return data

    def main_flow_fixture(self):
        (self.root / 'reports/runtime').mkdir(exist_ok=True)
        context = {}
        for key, relative in (('units_sha256', 'resources/units.json'), ('stages_sha256', 'resources/stages.json')):
            path = self.root / relative
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{}', encoding='utf-8')
            context[key] = run_checks.hashlib.sha256(path.read_bytes()).hexdigest()
        captures = []
        for name in run_checks.MAIN_FLOW_CAPTURES:
            path = self.root / 'reports/runtime' / (name + '.png')
            path.write_bytes(fixture_png())
            captures.append({'name': name, 'path': 'res://reports/runtime/' + name + '.png', 'sha256': run_checks.hashlib.sha256(path.read_bytes()).hexdigest(), 'size': [1280, 720], 'window_mode': 0, 'display_window_mode': 0, 'window_visible': True, 'focused': True, 'actual_rendering_driver': 'vulkan'})
        return {'real_spine': True, 'audio_shutdown_clean': True, 'normal_window_close': True, 'screenshots': 15, 'host_observed_frames': 20, 'host_normal_window_frames': 20, 'host_focused_frames': 20, 'engine_input_dispatch_verified': True, 'os_input_verified': False, 'capture_states': captures, **context}

    def write_report(self, case, data):
        path = self.root / "reports" / case.report_file
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def success(self, command, **kwargs):
        qa_mock.emit(command, self.root)
        case = self.case_for(command)
        self.assertFalse((self.root / "reports" / case.report_file).exists(), "report must be cleared before launch")
        self.write_report(case, self.payload(case))
        return subprocess.CompletedProcess(command, 0, stdout=case.marker + " completed\n", stderr="")

    def run_case(self, callback=None, name="ProfileSmoke", verbose_render_diagnostics=False):
        with patch.object(run_checks.subprocess, "run", side_effect=callback or self.success):
            return run_checks.run_case(run_checks.CASES[name], Path("mock-godot.exe"), run_checks.project_context(), verbose_render_diagnostics)

    def test_guide_case_is_in_cpu_suite_and_requires_current_binding_and_no_foreground_claim(self):
        self.assertIn('GuideUISmoke', run_checks.CPU_CASES)
        case = run_checks.CASES['GuideUISmoke']
        result = self.run_case(name=case.name)
        self.assertTrue(result['passed'], result['errors'])
        self.assertEqual(case.final_phase, 'complete')
        self.assertEqual(set(result['artifact_sha256']), {'project_sha256', 'gdd_sha256', 'gdd_version', 'main_sha256', 'guide_panel_sha256', 'user_prefs_sha256'})

    def test_guide_missing_rules_or_preference_guard_cannot_pass(self):
        case = run_checks.CASES['GuideUISmoke']
        for key, value in (('pages_verified', 2), ('guide_preference_failure_verified', False),
                           ('guide_cold_reload_verified', False), ('guide_exit_layer_verified', False),
                           ('foreground_verified', True), ('input_device_verified', True),
                           ('guide_panel_sha256', 'stale'), ('gdd_sha256', 'stale')):
            with self.subTest(key=key):
                def callback(command, **kwargs):
                    qa_mock.emit(command, self.root)
                    data = self.payload(case)
                    data[key] = value
                    self.write_report(case, data)
                    return subprocess.CompletedProcess(command, 0, stdout=case.marker + ' completed\n', stderr='')
                result = self.run_case(callback, name=case.name)
                self.assertFalse(result['passed'])

    def run_main(self, arguments, callback=None):
        with patch.object(run_checks.subprocess, "run", side_effect=callback or self.success), redirect_stdout(io.StringIO()):
            code = run_checks.main(["--godot", "mock-godot.exe", *arguments])
        return code, json.loads((self.root / "reports" / "checks.json").read_text(encoding="utf-8"))

    def test_valid_fresh_report_records_context_and_timestamps(self):
        result = self.run_case()
        self.assertTrue(result["passed"])
        self.assertEqual(result["program_version"], "0.1.3.0")
        self.assertEqual(result["project_sha256"], run_checks.project_context()["project_sha256"])
        self.assertGreaterEqual(result["report_mtime_ns"] + run_checks.TIMESTAMP_TOLERANCE_NS, result["started_ns"])
        self.assertLessEqual(result["report_mtime_ns"], result["finished_ns"])
        self.assertEqual(len(result["report_sha256"]), 64)

    def test_old_pass_cannot_replace_missing_fresh_report(self):
        case = run_checks.CASES["ProfileSmoke"]
        self.write_report(case, self.payload(case))
        def no_report(command, **kwargs):
            self.assertFalse((self.root / "reports" / case.report_file).exists())
            return subprocess.CompletedProcess(command, 0, stdout=case.marker, stderr="")
        result = self.run_case(no_report)
        self.assertFalse(result["passed"])
        self.assertIn("fresh_report_missing", result["errors"])

    def test_failed_or_truthy_report_is_rejected(self):
        for value in [False, 1, "true", None]:
            with self.subTest(passed=value):
                def failed(command, **kwargs):
                    response = self.success(command, **kwargs)
                    case = self.case_for(command)
                    data = self.payload(case)
                    data["passed"] = value
                    self.write_report(case, data)
                    return response
                result = self.run_case(failed)
                self.assertFalse(result["passed"])
                self.assertIn("report_passed_is_not_true", result["errors"])

    def test_non_object_or_malformed_json_is_rejected(self):
        for raw in ["not-json", "[true]", "null", '{"passed":true,"checks":1,"ratio":NaN}']:
            with self.subTest(raw=raw):
                def malformed(command, **kwargs):
                    response = self.success(command, **kwargs)
                    (self.root / "reports" / self.case_for(command).report_file).write_text(raw)
                    return response
                self.assertFalse(self.run_case(malformed)["passed"])

    def test_nonempty_failures_cannot_claim_pass(self):
        def inconsistent(command, **kwargs):
            response = self.success(command, **kwargs)
            case = self.case_for(command)
            data = self.payload(case)
            data["failures"] = ["broken assertion"]
            self.write_report(case, data)
            return response
        self.assertIn("report_contains_failures", self.run_case(inconsistent)["errors"])

    def test_no_checks_or_boolean_count_is_rejected(self):
        for count in [0, True, None]:
            with self.subTest(checks=count):
                def empty(command, **kwargs):
                    response = self.success(command, **kwargs)
                    case = self.case_for(command)
                    data = self.payload(case)
                    data["checks"] = count
                    self.write_report(case, data)
                    return response
                self.assertFalse(self.run_case(empty)["passed"])

    def test_error_and_leak_logs_fail_even_with_zero_exit(self):
        lines = ["SCRIPT ERROR: parse", "ERROR: load", "ERROR missing colon",
                 "Leaked instance: AudioStreamWAV", "WARNING: 2 ObjectDB instances were leaked at exit",
                 "\x1b[31merror\x1b[0m: colored failure"]
        for line in lines:
            with self.subTest(line=line):
                def noisy(command, **kwargs):
                    response = self.success(command, **kwargs)
                    response.stderr = line
                    return response
                result = self.run_case(noisy)
                self.assertFalse(result["passed"])
                self.assertIn("fatal_error_or_leak_log", result["errors"])
                self.assertTrue(result["fatal_log_lines"])

    def test_separate_stdout_stderr_boundaries_keep_error_token(self):
        output = run_checks.joined_output("lastword", "ERROR: failed")
        self.assertTrue(run_checks.fatal_lines(output))

    def test_benign_words_do_not_match_error_severity(self):
        self.assertFalse(run_checks.fatal_lines("SpriteErrorName and errors_count=0"))

    def test_completion_must_be_a_full_line_marker(self):
        for marker in ['debug: "PROFILE_SMOKE"', "PROFILE_SMOKE_FAILED"]:
            with self.subTest(marker=marker):
                def wrong_marker(command, **kwargs):
                    response = self.success(command, **kwargs)
                    response.stdout = marker
                    return response
                self.assertIn("completion_marker_missing", self.run_case(wrong_marker)["errors"])

    def test_colored_completion_marker_is_supported(self):
        def colored(command, **kwargs):
            response = self.success(command, **kwargs)
            response.stdout = "\x1b[32m" + self.case_for(command).marker + "\x1b[0m completed\n"
            return response
        self.assertTrue(self.run_case(colored)["passed"])

    def test_nonzero_exit_cannot_pass_with_valid_report(self):
        def nonzero(command, **kwargs):
            response = self.success(command, **kwargs)
            response.returncode = 7
            return response
        self.assertIn("nonzero_exit", self.run_case(nonzero)["errors"])

    def test_old_report_version_is_rejected(self):
        def old_version(command, **kwargs):
            response = self.success(command, **kwargs)
            case = self.case_for(command)
            data = self.payload(case)
            data["version"] = "0.1.2.0"
            self.write_report(case, data)
            return response
        result = self.run_case(old_version)
        self.assertIn("report_program_version_mismatch: version", result["errors"])

    def test_project_change_during_case_is_rejected(self):
        def changed(command, **kwargs):
            response = self.success(command, **kwargs)
            with (self.root / "project.godot").open("a", encoding="utf-8") as file:
                file.write("# concurrent project change\n")
            return response
        self.assertIn("project_changed_during_case", self.run_case(changed)["errors"])

    def test_project_change_before_case_skips_engine(self):
        expected = run_checks.project_context()
        (self.root / "project.godot").write_text('config/version="0.1.4.0"\n')
        with patch.object(run_checks.subprocess, "run") as engine:
            result = run_checks.run_case(run_checks.CASES["ProfileSmoke"], Path("mock-godot.exe"), expected)
        engine.assert_not_called()
        self.assertFalse(result["passed"])

    def test_increment_report_requires_each_current_input_hash(self):
        for name in ("StudyProfileSmoke", "StudyCombatSmoke", "StudyUISmoke", "BriefingSmoke", "BriefingUISmoke"):
            case = run_checks.CASES[name]
            for key in run_checks.case_artifact_context(case):
                for missing in (True, False):
                    with self.subTest(case=name, field=key, missing=missing):
                        def wrong_hash(command, **kwargs):
                            response = self.success(command, **kwargs)
                            data = self.payload(case)
                            if missing:
                                data.pop(key)
                            else:
                                data[key] = "forged sha"
                            self.write_report(case, data)
                            return response
                        result = self.run_case(wrong_hash, name)
                        self.assertFalse(result["passed"])
                        self.assertIn("report_artifact_hash_mismatch: " + key, result["errors"])

    def test_briefing_reports_require_eight_stages_current_design_and_complete_matrix(self):
        for name in ("BriefingSmoke", "BriefingUISmoke"):
            case = run_checks.CASES[name]
            self.assertTrue(case.headless)
            for key, expected in case.required_report_values:
                values = (None, True, str(expected), expected + 1, float(expected)) if type(expected) is int else (None, True, "0.5.4", "0.5.5")
                for value in values:
                    with self.subTest(case=name, field=key, value=value):
                        def wrong_scope(command, **kwargs):
                            response = self.success(command, **kwargs)
                            data = self.payload(case)
                            data[key] = value
                            self.write_report(case, data)
                            return response
                        result = self.run_case(wrong_scope, name)
                        self.assertIn("report_required_value_mismatch: " + key, result["errors"])

    def test_design_version_is_read_from_the_same_project_instead_of_a_fixed_release(self):
        path = self.root / "docs/GAME_DESIGN.md"
        path.write_text("> 文档 v0.9.3 · later design fixture\n", encoding="utf-8")
        for name in ("BriefingSmoke", "BriefingUISmoke", "BattleReportSmoke", "ResultUISmoke"):
            with self.subTest(case=name):
                result = self.run_case(self.success, name)
                self.assertTrue(result["passed"], result)
                self.assertEqual(result["artifact_sha256"]["gdd_version"], "0.9.3")

    def test_new_result_reports_require_current_design_and_exact_core_input(self):
        for name in ("BattleReportSmoke", "ResultUISmoke"):
            for key in ("gdd_version", "gdd_sha256", "scripts_sha256"):
                with self.subTest(case=name, field=key):
                    def stale(command, **kwargs):
                        response = self.success(command, **kwargs)
                        case = run_checks.CASES[name]
                        data = self.payload(case)
                        data[key] = "old" if key != "scripts_sha256" else {}
                        self.write_report(case, data)
                        return response
                    result = self.run_case(stale, name)
                    self.assertFalse(result["passed"])
                    self.assertIn("report_artifact_hash_mismatch: " + key, result["errors"])

    def test_briefing_rejects_each_changed_design_configuration_and_script(self):
        for name in ("BriefingSmoke", "BriefingUISmoke"):
            case = run_checks.CASES[name]
            for relative in [path for _, path in case.report_hashes] + list(case.script_hashes):
                with self.subTest(case=name, input=relative):
                    def changed(command, **kwargs):
                        response = self.success(command, **kwargs)
                        with (self.root / relative).open("a", encoding="utf-8") as file:
                            file.write("concurrent briefing input change\n")
                        return response
                    result = self.run_case(changed, name)
                    self.assertFalse(result["passed"])
                    expected_error = "project_changed_during_case" if relative == "project.godot" else "artifact_changed_during_case"
                    self.assertIn(expected_error, result["errors"])

    def test_briefing_nested_script_hashes_require_all_exact_paths_and_values(self):
        for name in ("BriefingSmoke", "BriefingUISmoke"):
            case = run_checks.CASES[name]
            expected = run_checks.case_artifact_context(case)["scripts_sha256"]
            variants = [{}, {**expected, "unrelated.gd": "extra"}]
            for path in expected:
                variants.extend(({key: value for key, value in expected.items() if key != path}, {**expected, path: "forged"}))
            for scripts in variants:
                with self.subTest(case=name, scripts=scripts):
                    def forged(command, **kwargs):
                        response = self.success(command, **kwargs)
                        data = self.payload(case)
                        data["scripts_sha256"] = scripts
                        self.write_report(case, data)
                        return response
                    self.assertIn("report_artifact_hash_mismatch: scripts_sha256", self.run_case(forged, name)["errors"])

    def test_study_combat_requires_all_108_actual_spawn_combinations(self):
        for matrix in (None, 0, 107, 109, "108", True):
            with self.subTest(matrix_cases=matrix):
                def incomplete_matrix(command, **kwargs):
                    response = self.success(command, **kwargs)
                    case = self.case_for(command)
                    data = self.payload(case)
                    if matrix is None:
                        data.pop("matrix_cases")
                    else:
                        data["matrix_cases"] = matrix
                    self.write_report(case, data)
                    return response
                result = self.run_case(incomplete_matrix, "StudyCombatSmoke")
                self.assertFalse(result["passed"])
                self.assertIn("report_required_value_mismatch: matrix_cases", result["errors"])

    def test_study_input_change_during_case_is_rejected(self):
        for name, relative in (("StudyProfileSmoke", "resources/studies.json"),
                               ("StudyCombatSmoke", "scripts/core/UnitStats.gd"),
                               ("StudyCombatSmoke", "scripts/combat/SiegeBattle.gd"),
                               ("StudyUISmoke", "scripts/ui/Main.gd")):
            with self.subTest(case=name, input=relative):
                def changed(command, **kwargs):
                    response = self.success(command, **kwargs)
                    with (self.root / relative).open("a", encoding="utf-8") as file:
                        file.write("concurrent change\n")
                    return response
                result = self.run_case(changed, name)
                self.assertFalse(result["passed"])
                self.assertIn("artifact_changed_during_case", result["errors"])

    def test_study_ui_nested_script_hash_requires_exact_path_and_digest(self):
        for scripts in ({}, {"Main.gd": "forged"},
                        {"scripts/ui/Main.gd": "forged"},
                        {"scripts/ui/Main.gd": run_checks.case_artifact_context(run_checks.CASES["StudyUISmoke"])["scripts_sha256"]["scripts/ui/Main.gd"], "unrelated.gd": "extra"}):
            with self.subTest(scripts=scripts):
                def wrong_scripts(command, **kwargs):
                    response = self.success(command, **kwargs)
                    case = self.case_for(command)
                    data = self.payload(case)
                    data["scripts_sha256"] = scripts
                    self.write_report(case, data)
                    return response
                result = self.run_case(wrong_scripts, "StudyUISmoke")
                self.assertIn("report_artifact_hash_mismatch: scripts_sha256", result["errors"])

    def test_actual_ui_reports_cannot_omit_or_forge_shared_stat_widget(self):
        for name in ("StudyUISmoke", "BriefingUISmoke"):
            case = run_checks.CASES[name]
            self.assertIn("scripts/ui/StatBadge.gd", case.script_hashes)
            expected = run_checks.case_artifact_context(case)["scripts_sha256"]
            for missing in (False, True):
                with self.subTest(case=name, missing=missing):
                    def old_widget(command, **kwargs):
                        response = self.success(command, **kwargs)
                        data = self.payload(case)
                        scripts = expected.copy()
                        if missing:
                            scripts.pop("scripts/ui/StatBadge.gd")
                        else:
                            scripts["scripts/ui/StatBadge.gd"] = "old widget"
                        data["scripts_sha256"] = scripts
                        self.write_report(case, data)
                        return response
                    self.assertIn("report_artifact_hash_mismatch: scripts_sha256", self.run_case(old_widget, name)["errors"])

    def test_missing_study_input_skips_engine(self):
        (self.root / "resources/studies.json").unlink()
        with patch.object(run_checks.subprocess, "run") as engine:
            result = run_checks.run_case(run_checks.CASES["StudyProfileSmoke"], Path("mock-godot.exe"), run_checks.project_context())
        engine.assert_not_called()
        self.assertFalse(result["passed"])

    def test_report_cleanup_failure_skips_engine(self):
        case = run_checks.CASES["ProfileSmoke"]
        (self.root / "reports" / case.report_file).mkdir()
        with patch.object(run_checks.subprocess, "run") as engine:
            result = run_checks.run_case(case, Path("mock-godot.exe"), run_checks.project_context())
        engine.assert_not_called()
        self.assertFalse(result["passed"])

    def test_old_or_future_report_timestamp_is_rejected(self):
        for shift, expected in [(-60, "report_timestamp_before_run"), (60, "report_timestamp_after_run")]:
            with self.subTest(shift=shift):
                def timestamp(command, **kwargs):
                    response = self.success(command, **kwargs)
                    path = self.root / "reports" / self.case_for(command).report_file
                    stamp = time.time_ns() + shift * 1_000_000_000
                    os.utime(path, ns=(stamp, stamp))
                    return response
                self.assertIn(expected, self.run_case(timestamp)["errors"])

    def test_timeout_preserves_mixed_partial_output_and_fails(self):
        def timed_out(command, **kwargs):
            self.success(command, **kwargs)
            raise subprocess.TimeoutExpired(command, 30, output=b"partial output", stderr="ERROR: stalled")
        result = self.run_case(timed_out)
        self.assertFalse(result["passed"])
        self.assertIn("timeout", result["errors"])
        log = (self.root / "reports" / "ProfileSmoke.log").read_text()
        self.assertIn("partial output", log)
        self.assertIn("ERROR: stalled", log)

    def test_start_failure_replaces_stale_green_summary(self):
        (self.root / "reports" / "checks.json").write_text('{"passed":true,"suite":"full"}')
        code, summary = self.run_main(["--only", "AudioShutdownSmoke"], callback=FileNotFoundError("missing engine"))
        self.assertEqual(code, 1)
        self.assertFalse(summary["passed"])
        self.assertEqual(summary["suite"], "single")
        self.assertEqual(summary["state"], "complete")
        self.assertTrue(summary["cases"][0]["errors"])

    def test_missing_project_cannot_leave_stale_summary(self):
        (self.root / "reports" / "checks.json").write_text('{"passed":true}')
        (self.root / "project.godot").unlink()
        code, summary = self.run_main(["--only", "ProfileSmoke"])
        self.assertEqual(code, 1)
        self.assertFalse(summary["passed"])
        self.assertTrue(summary["errors"])

    def test_default_suite_is_all_thirteen_cpu_cases_and_running_summary_is_not_passed(self):
        names = []
        def inspect(command, **kwargs):
            case = self.case_for(command)
            names.append(case.name)
            self.assertIn("--headless", command)
            self.assertIn("--verbose", command)
            checkpoint = json.loads((self.root / "reports" / "checks.json").read_text())
            self.assertEqual(checkpoint["state"], "running")
            self.assertFalse(checkpoint["passed"])
            return self.success(command, **kwargs)
        code, summary = self.run_main([], inspect)
        self.assertEqual(code, 0, summary)
        self.assertEqual(tuple(names), run_checks.CPU_CASES)
        self.assertEqual(len(names), 13)
        self.assertEqual(summary["suite"], "logic")

    def test_visual_suite_adds_mainflow_and_headless_campaign(self):
        modes = {}
        def inspect(command, **kwargs):
            modes[self.case_for(command).name] = "--headless" in command
            return self.success(command, **kwargs)
        code, summary = self.run_main(["--visual"], inspect)
        self.assertEqual(code, 0, summary)
        self.assertEqual(len(summary["cases"]), len(run_checks.CASES))
        self.assertEqual(summary["suite"], "full")
        self.assertFalse(modes["MainFlow"])
        self.assertTrue(modes["CampaignJourney"])

    def test_rendered_default_uses_production_logging_and_records_exact_command(self):
        observed = []
        def inspect(command, **kwargs):
            observed.append(command.copy())
            self.assertNotIn("--verbose", command)
            self.assertNotIn("--headless", command)
            return self.success(command, **kwargs)
        result = self.run_case(inspect, "MainFlow")
        self.assertTrue(result["passed"])
        self.assertEqual(result["launch_mode"], "rendered_production")
        self.assertEqual(result["command_line"], observed[0])

    def test_mainflow_single_and_visual_suites_require_host_observation(self):
        for arguments in (['--only', 'MainFlow'], ['--visual']):
            with self.subTest(arguments=arguments):
                def missing_host(command, **kwargs):
                    response = self.success(command, **kwargs)
                    case = self.case_for(command)
                    if case.name == 'MainFlow':
                        data = self.payload(case)
                        data.pop('host_observed_frames')
                        self.write_report(case, data)
                    return response
                code, summary = self.run_main(arguments, missing_host)
                self.assertEqual(code, 1)
                self.assertFalse(summary['passed'])

    def test_mainflow_rejects_partial_focus_float_counts_and_manual_claim(self):
        for key, value in (('host_observed_frames', 0), ('host_observed_frames', True), ('host_normal_window_frames', 19), ('host_normal_window_frames', 20.0), ('host_focused_frames', 19), ('engine_input_dispatch_verified', False), ('os_input_verified', True)):
            with self.subTest(field=key, value=value):
                def invalid_host(command, **kwargs):
                    response = self.success(command, **kwargs)
                    case = self.case_for(command)
                    data = self.payload(case)
                    data[key] = value
                    self.write_report(case, data)
                    return response
                self.assertFalse(self.run_case(invalid_host, 'MainFlow')['passed'])

    def test_mainflow_rejects_minimized_unfocused_or_false_capture_metadata(self):
        for key, value in (('window_mode', 1), ('display_window_mode', 1), ('window_mode', False), ('window_visible', False), ('focused', False), ('actual_rendering_driver', 'opengl3'), ('path', 'res://reports/runtime/unrelated.png'), ('size', [640, 360]), ('sha256', 'forged'), ('name', [])):
            with self.subTest(field=key, value=value):
                def invalid_capture(command, **kwargs):
                    response = self.success(command, **kwargs)
                    case = self.case_for(command)
                    data = self.payload(case)
                    data['capture_states'][0][key] = value
                    self.write_report(case, data)
                    return response
                self.assertFalse(self.run_case(invalid_capture, 'MainFlow')['passed'])

    def test_mainflow_rejects_missing_truncated_and_wrong_actual_png(self):
        for value in (None, b'\x89PNG\r\n\x1a\n', fixture_png()[:-1], fixture_png(640, 360)):
            with self.subTest(png=None if value is None else len(value)):
                def broken_png(command, **kwargs):
                    response = self.success(command, **kwargs)
                    path = self.root / 'reports/runtime/01_campaign.png'
                    if value is None:
                        path.unlink()
                    else:
                        path.write_bytes(value)
                    return response
                self.assertFalse(self.run_case(broken_png, 'MainFlow')['passed'])

    def test_png_reader_accepts_real_rgb_and_rgba_headers(self):
        for color in (2, 6):
            with self.subTest(color=color):
                path = self.root / 'fixture.png'
                path.write_bytes(fixture_png(color=color))
                self.assertEqual(run_checks.png_dimensions(path), (1280, 720))

    def test_verbose_render_diagnostics_is_explicit_and_keeps_headless_scope(self):
        observed = {}
        def inspect(command, **kwargs):
            observed[self.case_for(command).name] = command.copy()
            self.assertIn("--verbose", command)
            return self.success(command, **kwargs)
        code, summary = self.run_main(["--visual", "--verbose-render-diagnostics"], inspect)
        self.assertEqual(code, 0, summary)
        self.assertTrue(summary["verbose_render_diagnostics"])
        self.assertEqual(summary["rendered_launch_scope"], "verbose driver/resource diagnostics")
        for case in summary["cases"]:
            self.assertEqual(case["command_line"], observed[case["case"]])
            self.assertEqual(case["launch_mode"], "rendered_verbose_diagnostics" if case["case"] == "MainFlow" else "headless_verbose")

    def test_production_render_logs_still_reject_errors_and_leak_summaries(self):
        for line in ("SCRIPT ERROR: failed", "ERROR: GENERAL - Loader Message", "Leaked instance: AudioStreamPlayer", "ObjectDB instances leaked at exit (run with --verbose for details)"):
            with self.subTest(line=line):
                def noisy(command, **kwargs):
                    self.assertNotIn("--verbose", command)
                    response = self.success(command, **kwargs)
                    response.stderr = line
                    return response
                result = self.run_case(noisy, "MainFlow")
                self.assertFalse(result["passed"])
                self.assertIn("fatal_error_or_leak_log", result["errors"])
                self.assertTrue(result["fatal_log_lines"])

    def test_full_suite_cannot_reuse_one_old_case_report(self):
        for case in run_checks.CASES.values():
            self.write_report(case, self.payload(case))
        def omit_one(command, **kwargs):
            case = self.case_for(command)
            if case.name == "PreferencesSmoke":
                self.assertFalse((self.root / "reports" / case.report_file).exists())
                qa_mock.emit(command, self.root)
                return subprocess.CompletedProcess(command, 0, stdout=case.marker, stderr="")
            return self.success(command, **kwargs)
        code, summary = self.run_main(["--visual"], omit_one)
        self.assertEqual(code, 1)
        self.assertFalse(summary["passed"])
        self.assertEqual(len(summary["cases"]), len(run_checks.CASES))
        failed = [case for case in summary["cases"] if not case["passed"]]
        self.assertEqual(failed[0]["case"], "PreferencesSmoke")

    def test_full_suite_cannot_reuse_a_missing_study_report(self):
        case = run_checks.CASES["StudyUISmoke"]
        self.write_report(case, self.payload(case))
        def omit_study(command, **kwargs):
            current = self.case_for(command)
            if current.name == case.name:
                self.assertFalse((self.root / "reports" / case.report_file).exists())
                qa_mock.emit(command, self.root)
                return subprocess.CompletedProcess(command, 0, stdout=case.marker, stderr="")
            return self.success(command, **kwargs)
        code, summary = self.run_main(["--visual"], omit_study)
        self.assertEqual(code, 1)
        failed = [item for item in summary["cases"] if not item["passed"]]
        self.assertEqual([item["case"] for item in failed], [case.name])
        self.assertIn("fresh_report_missing", failed[0]["errors"])

    def test_every_single_case_is_selectable(self):
        for name in run_checks.CASES:
            with self.subTest(case=name):
                code, summary = self.run_main(["--only", name])
                self.assertEqual(code, 0)
                self.assertEqual(summary["selected_cases"], [name])
                self.assertEqual(summary["suite"], "single")

    def test_campaign_requires_parent_completion_marker(self):
        def child_only(command, **kwargs):
            response = self.success(command, **kwargs)
            response.stdout = "CAMPAIGN_JOURNEY checks=977 failures=0 process_restart=true\n"
            return response
        result = self.run_case(child_only, "CampaignJourney")
        self.assertIn("completion_marker_missing", result["errors"])

    def test_campaign_checkpoint_cannot_be_final_pass(self):
        def checkpoint(command, **kwargs):
            response = self.success(command, **kwargs)
            case = self.case_for(command)
            data = self.payload(case)
            data["phase"] = "fresh_complete"
            self.write_report(case, data)
            return response
        result = self.run_case(checkpoint, "CampaignJourney")
        self.assertIn("report_final_phase_missing", result["errors"])


if __name__ == "__main__":
    started = time.perf_counter()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(StrictRunnerBoundaries)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = {
        "passed": result.wasSuccessful(), "tests_run": result.testsRun,
        "failures": [str(test) for test, _ in result.failures + result.errors],
        "scope": "mocked subprocess boundaries; no Godot, rendering, or campaign execution",
        "duration_seconds": time.perf_counter() - started, **run_checks.project_context(),
    }
    (ROOT / "reports" / "runner_unit_tests.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if result.wasSuccessful() else 1)
