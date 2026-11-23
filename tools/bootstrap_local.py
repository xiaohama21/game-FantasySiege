"""Build local research assets from user-owned sources; never download or publish them."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, sys, tempfile, time
from datetime import datetime, timezone
import spine_pipeline
import qa_launch
from run_checks import fatal_lines, joined_output
ROOT = Path(__file__).resolve().parents[1]
IDS = '097,312,314,072,163,084,018,168,253,254,046,285,271,110,023,147,069,057,059,036,094'
IMPORT_TOOLS = ('bootstrap_local.py', 'spine_pipeline.py', 'spine_upgrade_38_to_43.py',
                'run_checks.py', 'qa_launch.py')
AUTHORING_TOOLS = IMPORT_TOOLS + ('tune_visuals.py', 'verify_spine.py', 'generate_portraits.py')


class BootstrapError(RuntimeError):
    def __init__(self, message, exit_code=None):
        super().__init__(message)
        self.exit_code = exit_code


def _output_text(value):
    return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')


def _sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool_dependency_context(project, full_authoring=True):
    """Validate the actual executable dependency closure before any build writes."""
    project = Path(project).absolute()
    required = AUTHORING_TOOLS if full_authoring else IMPORT_TOOLS
    result = {}
    for filename in required:
        path = qa_launch.assert_safe_path(project/'tools'/filename, project, 'tools')
        if not path.is_file():
            raise ValueError('Missing bootstrap tool dependency: tools/' + filename)
        result['tools/' + filename] = _sha(path)
    return result

def _editor_import(godot, phase):
    qa_launch.preflight_project(ROOT, gameplay=False)
    folder = ROOT/'reports'
    folder.mkdir(parents=True,exist_ok=True)
    log = folder/('bootstrap_'+phase+'.log')
    evidence = qa_launch.prepare_launch([str(godot),'--headless','--path',str(ROOT),'--editor','--quit'], ROOT, 'import_' + phase, gameplay=False)
    try:
        run = subprocess.run(evidence.command,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    except subprocess.TimeoutExpired as failure:
        log.write_text(joined_output(failure.stdout,failure.stderr),encoding='utf-8')
        raise BootstrapError('Godot '+phase+' import timed out; see '+str(log)) from failure
    except OSError as failure:
        log.write_text(str(failure),encoding='utf-8')
        raise BootstrapError('Godot '+phase+' could not start; see '+str(log)) from failure
    output = joined_output(run.stdout,run.stderr)
    log.write_text(output,encoding='utf-8')
    startup = qa_launch.validate_evidence(evidence, fatal_lines)
    (folder/('bootstrap_'+phase+'_startup.json')).write_text(json.dumps(startup,ensure_ascii=False,indent=2),encoding='utf-8')
    if run.returncode != 0 or fatal_lines(output) or 'CrashHandler' in output or not startup['passed']:
        raise BootstrapError('Godot '+phase+' import failed; see '+str(log),run.returncode)

def import_runtime_assets(godot):
    """Import PNGs at their final paths before loading native atlas importers."""
    qa_launch.preflight_project(ROOT, gameplay=False)
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

def _fresh_json(path, stage):
    if path.stat().st_mtime_ns + 1_000_000 < stage['started_ns']:
        raise ValueError('stale bootstrap evidence: '+str(path))
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(data,dict): raise ValueError('bootstrap evidence must be an object: '+str(path))
    return data


def _validate_conversion(stage):
    data = _fresh_json(ROOT/'reports/spine_import.json',stage)
    results = data.get('results',[])
    expected = IDS.split(',')
    if not isinstance(results,list) or len(results) != len(expected):
        raise ValueError('conversion must report all 21 requested source IDs')
    actual = [item.get('source_id') for item in results if isinstance(item,dict)]
    if sorted(actual) != sorted(expected) or any(item.get('status') != 'converted' for item in results):
        raise ValueError('conversion has missing, duplicate or rejected source IDs')
    if data.get('passed') is not True:
        raise ValueError('conversion report did not pass')
    return {'source_ids':actual,'converted':len(results)}


def _validate_native(stage, update_status):
    data = _fresh_json(ROOT/'reports/spine_verify.json',stage)
    expected = ['d69_'+number for number in IDS.split(',')]
    results = data.get('results',[])
    if (data.get('passed') is not True or data.get('update_status_requested') is not update_status
            or sorted(data.get('selected_visual_ids',[])) != sorted(expected)
            or not isinstance(results,list) or len(results) != len(expected)
            or sorted(item.get('visual_id','') for item in results) != sorted(expected)
            or any(item.get('passed') is not True for item in results)):
        raise ValueError('native verification must pass all 21 current visual IDs in the requested mode')
    actual_sha = _sha(ROOT/'resources/visuals.json')
    if data.get('config_sha256_after') != actual_sha:
        raise ValueError('native report does not match current visual recipes')
    if not update_status and (data.get('config_unchanged') is not True or data.get('config_write_performed') is not False):
        raise ValueError('frozen native verification changed author recipes')
    if update_status:
        config = json.loads((ROOT/'resources/visuals.json').read_text(encoding='utf-8-sig'))
        if any(config[key].get('status') not in ('runtime_pass','visual_checked','performance_checked') for key in expected):
            raise ValueError('author verification did not establish runtime status for all 21 visuals')
    return {'visual_ids':expected,'passed':True,'visuals_sha256':actual_sha,'update_status':update_status}


def _require_frozen(report):
    if _sha(ROOT/'resources/visuals.json') != report['frozen_visuals_sha256']:
        raise ValueError('frozen visual recipes changed after author verification')


def _validate_portraits(stage, report):
    _require_frozen(report)
    data = _fresh_json(ROOT/'reports/portraits_local.json',stage)
    if data.get('passed') is not True or len(data.get('entries',[])) != 12:
        raise ValueError('portrait verification must pass all twelve playable heroes')
    manifest = json.loads((ROOT/'assets/portraits/manifest.json').read_text(encoding='utf-8-sig'))
    if (data.get('visuals_sha256') != report['frozen_visuals_sha256']
            or manifest.get('passed') is not True or manifest.get('visuals_sha256') != report['frozen_visuals_sha256']):
        raise ValueError('portraits do not use the frozen author recipes')
    return {'portraits':12,'visuals_sha256':report['frozen_visuals_sha256']}


def _snapshot_evidence(report, stage, paths):
    stage['evidence'] = []
    for path in paths:
        entry = {'path':str(path.resolve()),'exists':path.is_file()}
        if path.is_file():
            entry.update({'sha256':_sha(path),'modified_ns':path.stat().st_mtime_ns,
                          'fresh_for_stage':path.stat().st_mtime_ns + 1_000_000 >= stage['started_ns']})
            if path.suffix in ('.json','.log','.err'):
                destination = Path(report['run_directory'])/(stage['name']+'_'+path.name)
                shutil.copy2(path,destination)
                entry['snapshot'] = str(destination)
        stage['evidence'].append(entry)


def _write_report(report):
    content = json.dumps(report,ensure_ascii=False,indent=2)+'\n'
    (Path(report['run_directory'])/'bootstrap_local.json').write_text(content,encoding='utf-8')
    (ROOT/'reports/bootstrap_local.json').write_text(content,encoding='utf-8')


def _stage(report, name, command=None, action=None, validate=None, evidence=()):
    stage = {'name':name,'started_ns':time.time_ns(),'command':command or [],
             'exit_code':None,'passed':False,'error':None}
    report['stages'].append(stage)
    _write_report(report)
    try:
        if command is not None:
            run = subprocess.run(command,cwd=ROOT,capture_output=True,text=True,
                                 encoding='utf-8',errors='replace',check=True)
            stage['exit_code'] = run.returncode
            (Path(report['run_directory'])/(name+'.log')).write_text(
                _output_text(run.stdout)+_output_text(run.stderr),encoding='utf-8')
        else:
            action()
            stage['exit_code'] = 0
        if validate is not None:
            stage['details'] = validate(stage)
        stage['passed'] = True
    except Exception as failure:
        stage['error'] = str(failure)
        if isinstance(failure,subprocess.CalledProcessError):
            stage['exit_code'] = failure.returncode
            (Path(report['run_directory'])/(name+'.log')).write_text(
                _output_text(failure.stdout)+_output_text(failure.stderr),encoding='utf-8')
        elif isinstance(failure,BootstrapError):
            stage['exit_code'] = failure.exit_code
        raise
    finally:
        stage['finished_ns'] = time.time_ns()
        _snapshot_evidence(report,stage,evidence)
        _write_report(report)


def _copy_runtime(donor):
    target = qa_launch.assert_safe_path(ROOT/'bin', ROOT, 'bin')
    windows = qa_launch.assert_safe_path(ROOT/'bin/windows', ROOT, 'bin')
    qa_launch.inspect_existing_tree(target)
    # Validate every destination before the first mkdir or copy, including the
    # root extension file and the three native libraries.
    qa_launch.assert_safe_path(target/'spine_godot_extension.gdextension', ROOT, 'bin')
    for name in ('editor','template_debug','template_release'):
        qa_launch.assert_safe_path(windows/('libspine_godot.windows.'+name+'.x86_64.dll'), ROOT, 'bin')
    windows.mkdir(parents=True,exist_ok=True)
    shutil.copy2(donor/'spine_godot_extension.gdextension',target/'spine_godot_extension.gdextension')
    for name in ('editor','template_debug','template_release'):
        filename='libspine_godot.windows.'+name+'.x86_64.dll'
        shutil.copy2(donor/'windows'/filename,windows/filename)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,help='Read-only D69 315 source package; required unless import-only')
    parser.add_argument('--runtime-from',type=Path,help='Read-only installed spine-godot bin directory, e.g. TowerDefense/bin')
    parser.add_argument('--godot',type=Path,help='Optional Godot console executable: complete native authoring, portraits and read-only verification')
    parser.add_argument('--import-only',action='store_true',help='Only two-phase import of assets already copied into this project/package')
    args = parser.parse_args(argv)
    qa_launch.preflight_project(ROOT, gameplay=False)
    try:
        tool_dependencies = tool_dependency_context(ROOT, not args.import_only)
    except (OSError, ValueError) as failure:
        parser.error(str(failure))
    for name in ('source_root','runtime_from','godot'):
        value = getattr(args,name)
        if value is not None: setattr(args,name,value.resolve())
    if args.import_only:
        if not args.godot: parser.error('--import-only requires --godot')
    else:
        if not args.source_root or not args.source_root.is_dir(): parser.error('source-root directory does not exist')
        if args.runtime_from and not (args.runtime_from/'spine_godot_extension.gdextension').is_file():
            parser.error('runtime-from must contain spine_godot_extension.gdextension')
    run_directory = ROOT/'reports/runtime/bootstrap'/str(time.time_ns())
    run_directory.mkdir(parents=True,exist_ok=False)
    (run_directory/'.gdignore').write_text('',encoding='utf-8')
    report = {'schema':1,'started_utc':datetime.now(timezone.utc).isoformat(),
              'project_root':str(ROOT.resolve()),'source_root':str(args.source_root.resolve()) if args.source_root else None,
              'runtime_from':str(args.runtime_from.resolve()) if args.runtime_from else None,
              'godot':str(args.godot.resolve()) if args.godot else None,'source_ids':IDS.split(','),
              'mode':'import_only' if args.import_only else ('full_authoring' if args.godot else 'conversion_only'),
              'run_directory':str(run_directory.resolve()),'status':'running','ready':False,'passed':False,
              'frozen_visuals_sha256':None,'stages':[],'error':None,
              'tool_dependencies_sha256':tool_dependencies,
              'scope':'Local restricted dependencies only; foreground play and performance are separate acceptance items'}
    _write_report(report)
    command = lambda filename,*options: [sys.executable,str(ROOT/'tools'/filename),*options]
    try:
        if args.import_only:
            _stage(report,'runtime_import',action=lambda: import_runtime_assets(args.godot),
                   evidence=[ROOT/'reports/bootstrap_textures.log',ROOT/'reports/bootstrap_native.log'])
            report['status'] = 'imported'
        else:
            if args.runtime_from:
                runtime_files = [ROOT/'bin/spine_godot_extension.gdextension']+[
                    ROOT/'bin/windows'/('libspine_godot.windows.'+name+'.x86_64.dll')
                    for name in ('editor','template_debug','template_release')]
                _stage(report,'runtime_copy',action=lambda: _copy_runtime(args.runtime_from),evidence=runtime_files)
            _stage(report,'scan',command('spine_pipeline.py','scan','--source-root',str(args.source_root.resolve())),
                   evidence=[ROOT/'reports/spine_catalog.json'])
            _stage(report,'convert',command('spine_pipeline.py','import','--source-root',str(args.source_root.resolve()),'--ids',IDS,'--allow-deform'),
                   validate=_validate_conversion,evidence=[ROOT/'reports/spine_import.json'])
            _stage(report,'tune',command('tune_visuals.py'),evidence=[ROOT/'resources/visuals.json'])
            if args.godot:
                _stage(report,'runtime_import',action=lambda: import_runtime_assets(args.godot),
                       evidence=[ROOT/'reports/bootstrap_textures.log',ROOT/'reports/bootstrap_native.log'])
                _stage(report,'native_author',command('verify_spine.py','--godot',str(args.godot),'--ids',IDS,'--update-status'),
                       validate=lambda stage: _validate_native(stage,True),
                       evidence=[ROOT/'reports/spine_verify.json',ROOT/'resources/visuals.json'])
                report['frozen_visuals_sha256'] = _sha(ROOT/'resources/visuals.json')
                _write_report(report)
                _stage(report,'portraits_generate',command('generate_portraits.py','--godot',str(args.godot)),
                       validate=lambda stage: _validate_portraits(stage,report),
                       evidence=[ROOT/'reports/portraits_local.json',ROOT/'assets/portraits/manifest.json'])
                _stage(report,'portraits_import',action=lambda: _editor_import(args.godot,'portraits'),
                       validate=lambda stage: _require_frozen(report),evidence=[ROOT/'reports/bootstrap_portraits.log'])
                def readonly_native(stage):
                    _require_frozen(report)
                    return _validate_native(stage,False)
                _stage(report,'native_readonly',command('verify_spine.py','--godot',str(args.godot),'--ids',IDS),
                       validate=readonly_native,evidence=[ROOT/'reports/spine_verify.json'])
                _stage(report,'portraits_readonly',command('generate_portraits.py','--check'),
                       validate=lambda stage: _validate_portraits(stage,report),
                       evidence=[ROOT/'reports/portraits_local.json',ROOT/'assets/portraits/manifest.json'])
                report['status'],report['ready'] = 'ready',True
            else:
                report['status'] = 'converted'
        report['passed'] = True
    except Exception as failure:
        report['status'],report['error'] = 'failed',str(failure)
        print('LOCAL_BOOTSTRAP_FAILED: '+str(failure),file=sys.stderr)
    finally:
        report['finished_utc'] = datetime.now(timezone.utc).isoformat()
        _write_report(report)
    if not report['passed']: return 1
    if args.import_only:
        print('LOCAL_IMPORT_READY: texture and native import phases completed')
    elif report['ready']:
        print('LOCAL_ASSETS_READY: all 21 native resources and twelve portraits passed; restricted assets remain local')
    else:
        print('LOCAL_ASSETS_CONVERTED: native runtime and portraits have not been verified; rerun full bootstrap with --godot')
    return 0


if __name__=='__main__': raise SystemExit(main())
