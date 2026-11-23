"""Verify two-phase native import restores files on success and failure."""
from pathlib import Path
import hashlib, json, os, subprocess, sys, tempfile, unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import bootstrap_local


def mock_tools(project):
    for filename in bootstrap_local.AUTHORING_TOOLS:
        path = project/'tools'/filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('mock tool dependency: '+filename, encoding='utf-8')

class BootstrapImportRestore(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.actor = self.root/'assets/actors/084'
        self.actor.mkdir(parents=True)
        mock_tools(self.root)
        self.native = ['actor.atlas','actor.spine-json','actor-data.tres']
        for name in self.native: (self.actor/name).write_text('original-'+name)
        (self.actor/'body.png').write_text('texture-input')
        self.root_patch = patch.object(bootstrap_local,'ROOT',self.root)
        self.root_patch.start()
        self.pipeline_root_patch = patch.object(bootstrap_local.spine_pipeline,'ROOT',self.root)
        self.pipeline_root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.pipeline_root_patch.stop()
        self.temp.cleanup()

    def assertRestored(self):
        for name in self.native: self.assertEqual((self.actor/name).read_text(),'original-'+name)
        self.assertEqual((self.actor/'body.png').read_text(),'texture-input')

    def test_texture_phase_hides_native_then_restores(self):
        (self.actor/'actor.atlas.import').write_text('stale native mapping')
        (self.actor/'actor.spine-json.import').write_text('stale native mapping')
        phases=[]
        def editor(godot,phase):
            phases.append(phase)
            self.assertTrue((self.actor/'body.png').exists())
            if phase=='textures':
                for name in self.native: self.assertFalse((self.actor/name).exists())
            else: self.assertRestored()
        with patch.object(bootstrap_local,'_editor_import',side_effect=editor):
            bootstrap_local.import_runtime_assets('unused-godot')
        self.assertEqual(phases,['textures','native'])
        self.assertRestored()
        self.assertFalse((self.actor/'actor.atlas.import').exists())
        self.assertFalse((self.actor/'actor.spine-json.import').exists())

    def test_texture_failure_restores_every_native_file(self):
        with patch.object(bootstrap_local,'_editor_import',side_effect=RuntimeError('simulated import failure')):
            with self.assertRaises(RuntimeError): bootstrap_local.import_runtime_assets('unused-godot')
        self.assertRestored()

    def test_editor_zero_exit_leaks_are_rejected_and_log_is_preserved(self):
        for leak in ('ObjectDB instances leaked at exit (run with --verbose for details)',
                     'Leaked instance: AudioStreamWAV'):
            with self.subTest(leak=leak):
                completed = subprocess.CompletedProcess(['unused-godot'],0,'import completed',leak)
                with patch.object(bootstrap_local.subprocess,'run',return_value=completed):
                    with self.assertRaises(bootstrap_local.BootstrapError) as failure:
                        bootstrap_local._editor_import('unused-godot','textures')
                self.assertEqual(failure.exception.exit_code,0)
                log = self.root/'reports/bootstrap_textures.log'
                self.assertTrue(log.is_file())
                self.assertEqual(log.read_text(),'import completed\n'+leak)

    def test_import_only_zero_exit_leak_returns_failure_and_restores_files(self):
        leak = 'WARNING: ObjectDB instances leaked at exit'
        completed = subprocess.CompletedProcess(['unused-godot'],0,'import completed',leak)
        with patch.object(bootstrap_local.subprocess,'run',return_value=completed) as command:
            self.assertEqual(bootstrap_local.main(['--import-only','--godot','unused-godot']),1)
        command.assert_called_once()
        self.assertRestored()
        report = json.loads((self.root/'reports/bootstrap_local.json').read_text())
        self.assertEqual(report['status'],'failed')
        self.assertFalse(report['ready'])
        self.assertEqual(report['stages'][0]['exit_code'],0)
        self.assertFalse(report['stages'][0]['passed'])
        frozen_log = Path(report['stages'][0]['evidence'][0]['snapshot'])
        self.assertIn(leak,frozen_log.read_text())

    def test_import_only_needs_no_external_source_or_rebuild(self):
        with patch.object(sys,'argv',['bootstrap_local.py','--import-only','--godot','package.exe']), patch.object(bootstrap_local,'import_runtime_assets') as importer:
            self.assertEqual(bootstrap_local.main(),0)
        importer.assert_called_once_with(Path('package.exe').resolve())
        report = json.loads((self.root/'reports/bootstrap_local.json').read_text())
        self.assertEqual(report['status'],'imported')
        self.assertFalse(report['ready'])
        self.assertEqual([stage['name'] for stage in report['stages']],['runtime_import'])

    def test_import_only_rejects_missing_engine(self):
        with patch.object(sys,'argv',['bootstrap_local.py','--import-only']), patch.object(bootstrap_local,'import_runtime_assets') as importer:
            with self.assertRaises(SystemExit) as failure: bootstrap_local.main()
        self.assertEqual(failure.exception.code,2)
        importer.assert_not_called()


class BootstrapFullAuthoring(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root/'read-only-source'
        self.source.mkdir()
        mock_tools(self.root)
        (self.root/'resources').mkdir()
        (self.root/'reports').mkdir()
        self.ids = bootstrap_local.IDS.split(',')
        self.visual_ids = ['d69_'+number for number in self.ids]
        self.calls = []
        self.failure_at = None
        self.bad_conversion = None
        self.stale_conversion = False
        self.mutate_at = None
        self.root_patch = patch.object(bootstrap_local,'ROOT',self.root)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.temp.cleanup()

    def write_json(self,path,data):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(data),encoding='utf-8')

    def recipes(self,status):
        self.write_json(self.root/'resources/visuals.json',{key:{'status':status} for key in self.visual_ids})

    def sha(self):
        return hashlib.sha256((self.root/'resources/visuals.json').read_bytes()).hexdigest()

    def report(self):
        return json.loads((self.root/'reports/bootstrap_local.json').read_text())

    def fake_run(self,command,**options):
        filename = Path(command[1]).name
        if filename == 'spine_pipeline.py':
            name = 'scan' if command[2] == 'scan' else 'convert'
        elif filename == 'tune_visuals.py': name = 'tune'
        elif filename == 'verify_spine.py': name = 'native_author' if '--update-status' in command else 'native_readonly'
        else: name = 'portraits_readonly' if '--check' in command else 'portraits_generate'
        self.calls.append(name)
        if self.failure_at == name:
            raise subprocess.CalledProcessError(7,command,output='failed command output',stderr='failure reason')
        if name == 'scan':
            self.write_json(self.root/'reports/spine_catalog.json',{'source_root':str(self.source)})
        elif name == 'convert':
            self.recipes('converted')
            results = [{'source_id':number,'status':'converted'} for number in self.ids]
            if self.bad_conversion == 'missing': results.pop()
            if self.bad_conversion == 'duplicate': results[-1] = results[0]
            if self.bad_conversion == 'rejected': results[-1]['status'] = 'import_rejected'
            path = self.root/'reports/spine_import.json'
            self.write_json(path,{'passed':True,'results':results})
            if self.stale_conversion: os.utime(path,ns=(1,1))
        elif name in ('native_author','native_readonly'):
            if name == 'native_author': self.recipes('runtime_pass')
            self.write_json(self.root/'reports/spine_verify.json',{
                'passed':True,'update_status_requested':name == 'native_author',
                'selected_visual_ids':self.visual_ids,
                'results':[{'visual_id':key,'passed':True} for key in self.visual_ids],
                'config_sha256_after':self.sha(),'config_unchanged':name != 'native_author',
                'config_write_performed':name == 'native_author'})
        elif name in ('portraits_generate','portraits_readonly'):
            if self.mutate_at == name: self.recipes('unexpected_mutation')
            self.write_json(self.root/'reports/portraits_local.json',{
                'passed':True,'entries':[{} for _ in range(12)],'visuals_sha256':self.sha()})
            if name == 'portraits_generate':
                self.write_json(self.root/'assets/portraits/manifest.json',{'passed':True,'visuals_sha256':self.sha()})
        return subprocess.CompletedProcess(command,0,'stage completed\n','')

    def fake_import(self,godot):
        self.calls.append('runtime_import')

    def fake_editor(self,godot,phase):
        self.calls.append(phase+'_import')
        if self.mutate_at == 'portraits_import': self.recipes('unexpected_mutation')

    def run_bootstrap(self,with_godot=True):
        argv = ['--source-root',str(self.source)]
        if with_godot: argv.extend(['--godot','unused-godot'])
        with patch.object(bootstrap_local.subprocess,'run',side_effect=self.fake_run), \
             patch.object(bootstrap_local,'import_runtime_assets',side_effect=self.fake_import), \
             patch.object(bootstrap_local,'_editor_import',side_effect=self.fake_editor):
            return bootstrap_local.main(argv)

    def test_full_authoring_precedes_portraits_then_freezes_readonly(self):
        self.assertEqual(self.run_bootstrap(),0)
        expected = ['scan','convert','tune','runtime_import','native_author','portraits_generate',
                    'portraits_import','native_readonly','portraits_readonly']
        self.assertEqual(self.calls,expected)
        report = self.report()
        self.assertEqual([stage['name'] for stage in report['stages']],expected)
        self.assertTrue(report['ready'])
        self.assertEqual(report['status'],'ready')
        self.assertEqual(report['frozen_visuals_sha256'],self.sha())
        author = next(stage for stage in report['stages'] if stage['name'] == 'native_author')
        frozen = Path(author['evidence'][0]['snapshot'])
        self.assertTrue(json.loads(frozen.read_text())['update_status_requested'])
        self.assertFalse(json.loads((self.root/'reports/spine_verify.json').read_text())['update_status_requested'])
        self.assertEqual(author['evidence'][0]['sha256'],hashlib.sha256(frozen.read_bytes()).hexdigest())
        for stage in report['stages']:
            self.assertTrue(stage['passed'])
            self.assertEqual(stage['exit_code'],0)

    def test_conversion_mode_does_not_claim_complete_dependencies(self):
        self.assertEqual(self.run_bootstrap(with_godot=False),0)
        self.assertEqual(self.calls,['scan','convert','tune'])
        report = self.report()
        self.assertEqual(report['status'],'converted')
        self.assertFalse(report['ready'])
        self.assertIsNone(report['frozen_visuals_sha256'])

    def test_each_conversion_integrity_failure_stops_before_tune(self):
        for invalid in ('missing','duplicate','rejected'):
            with self.subTest(invalid=invalid):
                self.calls.clear()
                self.bad_conversion = invalid
                self.assertEqual(self.run_bootstrap(),1)
                self.assertEqual(self.calls,['scan','convert'])
                report = self.report()
                self.assertEqual(report['status'],'failed')
                self.assertFalse(report['ready'])
                self.assertFalse(report['stages'][-1]['passed'])
                self.assertEqual(report['stages'][-1]['exit_code'],0)

    def test_child_failure_preserves_exit_output_and_stops_later_steps(self):
        self.failure_at = 'portraits_generate'
        self.assertEqual(self.run_bootstrap(),1)
        self.assertEqual(self.calls[-1],'portraits_generate')
        report = self.report()
        self.assertFalse(report['ready'])
        failed = report['stages'][-1]
        self.assertEqual(failed['exit_code'],7)
        log = Path(report['run_directory'])/'portraits_generate.log'
        self.assertIn('failed command output',log.read_text())
        self.assertTrue((Path(report['run_directory'])/'bootstrap_local.json').is_file())

    def test_frozen_recipe_mutation_is_rejected_before_readonly_steps(self):
        for mutation in ('portraits_generate','portraits_import'):
            with self.subTest(mutation=mutation):
                self.calls.clear()
                self.mutate_at = mutation
                self.assertEqual(self.run_bootstrap(),1)
                self.assertEqual(self.calls[-1],mutation)
                self.assertNotIn('native_readonly',self.calls)
                self.assertIn('frozen visual recipes changed',self.report()['error'])
                self.assertFalse(self.report()['ready'])

    def test_nonzero_conversion_cannot_be_masked_by_old_success_report(self):
        self.write_json(self.root/'reports/spine_import.json',{'passed':True,'results':[
            {'source_id':number,'status':'converted'} for number in self.ids]})
        self.failure_at = 'convert'
        self.assertEqual(self.run_bootstrap(),1)
        self.assertEqual(self.calls,['scan','convert'])
        report = self.report()
        self.assertEqual(report['stages'][-1]['exit_code'],7)
        self.assertFalse(report['ready'])

    def test_zero_exit_requires_fresh_current_conversion_evidence(self):
        self.stale_conversion = True
        self.assertEqual(self.run_bootstrap(),1)
        self.assertEqual(self.calls,['scan','convert'])
        report = self.report()
        self.assertIn('stale bootstrap evidence',report['error'])
        self.assertFalse(report['stages'][-1]['evidence'][0]['fresh_for_stage'])
        self.assertFalse(report['ready'])

    def test_repeated_failures_keep_separate_evidence_runs(self):
        self.failure_at = 'convert'
        self.assertEqual(self.run_bootstrap(),1)
        first = Path(self.report()['run_directory'])
        self.calls.clear()
        self.assertEqual(self.run_bootstrap(),1)
        second = Path(self.report()['run_directory'])
        self.assertNotEqual(first,second)
        for folder in (first,second):
            frozen = json.loads((folder/'bootstrap_local.json').read_text())
            self.assertEqual(frozen['status'],'failed')
            self.assertEqual(frozen['stages'][-1]['exit_code'],7)
            self.assertTrue((folder/'convert.log').is_file())

if __name__=='__main__': unittest.main()
