"""Keep local authoring dependencies executable and reject missing tools before writes."""
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
import bootstrap_local
import tune_visuals
import verify_package


class BootstrapDependencies(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for filename in bootstrap_local.AUTHORING_TOOLS:
            path = self.root/'tools'/filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('mock executable dependency: '+filename, encoding='utf-8')

    def test_authoring_closure_includes_tune_and_all_hashes(self):
        hashes = bootstrap_local.tool_dependency_context(self.root)
        self.assertEqual(set(hashes), {'tools/'+name for name in bootstrap_local.AUTHORING_TOOLS})
        self.assertIn('tools/tune_visuals.py', hashes)
        self.assertTrue(all(len(value) == 64 for value in hashes.values()))

    def test_missing_each_dependency_rejects_before_report_or_runtime_write(self):
        source = self.root/'source'
        source.mkdir()
        for filename in bootstrap_local.AUTHORING_TOOLS:
            with self.subTest(filename=filename):
                path = self.root/'tools'/filename
                saved = path.read_bytes()
                path.unlink()
                with patch.object(bootstrap_local, 'ROOT', self.root), patch.object(bootstrap_local, '_copy_runtime') as runtime, redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as failure:
                        bootstrap_local.main(['--source-root', str(source), '--godot', 'unused-godot'])
                    self.assertEqual(failure.exception.code, 2)
                    runtime.assert_not_called()
                self.assertFalse((self.root/'reports').exists())
                self.assertFalse((self.root/'bin').exists())
                path.write_bytes(saved)

    def test_import_only_does_not_require_authoring_scripts(self):
        for filename in set(bootstrap_local.AUTHORING_TOOLS) - set(bootstrap_local.IMPORT_TOOLS):
            (self.root/'tools'/filename).unlink()
        with patch.object(bootstrap_local, 'ROOT', self.root), patch.object(bootstrap_local, 'import_runtime_assets') as imported, redirect_stdout(io.StringIO()):
            self.assertEqual(bootstrap_local.main(['--import-only', '--godot', 'unused-godot']), 0)
        imported.assert_called_once()
        report = json.loads((self.root/'reports/bootstrap_local.json').read_text(encoding='utf-8'))
        self.assertEqual(set(report['tool_dependencies_sha256']), {'tools/'+name for name in bootstrap_local.IMPORT_TOOLS})
        self.assertFalse(report['ready'])

    def test_package_gate_rejects_missing_tune_even_with_matching_manifest(self):
        self.assertEqual(verify_package.payload_check(self.root, {'files': []}), [])
        (self.root/'tools/tune_visuals.py').unlink()
        self.assertIn('Missing bootstrap tool dependency: tools/tune_visuals.py', verify_package.payload_check(self.root, {'files': []}))

    def test_builder_declares_every_python_authoring_dependency_before_first_new_item(self):
        source = (ROOT/'tools/build_local.ps1').read_text(encoding='utf-8-sig')
        declaration = source.split('$payloadTools = ', 1)[1].split('\n', 1)[0]
        for filename in bootstrap_local.AUTHORING_TOOLS:
            self.assertIn("'"+filename+"'", declaration)
        self.assertLess(source.index('Missing package tool dependency'), source.index('New-Item -ItemType Directory'))

    def test_tuning_module_import_and_help_do_not_write_recipes(self):
        scripts = self.root/'tools'
        script = scripts/'tune_import_only.py'
        script.write_bytes((ROOT/'tools/tune_visuals.py').read_bytes())
        recipes = self.root/'resources/visuals.json'
        recipes.parent.mkdir()
        recipes.write_text('must remain untouched', encoding='utf-8')
        spec = importlib.util.spec_from_file_location('tune_import_only', script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(recipes.read_text(encoding='utf-8'), 'must remain untouched')
        with redirect_stdout(io.StringIO()), self.assertRaises(SystemExit) as failure:
            module.main(['--help'])
        self.assertEqual(failure.exception.code, 0)
        self.assertEqual(recipes.read_text(encoding='utf-8'), 'must remain untouched')

    def test_tuning_preserves_previous_recipe_semantics_and_exact_output_bytes(self):
        baseline = subprocess.check_output(['git', 'show', 'f83c809fa4fe7fe970a3b0037b20416708352880:tools/tune_visuals.py'], cwd=ROOT)
        old_root = self.root/'old'
        new_root = self.root/'new'
        recipes = {
            'd69_097': {'source_id': '097', 'data': 'res://assets/actors/097/actor-data.tres', 'root_motion_bones': ['hips'], 'kept': 'unchanged'},
            'd69_084': {'source_id': '084', 'data': 'res://assets/actors/084/actor-data.tres', 'root_motion_bones': ['hips', 'unused']},
        }
        catalog = {'number_entries': [{'source_id': key, 'exports': [{'skeleton_bounds': {'height': height, 'y': y}}]} for key, height, y in [('097', 300, -20), ('084', 250, -10)]]}
        for project in (old_root, new_root):
            (project/'resources').mkdir(parents=True)
            (project/'reports').mkdir()
            (project/'tools').mkdir()
            (project/'resources/visuals.json').write_text(json.dumps(recipes), encoding='utf-8')
            (project/'reports/spine_catalog.json').write_text(json.dumps(catalog), encoding='utf-8')
            actor = project/'assets/actors/084/actor.spine-json'
            actor.parent.mkdir(parents=True)
            actor.write_text(json.dumps({'animations': {'idle': {'bones': {'hips': {'translate': []}}}}}), encoding='utf-8')
        script = old_root/'tools/tune_visuals.py'
        script.write_bytes(baseline)
        run = subprocess.run([sys.executable, str(script)], cwd=old_root, capture_output=True, text=True, timeout=15)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(tune_visuals.tune(new_root), 2)
        old, new = old_root/'resources/visuals.json', new_root/'resources/visuals.json'
        self.assertEqual(new.read_bytes(), old.read_bytes())
        self.assertEqual(hashlib.sha256(new.read_bytes()).hexdigest(), hashlib.sha256(old.read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()
