"""Exercise startup evidence and filesystem boundaries without launching Godot."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import qa_launch
import qa_mock
import run_checks
import bootstrap_local
import generate_portraits
import verify_package
import verify_spine


class QALaunchBoundaries(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="fantasysiege_qa_")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        qa_mock.scripts(self.root)

    def prepare(self, gameplay=True, background=False):
        return qa_launch.prepare_launch(["unused-engine", "--path", str(self.root), "--script", "res://tests/Probe.gd",
                                        "--", "d69_097", "absolute-probe-report.json"],
                                       self.root, "native probe", gameplay=gameplay, background=background)

    def success(self):
        evidence = self.prepare()
        qa_mock.emit(evidence.command, self.root)
        return evidence

    def mutate(self, evidence, change):
        data = qa_launch.read_json(evidence.startup_report)
        change(data)
        evidence.startup_report.write_text(json.dumps(data), encoding="utf-8")
        return qa_launch.validate_evidence(evidence, run_checks.fatal_lines)

    def test_engine_and_user_argument_sections_preserve_positional_probe(self):
        evidence = self.prepare(background=True)
        split = evidence.command.index("--")
        self.assertLess(evidence.command.index("--log-file"), split)
        self.assertEqual(evidence.command[split + 1:split + 3], ["d69_097", "absolute-probe-report.json"])
        self.assertGreater(evidence.command.index("--qa-save-root"), split)
        self.assertIn("--qa-background", evidence.command)

    def test_each_launch_has_unique_save_report_and_log_paths(self):
        first, second = self.prepare(), self.prepare()
        for attr in ("save_root", "startup_report", "engine_log"):
            self.assertNotEqual(getattr(first, attr), getattr(second, attr))
        self.assertTrue(first.save_root.is_dir())
        self.assertTrue((self.root / "tests/.user/.gdignore").is_file())

    def test_gameplay_without_user_separator_gets_one(self):
        command = ["unused", "--path", str(self.root), "--script", "res://tests/Probe.gd"]
        result = qa_launch.prepare_launch(command, self.root, "simple")
        self.assertEqual(result.command.count("--"), 1)

    def test_editor_launch_only_redirects_engine_log(self):
        evidence = qa_launch.prepare_launch(["unused", "--path", str(self.root), "--editor", "--quit"], self.root, "import", gameplay=False)
        qa_mock.emit(evidence.command, self.root)
        self.assertIsNone(evidence.save_root)
        self.assertIsNone(evidence.startup_report)
        self.assertNotIn("--qa-save-root", evidence.command)
        self.assertTrue(qa_launch.validate_evidence(evidence, run_checks.fatal_lines)["passed"])

    def test_normal_record_reaudits_actual_files(self):
        evidence = self.success()
        record = qa_launch.validate_evidence(evidence, run_checks.fatal_lines)
        self.assertTrue(record["passed"], record["errors"])
        self.assertEqual(qa_launch.audit_record(record, self.root, run_checks.fatal_lines), [])
        evidence.engine_log.write_text("changed after verification", encoding="utf-8")
        self.assertIn("QA engine log SHA differs", qa_launch.audit_record(record, self.root, run_checks.fatal_lines))

    def test_missing_startup_or_engine_logs_cannot_pass(self):
        for missing in ("startup_report", "engine_log"):
            with self.subTest(missing=missing):
                evidence = self.success()
                getattr(evidence, missing).unlink()
                self.assertFalse(qa_launch.validate_evidence(evidence, run_checks.fatal_lines)["passed"])

    def test_engine_log_leak_fails_even_if_startup_is_valid(self):
        evidence = self.success()
        evidence.engine_log.write_text("Leaked instance: AudioStreamWAV", encoding="utf-8")
        record = qa_launch.validate_evidence(evidence, run_checks.fatal_lines)
        self.assertFalse(record["passed"])
        self.assertTrue(record["engine_fatal_log_lines"])

    def test_missing_load_owner_and_wrong_first_path_fail(self):
        for change in (lambda data: data["first_loads"].pop("profile"),
                       lambda data: data["first_loads"]["preferences"].update(path=str(self.root / "real_preferences.json")),
                       lambda data: data.update(refused_operations=[{"reason": "forbidden"}])):
            self.assertFalse(self.mutate(self.success(), change)["passed"])

    def test_read_trace_must_precede_initial_load_and_use_primary_path(self):
        for change in (lambda data: data.update(operations=[]),
                       lambda data: data["operations"][0].update(path=str(self.root / "tests/.user/backup.json")),
                       lambda data: data["operations"][0].update(ticks_usec=9),
                       lambda data: data["operations"][0].update(allowed=False)):
            self.assertFalse(self.mutate(self.success(), change)["passed"])

    def test_changed_runtime_script_invalidates_completed_startup(self):
        evidence = self.success()
        (self.root / qa_launch.SCRIPT_PATHS[0]).write_text("changed", encoding="utf-8")
        self.assertFalse(qa_launch.validate_evidence(evidence)["passed"])

    def test_operation_path_leaving_test_root_fails(self):
        result = self.mutate(self.success(), lambda data: data["operations"][0].update(path=str(self.root / "real_preferences.json")))
        self.assertFalse(result["passed"])
        self.assertTrue(any("outside isolation" in error for error in result["errors"]))

    def test_expected_rejection_requires_no_save_io_and_refusal(self):
        evidence = self.success()
        data = qa_launch.read_json(evidence.startup_report)
        data.update(valid=False, operations=[], first_loads={}, refused_operations=[{"reason": "malformed argument"}])
        evidence.startup_report.write_text(json.dumps(data), encoding="utf-8")
        self.assertTrue(qa_launch.validate_evidence(evidence, expect_valid=False)["passed"])
        data["operations"] = [{"path": str(evidence.save_root / "profile.json"), "owner": "profile", "action": "read", "allowed": True, "ticks_usec": 1}]
        evidence.startup_report.write_text(json.dumps(data), encoding="utf-8")
        self.assertFalse(qa_launch.validate_evidence(evidence, expect_valid=False)["passed"])

    def test_nonfinite_or_nonobject_json_fails(self):
        for raw in ("[]", '{"value":NaN}'):
            evidence = self.success()
            evidence.startup_report.write_text(raw, encoding="utf-8")
            self.assertFalse(qa_launch.validate_evidence(evidence)["passed"])

    def test_reserved_or_duplicate_engine_arguments_rejected_before_write(self):
        commands = [[], ["unused"], ["unused", "--", "--path", str(self.root)],
                    ["unused", "--path", str(self.root), "--path", str(self.root)],
                    ["unused", "--path", str(self.root), "--log-file", "outside.log"],
                    ["unused", "--path", str(self.root), "--", "--qa-save-root", "outside"],
                    ["unused", "--path", str(self.root), "--", "--qa-startup-report=x"]]
        for command in commands:
            with self.subTest(command=command), self.assertRaises(ValueError):
                qa_launch.prepare_launch(command, self.root, "invalid")
        self.assertFalse((self.root / "reports").exists())

    def test_outside_relative_and_parent_traversal_paths_rejected(self):
        for path in (Path("tests/.user/a"), self.root / "outside", self.root / "tests/.user/a/../b"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                qa_launch.assert_safe_path(path, self.root, "tests/.user")

    def test_hardlinked_fixture_elsewhere_in_save_tree_rejected_before_write(self):
        outside = self.root / "outside.json"
        outside.write_text("original outside bytes", encoding="utf-8")
        folder = self.root / "tests/.user/later_fixture"
        folder.mkdir(parents=True)
        os.link(outside, folder / "profile.json")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual(outside.read_text(encoding="utf-8"), "original outside bytes")
        self.assertFalse((self.root / "reports").exists())

    def test_windows_junction_fixture_rejected_before_write(self):
        if os.name != "nt":
            self.skipTest("Windows junction case")
        outside = self.root / "outside"
        outside.mkdir()
        folder = self.root / "tests/.user"
        folder.mkdir(parents=True)
        junction = folder / "later_fixture"
        result = subprocess.run(["cmd", "/c", "mklink", "/J", str(junction), str(outside)], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            with self.assertRaises(ValueError):
                self.prepare()
            self.assertEqual(list(outside.iterdir()), [])
            self.assertFalse((self.root / "reports").exists())
        finally:
            # Remove only the junction itself, never its target.
            os.rmdir(junction)


class BackgroundHostBoundaries(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='fantasysiege_background_setup_')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_single_ready_request_accepts_asynchronous_confirmation(self):
        setup = qa_mock.background_setup(self.root)
        self.assertEqual(qa_launch.background_host_check(setup, self.root), [])
        self.assertEqual(setup['trace'][4]['window_mode'], 0, 'request_after may precede OS confirmation')

    def test_missing_duplicate_or_forged_setup_is_rejected(self):
        self.assertTrue(qa_launch.background_host_check(None, self.root))
        for key, value in [('initialized', False), ('initialize_calls', 2), ('request_count', 2),
                           ('request_count', True), ('helper_sha256', 'forged'), ('errors', ['failed'])]:
            with self.subTest(key=key):
                setup = qa_mock.background_setup(self.root)
                setup[key] = value
                self.assertTrue(qa_launch.background_host_check(setup, self.root))

    def test_readiness_stage_order_and_monitor_start_must_precede_samples(self):
        for change in (lambda data: data['trace'][3].update(root_ready=False),
                       lambda data: data['trace'][2].update(stage='request_before'),
                       lambda data: data.update(monitor_start_ticks_usec=4),
                       lambda data: data.update(confirmed_frame=2),
                       lambda data: data['trace'][4].update(ticks_usec=2)):
            setup = qa_mock.background_setup(self.root)
            change(setup)
            self.assertTrue(qa_launch.background_host_check(setup, self.root))

    def test_confirmed_and_sampling_modes_cannot_be_relaxed(self):
        for index in (-2, -1):
            for key in ('window_mode', 'display_window_mode'):
                for value in (0, 3, True):
                    with self.subTest(index=index, key=key, value=value):
                        setup = qa_mock.background_setup(self.root)
                        setup['trace'][index][key] = value
                        self.assertTrue(qa_launch.background_host_check(setup, self.root))


class LauncherFirstWriteBoundaries(unittest.TestCase):
    """Real filesystem links must be rejected before a launcher touches output."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="fantasysiege_entry_guard_")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.root = self.base / "project"
        self.root.mkdir()
        (self.root / 'project.godot').write_text('[application]\nconfig/version="0.1.3.0"\n', encoding='utf-8')
        resources = self.root / 'resources'
        resources.mkdir()
        (resources / 'visuals.json').write_text('{"d69_097": {"status": "converted"}}', encoding='utf-8')
        qa_mock.scripts(self.root)
        self.outside = self.base / "outside"
        self.outside.mkdir()

    def invoke(self, name):
        module, arguments = {
            'runner': (run_checks, ['--only', 'ProfileSmoke', '--godot', 'unused-engine']),
            'package': (verify_package, ['--package', str(self.root), '--phase', 'background']),
            'native': (verify_spine, ['--ids', '097', '--godot', 'unused-engine']),
            'bootstrap': (bootstrap_local, ['--import-only', '--godot', 'unused-engine']),
            'portraits': (generate_portraits, ['--check']),
        }[name]
        with patch.object(module, 'ROOT', self.root), patch.object(subprocess, 'run') as engine:
            with self.assertRaises(ValueError):
                module.main(arguments)
            engine.assert_not_called()

    def test_report_junction_rejected_by_every_launcher_before_first_write(self):
        if os.name != 'nt':
            self.skipTest('Windows junction case')
        marker = self.outside / 'checks.json'
        marker.write_bytes(b'outside marker must remain unchanged')
        before = {path.name: path.read_bytes() for path in self.outside.iterdir()}
        reports = self.root / 'reports'
        result = subprocess.run(['cmd', '/c', 'mklink', '/J', str(reports), str(self.outside)], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            for name in ('runner', 'package', 'native', 'bootstrap', 'portraits'):
                with self.subTest(launcher=name):
                    self.invoke(name)
                    self.assertEqual({path.name: path.read_bytes() for path in self.outside.iterdir()}, before)
                    self.assertFalse((self.root / 'tests/.user').exists())
        finally:
            os.rmdir(reports)  # The verified junction only; never recurse into the target.

    def test_report_hardlink_rejected_by_every_launcher_before_first_write(self):
        reports = self.root / 'reports'
        reports.mkdir()
        marker = self.outside / 'marker.json'
        marker.write_bytes(b'outside marker must remain unchanged')
        os.link(marker, reports / 'checks.json')
        for name in ('runner', 'package', 'native', 'bootstrap', 'portraits'):
            with self.subTest(launcher=name):
                self.invoke(name)
                self.assertEqual(marker.read_bytes(), b'outside marker must remain unchanged')
                self.assertEqual([path.name for path in reports.iterdir()], ['checks.json'])
                self.assertFalse((self.root / 'tests/.user').exists())

    def test_portrait_manifest_hardlink_rejected_before_report_or_asset_deletion(self):
        portraits = self.root / 'assets/portraits'
        portraits.mkdir(parents=True)
        marker = self.outside / 'manifest.json'
        marker.write_bytes(b'outside portrait manifest')
        os.link(marker, portraits / 'manifest.json')
        self.invoke('portraits')
        self.assertEqual(marker.read_bytes(), b'outside portrait manifest')
        self.assertTrue((portraits / 'manifest.json').exists())
        self.assertFalse((self.root / 'reports').exists())

    def test_native_runtime_hardlink_rejected_before_mkdir_or_copy(self):
        target = self.root / 'bin'
        target.mkdir()
        marker = self.outside / 'native_extension.gdextension'
        marker.write_bytes(b'outside native runtime marker')
        os.link(marker, target / 'spine_godot_extension.gdextension')
        with patch.object(bootstrap_local, 'ROOT', self.root), patch.object(bootstrap_local.shutil, 'copy2') as copy:
            with self.assertRaises(ValueError):
                bootstrap_local._copy_runtime(self.outside / 'unused_donor')
            copy.assert_not_called()
        self.assertEqual(marker.read_bytes(), b'outside native runtime marker')
        self.assertFalse((target / 'windows').exists())

    def test_native_runtime_junction_rejected_before_copy(self):
        if os.name != 'nt':
            self.skipTest('Windows junction case')
        target = self.root / 'bin'
        target.mkdir()
        windows = target / 'windows'
        marker = self.outside / 'native_marker.dll'
        marker.write_bytes(b'outside native runtime marker')
        result = subprocess.run(['cmd', '/c', 'mklink', '/J', str(windows), str(self.outside)], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        try:
            with patch.object(bootstrap_local, 'ROOT', self.root), patch.object(bootstrap_local.shutil, 'copy2') as copy:
                with self.assertRaises(ValueError):
                    bootstrap_local._copy_runtime(self.outside / 'unused_donor')
                copy.assert_not_called()
            self.assertEqual(marker.read_bytes(), b'outside native runtime marker')
            self.assertEqual([path.name for path in target.iterdir()], ['windows'])
        finally:
            os.rmdir(windows)

    def test_build_destination_junctions_rejected_before_payload_or_import(self):
        if os.name != 'nt':
            self.skipTest('Windows junction case')
        shell = shutil.which('pwsh') or shutil.which('powershell')
        if not shell:
            self.skipTest('PowerShell unavailable')
        tools = self.root / 'tools'
        tools.mkdir()
        script = tools / 'build_local.ps1'
        shutil.copy2(Path(__file__).resolve().parents[1] / 'tools/build_local.ps1', script)
        fake_engine = self.outside / 'unused.exe'
        fake_engine.write_bytes(b'not an engine; this must never run')
        external_target = self.outside / 'output'
        external_target.mkdir()
        exports = self.root / 'exports'
        exports.mkdir()
        for case in ('parent', 'leaf'):
            with self.subTest(case=case):
                windows = exports / 'windows'
                if case == 'leaf':
                    windows.mkdir()
                junction = windows if case == 'parent' else windows / 'candidate'
                destination = windows / 'candidate'
                link = subprocess.run(['cmd', '/c', 'mklink', '/J', str(junction), str(external_target)], capture_output=True, timeout=10)
                self.assertEqual(link.returncode, 0, link.stderr)
                try:
                    run = subprocess.run([shell, '-NoProfile', '-File', str(script), '-GodotPath', str(fake_engine),
                                          '-Destination', str(destination)], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=15)
                    self.assertNotEqual(run.returncode, 0)
                    self.assertIn('Refusing reparse point in package destination', run.stdout + run.stderr)
                    self.assertEqual(list(external_target.iterdir()), [])
                    self.assertEqual(fake_engine.read_bytes(), b'not an engine; this must never run')
                finally:
                    os.rmdir(junction)
                    if case == 'leaf':
                        os.rmdir(windows)


if __name__ == "__main__":
    unittest.main()
