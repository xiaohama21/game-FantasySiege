"""Verify import failures and source boundaries cannot reuse stale success."""
from pathlib import Path
import contextlib, io, json, os, shutil, subprocess, sys, tempfile, unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import spine_pipeline

class NativeImportSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.original_root = spine_pipeline.ROOT
        spine_pipeline.ROOT = self.root
        self.actor = self.root/'assets/actors/084'
        self.actor.mkdir(parents=True)

    def tearDown(self):
        spine_pipeline.ROOT = self.original_root
        self.temp.cleanup()

    def test_only_stale_native_remaps_are_removed(self):
        target = self.actor/'actor.spine-json.import'
        target.write_text('stale native remap')
        atlas = self.actor/'actor.atlas.import'
        atlas.write_text('stale native atlas remap')
        texture = self.actor/'Hero_Evan_A.png.import'
        texture.write_text('valid texture remap')
        source = self.actor/'actor.spine-json'
        source.write_text('valid derived JSON')
        self.assertEqual(spine_pipeline.invalidate_native_imports(self.actor),['actor.spine-json.import','actor.atlas.import'])
        self.assertFalse(target.exists())
        self.assertFalse(atlas.exists())
        self.assertEqual(texture.read_text(),'valid texture remap')
        self.assertEqual(source.read_text(),'valid derived JSON')
        self.assertEqual(spine_pipeline.invalidate_native_imports(self.actor),[])

    def test_source_and_outside_directory_are_rejected(self):
        for folder in [self.root/'assets/source/d69_084',self.root/'old_project/084',self.actor/'nested']:
            folder.mkdir(parents=True)
            target = folder/'actor.spine-json.import'
            target.write_text('must remain')
            with self.assertRaises(ValueError): spine_pipeline.invalidate_native_imports(folder)
            self.assertTrue(target.exists())

class ImportIntegrity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)/'project'
        self.root.mkdir()
        self.source = Path(self.temp.name)/'source'
        self.source.mkdir()
        self.original_root = spine_pipeline.ROOT
        spine_pipeline.ROOT = self.root

    def tearDown(self):
        spine_pipeline.ROOT = self.original_root
        self.temp.cleanup()

    def source_actor(self, number, version='4.3.0'):
        folder = self.source/(number+'_fixture')
        folder.mkdir()
        spine_pipeline.write(folder/'actor.json', {
            'skeleton':{'spine':version, 'height':240}, 'bones':[{'name':'root'}],
            'slots':[], 'skins':{},
            'animations':{'Idle':{'bones':{'root':{'rotate':[{'time':0}, {'time':1}]}}}}
        })
        (folder/'actor.atlas').write_text('texture.png\nsize: 1, 1\nformat: RGBA8888\n', encoding='utf-8')
        (folder/'texture.png').write_bytes(b'fixture texture')
        return folder

    def catalog(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return spine_pipeline.scan(self.source)

    def import_quietly(self, ids, source=None):
        with contextlib.redirect_stdout(io.StringIO()):
            return spine_pipeline.import_ids(ids, source or self.source)

    @contextlib.contextmanager
    def directory_link(self, link, target):
        link.parent.mkdir(parents=True, exist_ok=True)
        if os.name == 'nt':
            # Junction creation is unprivileged and both paths are test-owned.
            result = subprocess.run(['cmd', '/c', 'mklink', '/J', str(link), str(target)], capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, str(result.stdout)+str(result.stderr))
        else:
            link.symlink_to(target, target_is_directory=True)
        try:
            yield
        finally:
            # Remove only the link itself, never traverse or delete its target.
            link.absolute().relative_to(Path(self.temp.name).absolute())
            if os.name == 'nt': link.rmdir()
            else: link.unlink()

    @staticmethod
    def file_snapshot(directory):
        return {str(p.relative_to(directory)):p.read_bytes() for p in directory.rglob('*') if p.is_file()}

    def test_destination_directory_links_cannot_modify_external_sentinels(self):
        self.source_actor('084')
        self.catalog()
        external = Path(self.temp.name)/'external-output'
        external.mkdir()
        for filename in ('actor.atlas', 'actor.spine-json', 'actor.json', 'texture.png', '.gdignore'):
            (external/filename).write_bytes(('external sentinel '+filename).encode())
        before = self.file_snapshot(external)
        for relative in ('assets', 'assets/actors', 'assets/source',
                         'assets/actors/084', 'assets/source/d69_084'):
            with self.subTest(directory=relative):
                link = self.root/relative
                with self.directory_link(link, external):
                    report = self.import_quietly(['084'])
                    self.assertFalse(report['passed'])
                    self.assertIn('import destination redirects', report['results'][0]['error'])
                    self.assertEqual(self.file_snapshot(external), before)

    def test_existing_hardlinked_output_files_are_rejected_before_any_copy(self):
        self.source_actor('084')
        self.catalog()
        external = Path(self.temp.name)/'external-file'
        external.write_bytes(b'external sentinel must not be truncated')
        targets = ('assets/source/.gdignore', 'assets/source/d69_084/actor.json',
                   'assets/actors/084/actor.atlas', 'assets/actors/084/texture.png',
                   'assets/actors/084/actor.spine-json', 'assets/actors/084/actor-data.tres',
                   'assets/actors/084/provenance.json', 'assets/actors/084/actor.atlas.import',
                   'assets/actors/084/actor.spine-json.import')
        for relative in targets:
            with self.subTest(file=relative):
                target = self.root/relative
                target.parent.mkdir(parents=True, exist_ok=True)
                os.link(external, target)
                before = self.file_snapshot(self.root/'assets')
                try:
                    report = self.import_quietly(['084'])
                    self.assertFalse(report['passed'])
                    self.assertIn('hard-linked import file', report['results'][0]['error'])
                    self.assertEqual(external.read_bytes(), b'external sentinel must not be truncated')
                    self.assertEqual(self.file_snapshot(self.root/'assets'), before)
                finally:
                    target.unlink()

    def test_output_file_symlink_is_rejected_even_inside_actor_directory(self):
        actor = self.root/'assets/actors/084'
        actor.mkdir(parents=True)
        sentinel = actor/'untouched.txt'
        sentinel.write_bytes(b'internal sentinel')
        linked = actor/'actor.atlas'
        try:
            linked.symlink_to(sentinel)
        except OSError as exc:
            self.skipTest('file symlink creation unavailable: '+str(exc))
        try:
            with self.assertRaisesRegex(ValueError, 'linked import file'):
                spine_pipeline.validate_import_destinations('084', [], [])
            self.assertEqual(sentinel.read_bytes(), b'internal sentinel')
        finally:
            linked.unlink()

    def test_batch_failure_keeps_success_and_downgrades_stale_status(self):
        self.source_actor('084', version='3.8.99')
        self.source_actor('085')
        self.catalog()
        stale_actor = self.root/'assets/actors/084'
        stale_actor.mkdir(parents=True)
        (stale_actor/'old-evidence.txt').write_text('previous asset retained')
        spine_pipeline.write(self.root/'resources/visuals.json', {
            'd69_084':{'status':'runtime_pass', 'scale':.5},
            'unrelated':{'status':'runtime_pass'}
        })
        with patch.object(spine_pipeline.converter, 'upgrade', side_effect=ValueError('fixture conversion failed')):
            report = self.import_quietly(['084', '085'])
        self.assertFalse(report['passed'])
        self.assertEqual(report['requested_ids'], ['084', '085'])
        self.assertEqual([r['status'] for r in report['results']], ['import_rejected', 'converted'])
        self.assertIn('fixture conversion failed', report['results'][0]['error'])
        self.assertEqual(spine_pipeline.read(self.root/'reports/spine_import.json'), report)
        config = spine_pipeline.read(self.root/'resources/visuals.json')
        self.assertEqual(config['d69_084'], {'status':'import_rejected', 'scale':.5})
        self.assertEqual(config['d69_085']['status'], 'converted')
        self.assertEqual(config['unrelated']['status'], 'runtime_pass')
        self.assertEqual((stale_actor/'old-evidence.txt').read_text(), 'previous asset retained')

    def test_existing_catalog_cannot_import_another_source(self):
        self.source_actor('084')
        self.catalog()
        other_source = Path(self.temp.name)/'other-source'
        other_source.mkdir()
        config_path = self.root/'resources/visuals.json'
        spine_pipeline.write(config_path, {'d69_084':{'status':'runtime_pass'}})
        before = config_path.read_bytes()
        report = self.import_quietly(['084'], other_source)
        self.assertFalse(report['passed'])
        self.assertIn('source_root does not match', report['error'])
        self.assertIn('run scan', report['error'])
        self.assertEqual(config_path.read_bytes(), before)
        self.assertFalse((self.root/'assets').exists())

    def test_catalog_paths_are_checked_before_any_asset_writes(self):
        self.source_actor('084')
        base = self.catalog()
        outside = str(Path(self.temp.name)/'outside-source.txt')
        alterations = {
            'directory':lambda e: e.update(directory=outside),
            'json':lambda e: e['exports'][0].update(json=outside),
            'atlas':lambda e: e['exports'][0].update(atlas=outside),
            'files':lambda e: e['exports'][0]['files'][0].update(path=outside),
            'missing_files':lambda e: e['exports'][0].update(missing_files=[outside]),
            'source_projects':lambda e: e.update(source_projects=[{'path':outside}]),
            'notices':lambda e: e['license'].update(notices=[{'path':outside}]),
            'scan_errors':lambda e: e.update(scan_errors=[{'path':outside}])
        }
        for label, alter in alterations.items():
            with self.subTest(path=label):
                catalog = json.loads(json.dumps(base))
                alter(catalog['number_entries'][0])
                spine_pipeline.write(self.root/'reports/spine_catalog.json', catalog)
                report = self.import_quietly(['084'])
                self.assertFalse(report['passed'])
                self.assertIn('outside --source-root', report['error'])
                self.assertFalse((self.root/'assets').exists())

    def test_atlas_page_cannot_escape_destination_even_inside_source(self):
        self.source_actor('084')
        catalog = self.catalog()
        catalog['number_entries'][0]['exports'][0]['texture_pages'] = ['../shared.png']
        spine_pipeline.write(self.root/'reports/spine_catalog.json', catalog)
        report = self.import_quietly(['084'])
        self.assertFalse(report['passed'])
        self.assertIn('unsafe atlas texture page', report['error'])
        self.assertFalse((self.root/'assets').exists())

    def test_resolved_source_alias_matches_and_success_is_explicit(self):
        self.source_actor('084')
        catalog = self.catalog()
        self.assertEqual(catalog['source_root'], str(self.source.resolve()))
        report = self.import_quietly(['084'], self.source/'..'/'source')
        self.assertTrue(report['passed'])
        self.assertEqual(report['source_root'], str(self.source.resolve()))
        self.assertEqual(report['results'][0]['status'], 'converted')

    def test_duplicate_and_empty_requests_fail_without_asset_writes(self):
        self.source_actor('084')
        self.catalog()
        for ids in ([], ['084', '084']):
            with self.subTest(ids=ids):
                report = self.import_quietly(ids)
                self.assertFalse(report['passed'])
                self.assertFalse((self.root/'assets').exists())

    def test_missing_requested_id_is_rejected_without_hiding_valid_results(self):
        self.source_actor('084')
        self.catalog()
        report = self.import_quietly(['084', '085'])
        self.assertFalse(report['passed'])
        self.assertEqual([r['source_id'] for r in report['results']], ['084', '085'])
        self.assertEqual([r['status'] for r in report['results']], ['converted', 'import_rejected'])
        self.assertIn('085', report['results'][1]['error'])

    def test_real_cli_failure_exits_nonzero_and_preserves_batch_report(self):
        self.source_actor('084')
        self.source_actor('085', version='2.1')
        tools_dir = self.root/'tools'
        tools_dir.mkdir()
        for filename in ('spine_pipeline.py', 'spine_upgrade_38_to_43.py'):
            shutil.copy2(Path(spine_pipeline.__file__).parent/filename, tools_dir/filename)
        args = [sys.executable, str(tools_dir/'spine_pipeline.py'), 'import',
                '--source-root', str(self.source), '--ids', '084,085']
        result = subprocess.run(args, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1, result.stdout+result.stderr)
        report = spine_pipeline.read(self.root/'reports/spine_import.json')
        self.assertFalse(report['passed'])
        self.assertEqual([r['status'] for r in report['results']], ['converted', 'import_rejected'])
        self.assertIn('unsupported source export version', report['results'][1]['error'])
        args[-1] = '084'
        result = subprocess.run(args, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertTrue(spine_pipeline.read(self.root/'reports/spine_import.json')['passed'])

if __name__=='__main__': unittest.main()
