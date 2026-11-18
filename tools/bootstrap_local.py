"""Build local research assets from user-owned sources; never download or publish them."""
from pathlib import Path
import argparse, shutil, subprocess, sys
ROOT = Path(__file__).resolve().parents[1]
IDS = '097,312,314,072,163,084,018,168,253,254,046,285,271'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,required=True,help='Read-only D69 315 source package')
    parser.add_argument('--runtime-from',type=Path,help='Read-only installed spine-godot bin directory, e.g. TowerDefense/bin')
    parser.add_argument('--godot',type=Path,help='Optional Godot console executable: import and verify after build')
    args = parser.parse_args()
    if not args.source_root.is_dir(): parser.error('source-root directory does not exist')
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
        subprocess.run([str(args.godot),'--headless','--path',str(ROOT),'--editor','--quit'],cwd=ROOT,check=True)
        subprocess.run([sys.executable,str(ROOT/'tools/verify_spine.py'),'--godot',str(args.godot)],cwd=ROOT,check=True)
    print('LOCAL_ASSETS_READY: restricted sources and derived visuals remain local; Git contains code and recipes only')

if __name__=='__main__': main()
