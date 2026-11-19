"""Verify isolated native skeletons without changing source recipes by default."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time
from datetime import datetime, timezone
import run_checks

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path('F:/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe')


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'), parse_constant=run_checks._invalid_json_number)


def _probe(godot, key, folder):
    path = folder / (key + '.json')
    log = folder / (key + '.log')
    command = [str(godot), '--headless', '--path', str(ROOT), '--script', 'res://tests/SpineProbe.gd', '--', key, str(path)]
    started_ns = time.time_ns()
    output = ''
    result = {'visual_id': key, 'source_id': key.removeprefix('d69_'), 'passed': False,
              'exit_code': None, 'animation_count': 0, 'errors': [], 'log': str(log), 'command_line': command}
    try:
        path.unlink(missing_ok=True)
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                             encoding='utf-8', errors='replace', timeout=50)
        output = run_checks.joined_output(run.stdout, run.stderr)
        result['exit_code'] = run.returncode
        if run.returncode != 0:
            result['errors'].append('nonzero_exit')
        if re.search(r'(?m)^\s*SPINE_PROBE_COMPLETE(?:\s|$)', run_checks.ANSI_ESCAPE.sub('', run_checks.capture_text(run.stdout))) is None:
            result['errors'].append('completion_marker_missing')
        if not path.is_file():
            result['errors'].append('fresh_report_missing')
        else:
            if path.stat().st_mtime_ns + run_checks.TIMESTAMP_TOLERANCE_NS < started_ns:
                result['errors'].append('report_timestamp_before_run')
            data = _read_json(path)
            if not isinstance(data, dict):
                result['errors'].append('report_is_not_an_object')
            else:
                animations = data.get('animations', [])
                if not isinstance(animations, list) or not animations:
                    result['errors'].append('native_animation_report_missing')
                else:
                    result['animation_count'] = len(animations)
                if data.get('passed') is not True or data.get('native') is not True or data.get('visual_id') != key or data.get('errors') or data.get('failures'):
                    result['errors'].append('native_report_failed')
    except subprocess.TimeoutExpired as failure:
        output = run_checks.joined_output(failure.stdout, failure.stderr)
        result['errors'].append('timeout')
    except (OSError, ValueError, TypeError) as failure:
        output = run_checks.joined_output(output, str(failure))
        result['errors'].append('probe_or_report_failed: ' + str(failure))
    result['fatal_log_lines'] = run_checks.fatal_lines(output)
    result['diagnostic_log_lines'] = run_checks.diagnostic_lines(output)
    if result['fatal_log_lines'] or 'CrashHandler' in output:
        result['errors'].append('fatal_error_or_leak_log')
    log.write_text(output, encoding='utf-8')
    result['passed'] = not result['errors']
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=DEFAULT_GODOT)
    parser.add_argument('--ids', default='097,312,314,072,163,084,018,168,253,254,046,285,271,110,023,147,069,057,059,036,094')
    parser.add_argument('--update-status', action='store_true', help='Authoring only: explicitly update recipe runtime status; package verification must omit this option')
    args = parser.parse_args(argv)
    config_path = ROOT / 'resources/visuals.json'
    before_sha = _sha(config_path)
    config = _read_json(config_path)
    selected = []
    for number in args.ids.split(','):
        if not re.fullmatch(r'[0-9]{1,3}', number.strip()):
            parser.error('ids must be comma-separated source numbers')
        key = 'd69_' + number.strip().zfill(3)
        if key not in config or key in selected:
            parser.error('unknown or duplicate source id: ' + key)
        selected.append(key)
    folder = ROOT / 'reports/spine_probes'
    folder.mkdir(parents=True, exist_ok=True)
    results = []
    for key in selected:
        result = _probe(args.godot, key, folder)
        result['previous_status'] = config[key].get('status')
        results.append(result)
        print('PASS' if result['passed'] else 'FAIL', key, flush=True)

    failures = []
    write_performed = False
    if _sha(config_path) != before_sha:
        failures.append('source configuration changed during verification')
    elif args.update_status:
        changed = False
        for result in results:
            spec = config[result['visual_id']]
            status = spec.get('status')
            requested = status if result['passed'] and status in ('visual_checked', 'performance_checked') else ('runtime_pass' if result['passed'] else 'runtime_failed')
            if requested != status:
                spec['status'] = requested
                changed = True
        if changed:
            try:
                temporary = config_path.with_name(config_path.name + '.tmp')
                temporary.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding='utf-8')
                temporary.replace(config_path)
                write_performed = True
            except OSError as failure:
                failures.append('explicit status write failed: ' + str(failure))
    after_sha = _sha(config_path)
    version_match = re.search(r'^config/version="([^"\r\n]+)"', (ROOT / 'project.godot').read_text(encoding='utf-8-sig'), re.MULTILINE)
    report = {'schema': 2, 'program_version': version_match.group(1) if version_match else 'unknown',
              'results': results, 'selected_visual_ids': selected, 'passed': all(item['passed'] for item in results) and not failures,
              'failures': failures, 'config_sha256_before': before_sha, 'config_sha256_after': after_sha,
              'config_unchanged': before_sha == after_sha, 'update_status_requested': args.update_status,
              'config_write_performed': write_performed, 'scope': 'Current selection of isolated native probes; recipe configuration is read-only unless authoring status update was explicitly requested',
              'finished_utc': datetime.now(timezone.utc).isoformat()}
    (ROOT / 'reports/spine_verify.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if report['passed'] else 1

if __name__ == '__main__': raise SystemExit(main())
