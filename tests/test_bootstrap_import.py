"""Verify two-phase native import restores files on success and failure."""
from pathlib import Path
import sys, tempfile, unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import bootstrap_local

class BootstrapImportRestore(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.actor = self.root/'assets/actors/084'
        self.actor.mkdir(parents=True)
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

    def test_import_only_needs_no_external_source_or_rebuild(self):
        with patch.object(sys,'argv',['bootstrap_local.py','--import-only','--godot','package.exe']), patch.object(bootstrap_local,'import_runtime_assets') as importer:
            bootstrap_local.main()
        importer.assert_called_once_with(Path('package.exe'))

    def test_import_only_rejects_missing_engine(self):
        with patch.object(sys,'argv',['bootstrap_local.py','--import-only']), patch.object(bootstrap_local,'import_runtime_assets') as importer:
            with self.assertRaises(SystemExit) as failure: bootstrap_local.main()
        self.assertEqual(failure.exception.code,2)
        importer.assert_not_called()

if __name__=='__main__': unittest.main()
