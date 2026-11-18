"""Run isolated game checks; a Godot zero exit does not hide script errors."""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path('F:/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=DEFAULT_GODOT)
    parser.add_argument('--visual', action='store_true')
    args = parser.parse_args()
    cases = [('BattleSmoke', 'BATTLE_SMOKE'), ('ProfileSmoke', 'PROFILE_SMOKE')]
    if args.visual:
        cases.append(('MainFlow', 'MAIN_FLOW'))
    results = []
    for name, marker in cases:
        command = [str(args.godot), '--path', str(ROOT)]
        if name != 'MainFlow':
            command.append('--headless')
        command += ['--script', f'res://tests/{name}.gd']
        try:
            run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
            output = run.stdout + run.stderr
            (ROOT / 'reports' / f'{name}.log').write_text(output, encoding='utf-8')
            passed = run.returncode == 0 and marker in run.stdout and 'SCRIPT ERROR:' not in output and 'ERROR:' not in output
            results.append({'case': name, 'passed': passed, 'exit_code': run.returncode})
        except subprocess.TimeoutExpired:
            results.append({'case': name, 'passed': False, 'error': 'timeout'})
        print(name, 'PASS' if results[-1]['passed'] else 'FAIL', flush=True)
    report = {'passed': all(case['passed'] for case in results), 'cases': results, 'reject_script_errors': True}
    (ROOT / 'reports' / 'checks.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
