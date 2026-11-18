"""Run each native skeleton in its own Godot process, fail on crashes/timeouts."""
from pathlib import Path
import argparse, json, subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path('F:/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=DEFAULT_GODOT)
    parser.add_argument('--ids', default='097,312,314,072,163,084,018,168,253,254,046,285,271,110,023,147,069,057,059,036,094')
    args = parser.parse_args()
    results = []
    previous_path = ROOT/'reports/spine_verify.json'
    previous = json.loads(previous_path.read_text(encoding='utf-8')).get('results', []) if previous_path.exists() else []
    config_path = ROOT / 'resources/visuals.json'
    config = json.loads(config_path.read_text(encoding='utf-8'))
    folder = ROOT / 'reports/spine_probes'
    folder.mkdir(parents=True, exist_ok=True)
    for number in args.ids.split(','):
        key = 'd69_' + number.zfill(3)
        path = folder / (key + '.json')
        if path.exists(): path.unlink()
        try:
            run = subprocess.run([str(args.godot), '--headless', '--path', str(ROOT), '--script', 'res://tests/SpineProbe.gd', '--', key, str(path)], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=50)
            (folder / (key+'.log')).write_text(run.stdout+run.stderr, encoding='utf-8')
            data = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
            success = run.returncode == 0 and data.get('passed') is True and 'SPINE_PROBE_COMPLETE' in run.stdout and 'SCRIPT ERROR' not in run.stderr and 'ERROR:' not in run.stderr
            result = {'visual_id':key, 'source_id':number, 'passed':success, 'exit_code':run.returncode, 'animation_count':len(data.get('animations',[])), 'log':str(folder/(key+'.log'))}
        except subprocess.TimeoutExpired:
            result = {'visual_id':key,'source_id':number,'passed':False,'error':'timeout'}
        if result['passed']: config[key]['status']='runtime_pass'
        else: config[key]['status']='runtime_failed'
        results.append(result)
        print('PASS' if result['passed'] else 'FAIL', key, flush=True)
    keyed = {result['visual_id']:result for result in previous}
    keyed.update({result['visual_id']:result for result in results})
    results = list(keyed.values())
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2),encoding='utf-8')
    (ROOT/'reports/spine_verify.json').write_text(json.dumps({'schema':1,'results':results,'passed':all(x['passed'] for x in results)},ensure_ascii=False,indent=2),encoding='utf-8')
    return 0 if all(x['passed'] for x in results) else 1

if __name__ == '__main__': raise SystemExit(main())
