#!/usr/bin/env python3
"""Read-only D69 inventory and conservative, independent runtime imports.

No source directory is ever opened for writing. Converted != runtime_pass.
"""
from pathlib import Path
import argparse, copy, hashlib, json, re, shutil, sys
from datetime import datetime, timezone
import spine_upgrade_38_to_43 as converter

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = Path('F:/godotProject/D69【spine源文件】【315套Q版卡通角色spine动画】')
OLD = Path('F:/godotProject/TowerDefense')
VERIFIED = {
    '097': ('assets/characters/guan_yu', 'hero_guan_yu_a.spine-json', 'hero_guan_yu_a.atlas'),
    '072': ('assets/battle_visuals/diao_chan', 'diao_chan.spine-json', 'diao_chan.atlas'),
    '312': ('assets/battle_visuals/zhao_yun', 'zhao_yun.spine-json', 'zhao_yun.atlas'),
    '314': ('assets/battle_visuals/zhuge_liang', 'zhuge_liang.spine-json', 'zhuge_liang.atlas'),
}

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8', newline='\n')

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def invalidate_native_imports(runtime_dir):
    """Remove only derived JSON/atlas stale remaps inside this project's actor root.

    A copied .import can point to absent *.spjson/*.spatlas; the native
    skeleton resource then silently has no skeleton although PNG loading works.
    """
    project_root = ROOT.resolve()
    actors_root = (ROOT/'assets/actors').resolve()
    directory = Path(runtime_dir).resolve()
    actors_root.relative_to(project_root)
    if directory.parent != actors_root or not re.fullmatch(r'\d{3}', directory.name):
        raise ValueError('native remap invalidation target is outside assets/actors/NNN')
    targets = [directory/name for name in ('actor.spine-json.import','actor.atlas.import')]
    for target in targets:
        if target.is_symlink():
            raise ValueError('refusing to remove a symlinked native remap')
        target.resolve().relative_to(directory)
    removed = []
    for target in targets:
        if target.exists():
            target.unlink()
            removed.append(target.name)
    return removed

def duration(value):
    if isinstance(value, dict):
        return max([float(value.get('time', 0))] + [duration(v) for v in value.values()])
    if isinstance(value, list): return max([0] + [duration(v) for v in value])
    return 0.0

def skins(data):
    s = data.get('skins', {})
    if isinstance(s, dict): return [(name, attachments) for name, attachments in s.items()]
    return [(s.get('name', 'default'), s.get('attachments', {})) for s in s if isinstance(s, dict)]

def atlas_info(path):
    pages, regions = [], []
    if not path.exists(): return pages, regions
    previous_blank = True
    for raw in path.read_text(encoding='utf-8-sig').splitlines():
        line = raw.strip()
        if not line:
            previous_blank = True
            continue
        if ':' not in line:
            if previous_blank: pages.append(line)
            else: regions.append(line)
        previous_blank = False
    return pages, regions

def inspect_export(path):
    data = read(path)
    atlas = path.with_suffix('.atlas')
    pages, regions = atlas_info(atlas)
    region_set = set(regions)
    counts = {'region': 0, 'mesh': 0, 'weighted_mesh': 0, 'linkedmesh': 0, 'path': 0}
    missing_attachments, attachment_paths = [], []
    for skin, slots in skins(data):
        for slot, attachments in slots.items():
            if not isinstance(attachments, dict): continue
            for name, attachment in attachments.items():
                if not isinstance(attachment, dict): continue
                kind = attachment.get('type', 'region')
                counts[kind] = counts.get(kind, 0) + 1
                if kind in ('mesh', 'skinnedmesh', 'weightedmesh') and len(attachment.get('vertices', [])) != len(attachment.get('uvs', [])):
                    counts['weighted_mesh'] += 1
                if kind in ('region', 'mesh', 'linkedmesh', 'skinnedmesh', 'weightedmesh'):
                    region = attachment.get('path', attachment.get('name', name))
                    attachment_paths.append({'skin': skin, 'slot': slot, 'attachment': name, 'path': region})
                    if region not in region_set and atlas.exists(): missing_attachments.append(region)
    animations = {}
    for name, anim in data.get('animations', {}).items():
        animations[name] = {'duration': round(duration(anim), 6), 'empty': not bool(anim),
                            'events': anim.get('events', []), 'deform': bool(anim.get('deform')),
                            'path': bool(anim.get('paths') or anim.get('path'))}
    features = {'bones': len(data.get('bones', [])), 'slots': len(data.get('slots', [])),
                'attachments': counts, 'path_constraints': len(data.get('path', [])),
                'transform_constraints': len(data.get('transform', [])), 'ik_constraints': len(data.get('ik', [])),
                'deform_animations': [n for n,a in animations.items() if a['deform']],
                'path_animations': [n for n,a in animations.items() if a['path']]}
    missing_files = ([str(atlas)] if not atlas.exists() else []) + [str(atlas.parent / p) for p in pages if not (atlas.parent / p).is_file()]
    risks = []
    if features['deform_animations']: risks.append('deform_conversion_requires_dedicated_validation')
    if features['path_constraints'] or features['path_animations'] or counts['path']: risks.append('path_conversion_unsupported')
    if counts['linkedmesh']: risks.append('linked_mesh_requires_dedicated_validation')
    if counts['weighted_mesh']: risks.append('weighted_mesh_native_runtime_validation_required')
    if missing_files or missing_attachments: risks.append('missing_runtime_dependencies')
    version = str(data.get('skeleton', {}).get('spine', 'unknown'))
    if not version.startswith(('3.8', '4.3')): risks.append('export_version_not_supported_by_converter')
    files = [path] + ([atlas] if atlas.exists() else []) + [atlas.parent / p for p in pages if (atlas.parent / p).is_file()]
    return {'json': str(path), 'sha256': sha(path), 'export_name': path.stem, 'version': version,
            'skeleton_bounds': {k:data.get('skeleton', {}).get(k) for k in ('x','y','width','height')},
            'skins': [name for name,_ in skins(data)], 'animations': animations, 'features': features,
            'atlas': str(atlas), 'texture_pages': pages, 'attachment_paths': attachment_paths,
            'missing_files': missing_files, 'missing_attachment_paths': sorted(set(missing_attachments)),
            'files': [{'path':str(p), 'sha256':sha(p), 'bytes':p.stat().st_size} for p in files], 'risks': risks}

def scan(source):
    entries = []
    for folder in sorted(source.iterdir()):
        match = re.match(r'^(\d{3})', folder.name)
        if not folder.is_dir() or not match or match[1] == '000': continue
        number = match[1]
        entry = {'source_id':number, 'directory':str(folder), 'status':'cataloged', 'exports':[], 'scan_errors':[]}
        for path in sorted(folder.rglob('*.json')):
            try:
                data = read(path)
                if 'bones' in data and 'animations' in data: entry['exports'].append(inspect_export(path))
            except Exception as exc: entry['scan_errors'].append({'path':str(path),'error':str(exc)})
        entry['source_projects'] = [{'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size} for p in folder.rglob('*.spine')]
        notices = list(folder.rglob('*免责声明*.txt'))
        entry['license'] = {'status':'research_only_not_commercially_cleared', 'notices':[]}
        for p in notices:
            raw = p.read_bytes()
            for encoding in ('utf-8-sig','gb18030'):
                try: content = raw.decode(encoding); break
                except UnicodeError: content = raw.decode('utf-8',errors='replace')
            entry['license']['notices'].append({'path':str(p),'sha256':sha(p),'text':content})
        if not notices: entry['license']['status'] = 'notice_missing_permission_unknown'
        entry['inventory'] = {'file_count':sum(1 for p in folder.rglob('*') if p.is_file()), 'has_json_export':bool(entry['exports'])}
        entries.append(entry)
    result = {'schema':1,'generated_utc':datetime.now(timezone.utc).isoformat(),'source_root':str(source),
              'expected_number_count':315,'number_count':len(entries),
              'missing_numbers':[f'{i:03}' for i in range(1,316) if f'{i:03}' not in {e['source_id'] for e in entries}],
              'number_entries':entries, 'status_semantics':{'cataloged':'inventory only','converted':'structure output only','runtime_pass':'explicit isolated native probe passed','visual_checked':'human/render QA separate','performance_checked':'measured separately'}}
    write(ROOT/'reports/spine_catalog.json',result)
    print('CATALOG',len(entries),'numbers',sum(len(e['exports']) for e in entries),'exports')
    return result

def conversion_safe(export, allow_deform=False):
    f = export['features']; a = f['attachments']
    return not ((f['deform_animations'] and not allow_deform) or f['path_constraints'] or f['path_animations'] or a['path'] or a['linkedmesh'] or export['missing_files'] or export['missing_attachment_paths'])

def import_ids(ids, source, allow_deform=False, prefer_previous=False):
    catpath = ROOT/'reports/spine_catalog.json'
    cat = read(catpath) if catpath.exists() else scan(source)
    entries = {e['source_id']:e for e in cat['number_entries']}
    cfgpath = ROOT/'resources/visuals.json'
    config = read(cfgpath) if cfgpath.exists() else {}
    results=[]
    for number in ids:
        number=number.zfill(3)
        try:
            if not re.fullmatch(r'\d{3}',number) or not 1 <= int(number) <= 315:
                raise ValueError('source ID must be a three-digit number from 001 to 315')
            entry=entries[number]; exports=entry['exports']
            if len(exports)!=1: raise ValueError(f'expected one export, got {len(exports)}')
            export=exports[0]; original=read(Path(export['json']))
            use_previous = prefer_previous and number in VERIFIED
            if not use_previous and not conversion_safe(export, allow_deform):
                raise ValueError('conservative importer rejects risks: '+', '.join(export['risks']))
            if not use_previous and not export['version'].startswith(('3.8','4.3')):
                raise ValueError('unsupported source export version '+export['version'])
            dest=ROOT/'assets/actors'/number; archive=ROOT/'assets/source'/('d69_'+number)
            dest.mkdir(parents=True,exist_ok=True); archive.mkdir(parents=True,exist_ok=True)
            input_files=[Path(f['path']) for f in export['files']]
            input_files += [Path(n['path']) for n in entry['license']['notices']]
            input_files += [Path(p['path']) for p in entry['source_projects']]
            hashes={}
            for p in input_files:
                target=archive/p.name
                shutil.copy2(p,target)
                hashes[p.name]={'source_path':str(p),'sha256':sha(target),'bytes':target.stat().st_size}
            method='conservative_38_to_43'
            converter.WARNINGS.clear()
            if use_previous:
                folder, jsonname, atlasname=VERIFIED[number]
                oldfolder=OLD/folder
                # The Guan Yu export filename historically differs from its resource name.
                candidates=list(oldfolder.glob('*.spine-json'))
                oldjson=oldfolder/jsonname
                if not oldjson.exists() and len(candidates)==1: oldjson=candidates[0]
                converted=read(oldjson); atlas_source=oldfolder/atlasname
                if not atlas_source.exists(): atlas_source=next(oldfolder.glob('*.atlas'))
                method='copied_previously_validated_runtime_retested_in_new_project'
                runtime_pages,_=atlas_info(atlas_source)
                for p in runtime_pages: shutil.copy2(oldfolder/p,dest/p)
                shutil.copy2(atlas_source,dest/'actor.atlas')
                runtime_origin={'path':str(oldjson),'sha256':sha(oldjson)}
            else:
                converted=copy.deepcopy(original)
                if export['version'].startswith('3.8'):
                    converter.upgrade(converted)
                    for bone in converted.get('bones',[]):
                        if 'transform' in bone: bone['inherit']=bone.pop('transform')
                shutil.copy2(Path(export['atlas']),dest/'actor.atlas')
                for p in export['texture_pages']: shutil.copy2(Path(export['atlas']).parent/p,dest/p)
                runtime_origin=None
            write(dest/'actor.spine-json',converted)
            native_imports_invalidated=invalidate_native_imports(dest)
            tres=f'''[gd_resource type="SpineSkeletonDataResource" load_steps=3 format=3]
[ext_resource type="SpineAtlasResource" path="res://assets/actors/{number}/actor.atlas" id="1"]
[ext_resource type="SpineSkeletonFileResource" path="res://assets/actors/{number}/actor.spine-json" id="2"]
[resource]
atlas_res = ExtResource("1")
skeleton_file_res = ExtResource("2")
default_mix = 0.08
'''
            (dest/'actor-data.tres').write_text(tres,encoding='utf-8',newline='\n')
            anims=export['animations']; valid={n for n,a in anims.items() if not a['empty'] and a['duration']>0}
            mapping={}
            choices={'idle':['Idle','idle','Stand','stand'],'move':['Move','Walk','Run','move','walk'],'attack':['Attack_A','Attack','attack','Attack_B'],'skill':['Active_A','Critical','Appear'],'hurt':['Stiff','Hurt','Hit','hurt'],'death':['Death','death','UI_Death']}
            for state,names in choices.items(): mapping[state]=next((n for n in names if n in valid),'')
            for state in ('move','attack','skill','hurt'):
                if not mapping[state]: mapping[state]=mapping['idle']
            height=float(export['skeleton_bounds'].get('height') or 240)
            spec={'data':f'res://assets/actors/{number}/actor-data.tres','skin':'default','scale':round(125/max(100,height),3),
                  'foot':8,'native_facing':-1,'animations':mapping,'durations':{s:anims.get(n,{}).get('duration',0) for s,n in mapping.items()},
                  'source_id':number,'export_name':export['export_name'],'root_motion_bones':[b['name'] for b in original.get('bones',[]) if b['name'] in ('root','Root','Character')],
                  'root_motion_scale':0.0,'status':'converted','animation_substitutions':[s for s,n in mapping.items() if s!='idle' and n==mapping['idle']],
                  'license_status':entry['license']['status']}
            scales={'097':.33,'072':.50,'312':.46,'314':.47}
            if number in scales: spec['scale']=scales[number]
            config['d69_'+number]=spec
            provenance={'schema':1,'source_id':number,'status':'converted','method':method,'source_files':hashes,'source_export_version':export['version'],
                        'runtime_source':runtime_origin,'converter_sha256':sha(Path(converter.__file__)),'warnings':list(converter.WARNINGS),'risks':export['risks'],
                        'native_imports_invalidated':native_imports_invalidated,
                        'license':entry['license'],'disclaimer':'Local research and runtime verification only; does not establish commercial rights or release readiness.',
                        'runtime_files':{p.name:sha(p) for p in dest.iterdir() if p.is_file() and p.name!='provenance.json'}}
            write(dest/'provenance.json',provenance)
            results.append({'source_id':number,'status':'converted','method':method})
            print('CONVERTED',number,export['export_name'])
        except Exception as exc:
            results.append({'source_id':number,'status':'import_rejected','error':str(exc)}); print('REJECTED',number,str(exc))
    write(cfgpath,config); write(ROOT/'reports/spine_import.json',{'schema':1,'results':results})

def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('command',choices=['scan','import'])
    parser.add_argument('--source-root',type=Path,default=DEFAULT_SOURCE); parser.add_argument('--ids',default='097,312,314,072,163')
    parser.add_argument('--allow-deform',action='store_true',help='Enable mesh deform format adaptation; requires isolated native verification')
    parser.add_argument('--prefer-previous',action='store_true',help='Optional diagnostic: copy four previous read-only runtime adaptations')
    args=parser.parse_args()
    if args.command=='scan': scan(args.source_root)
    else: import_ids(args.ids.split(','),args.source_root,args.allow_deform,args.prefer_previous)

if __name__=='__main__': main()
