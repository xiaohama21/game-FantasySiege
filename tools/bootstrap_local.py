"""Build local research assets from user-owned sources; never download or publish them."""
from pathlib import Path
import argparse, shutil, subprocess, sys, tempfile
import spine_pipeline
ROOT = Path(__file__).resolve().parents[1]
IDS = '097,312,314,072,163,084,018,168,253,254,046,285,271,110,023,147,069,057,059,036,094'

def _editor_import(godot, phase):
    run = subprocess.run([str(godot),'--headless','--path',str(ROOT),'--editor','--quit'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    folder = ROOT/'reports'
    folder.mkdir(parents=True,exist_ok=True)
    (folder/('bootstrap_'+phase+'.log')).write_text(run.stdout+run.stderr,encoding='utf-8')
    if run.returncode != 0 or any(marker in run.stdout+run.stderr for marker in ('SCRIPT ERROR:','ERROR:','CrashHandler')):
        raise RuntimeError('Godot '+phase+' import failed; see reports/bootstrap_'+phase+'.log')

def import_runtime_assets(godot):
    """Import PNGs at their final paths before loading native atlas importers."""
    project_root = ROOT.resolve()
    actors = (ROOT/'assets/actors').resolve()
    actors.relative_to(project_root)
    staging_parent = (ROOT/'reports/native_texture_staging').resolve()
    staging_parent.relative_to(project_root)
    staging_parent.mkdir(parents=True,exist_ok=True)
    (staging_parent/'.gdignore').write_text('',encoding='utf-8')
    temporary = tempfile.TemporaryDirectory(prefix='bootstrap_',dir=staging_parent)
    staging = Path(temporary.name)
    staging.relative_to(staging_parent)
    moved = []
    try:
        for directory in actors.iterdir():
            if not directory.is_dir() or len(directory.name)!=3 or not directory.name.isdigit(): continue
            if directory.is_symlink(): raise ValueError('refusing a symlinked runtime actor directory')
            spine_pipeline.invalidate_native_imports(directory)
            for name in ('actor.atlas','actor.spine-json','actor-data.tres'):
                source = directory/name
                if source.is_symlink(): raise ValueError('refusing a symlinked native runtime file')
                source.resolve().relative_to(actors)
                if not source.exists(): continue
                destination = staging/directory.name/name
                destination.parent.mkdir(parents=True,exist_ok=True)
                shutil.move(str(source),str(destination))
                moved.append((source,destination))
        _editor_import(godot,'textures')
    finally:
        for source,destination in reversed(moved):
            if destination.exists(): shutil.move(str(destination),str(source))
        temporary.cleanup()
    _editor_import(godot,'native')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,help='Read-only D69 315 source package; required unless import-only')
    parser.add_argument('--runtime-from',type=Path,help='Read-only installed spine-godot bin directory, e.g. TowerDefense/bin')
    parser.add_argument('--godot',type=Path,help='Optional Godot console executable: import and verify after build')
    parser.add_argument('--import-only',action='store_true',help='Only two-phase import of assets already copied into this project/package')
    args = parser.parse_args()
    if args.import_only:
        if not args.godot: parser.error('--import-only requires --godot')
        import_runtime_assets(args.godot)
        print('LOCAL_IMPORT_READY: texture and native import phases completed')
        return
    if not args.source_root or not args.source_root.is_dir(): parser.error('source-root directory does not exist')
    if args.runtime_from:
        if not (args.runtime_from/'spine_godot_extension.gdextension').is_file(): parser.error('runtime-from must contain spine_godot_extension.gdextension')
        (ROOT/'bin/windows').mkdir(parents=True,exist_ok=True)
        shutil.copy2(args.runtime_from/'spine_godot_extension.gdextension',ROOT/'bin/spine_godot_extension.gdextension')
        for name in ('editor','template_debug','template_release'):
            filename='libspine_godot.windows.'+name+'.x86_64.dll'
            shutil.copy2(args.runtime_from/'windows'/filename,ROOT/'bin/windows'/filename)
    commands=[['spine_pipeline.py','scan','--source-root',str(args.source_root)],
              ['spine_pipeline.py','import','--source-root',str(args.source_root),'--ids',IDS,'--allow-deform'],
              ['tune_visuals.py']]
    for command in commands:
        subprocess.run([sys.executable,str(ROOT/'tools'/command[0]),*command[1:]],cwd=ROOT,check=True)
    if args.godot:
        import_runtime_assets(args.godot)
        subprocess.run([sys.executable,str(ROOT/'tools/verify_spine.py'),'--godot',str(args.godot)],cwd=ROOT,check=True)
    print('LOCAL_ASSETS_READY: restricted sources and derived visuals remain local; Git contains code and recipes only')

if __name__=='__main__': main()
