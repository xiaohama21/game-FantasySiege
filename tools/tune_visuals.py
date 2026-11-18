"""Apply tracked composition recipes after reproducible local source import."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]
path = ROOT/'resources/visuals.json'
data = json.loads(path.read_text(encoding='utf-8'))
catalog = json.loads((ROOT/'reports/spine_catalog.json').read_text(encoding='utf-8'))
entries = {entry['source_id']:entry['exports'][0] for entry in catalog['number_entries']}
heights = {'097':130,'312':128,'314':124,'072':124,'163':144,'084':110,'018':116,'168':114,'253':83,'254':89,'046':116,'285':110,'271':168,'110':119,'023':118,'147':119,'069':127,'057':89,'059':115,'036':121,'094':174}
colors = {'253':'807bd8','254':'ce729b','046':'e6a37d','285':'f29c71','271':'ff7652','057':'d9a063','059':'d37657','036':'aa70cc','094':'ff6652'}
stable = {'097':.42,'312':.58,'314':.64,'072':.69}
for key, spec in data.items():
    number = spec['source_id']
    bounds = entries[number]['skeleton_bounds']
    spec['scale'] = stable.get(number, round(heights[number]/max(100,float(bounds['height'] or 240)),3))
    spec['foot'] = round(float(bounds['y'] or 0)*spec['scale'], 2)
    spec['ring'] = colors.get(number, '74d2c8')
    spec['ring_radius'] = 32 if number in ('271','094') else 23
    spec['native_facing'] = 1 if number == '097' else -1
    spec['root_motion_scale'] = .08 if number == '312' else 0.0
    if number in ('084','018','253','254'): spec['skin'] = 'A'
    runtime_json = ROOT/str(spec['data']).replace('res://','').replace('actor-data.tres','actor.spine-json')
    if runtime_json.is_file():
        animations = json.loads(runtime_json.read_text(encoding='utf-8'))['animations']
        spec['root_motion_bones'] = [name for name in spec.get('root_motion_bones',[]) if any('translate' in animation.get('bones',{}).get(name,{}) for animation in animations.values())]
path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8',newline='\n')
print('TUNED',len(data),'visual recipes')
