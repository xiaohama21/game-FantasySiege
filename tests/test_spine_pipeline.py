"""Verify stale native remap cleanup stays confined to derived actor files."""
from pathlib import Path
import sys, tempfile, unittest

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

if __name__=='__main__': unittest.main()
