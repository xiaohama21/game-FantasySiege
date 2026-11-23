"""Verify a local Windows learning package with its own engine and fresh reports."""
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
import run_checks
import qa_launch

ROOT = Path(__file__).resolve().parents[1]
BAD_LOG = ('CrashHandler',)
ART_CAPTURE_COUNT = 56
STUDY_ART_CAPTURES = ('art_study_locked', 'art_study_unowned', 'art_study_ready', 'art_study_base',
                      'art_study_sweep', 'art_study_heal', 'art_study_siege', 'art_study_slow',
                      'art_hero_studied', 'art_gallery_studied')
BRIEFING_ART_CAPTURES = tuple('art_briefing_stage_%02d' % index for index in range(1, 9)) + tuple(
    'art_briefing_stage_%02d_lower' % index for index in range(1, 9)) + ('art_briefing_locked', 'art_briefing_studied')
RESULT_ART_CAPTURES = ('art_result_victory', 'art_result_defeat', 'art_result_unsaved', 'art_result_recovered')
SETTINGS_ART_CAPTURES = ('art_settings_save_failed', 'art_settings_temporary_return')
NAVIGATION_ART_CAPTURES = ('art_hero_spirit_beast', 'art_study_siege', 'art_squad', 'art_squad_lower')
STUDY_NOTICE_CAPTURES = ('art_study_sweep', 'art_study_heal', 'art_study_siege', 'art_study_slow')
FONT_ART_HASHES = (('ui_style_sha256', 'scripts/ui/UIStyle.gd'),
                   ('font_manifest_sha256', 'assets/fonts/manifest.json'),
                   ('font_binary_sha256', 'assets/fonts/NotoSansSC.ttf'),
                   ('font_body_sha256', 'resources/ui_font_body.tres'),
                   ('font_emphasis_sha256', 'resources/ui_font_emphasis.tres'))
FONT_ART_REQUIRED_CHARACTERS = '0123456789力量敏捷智力生命伤害护甲魔抗射程召唤冷却星砂训练研修保存敌情首领→×'
FONT_INTERNAL_FAMILIES = {'Noto Sans SC', 'Noto Sans SC Thin'}
FONT_WEIGHT_TAG = '2003265652'  # OpenType wght, as serialized from TextServer's integer tag.


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'), parse_constant=run_checks._invalid_json_number)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def payload_check(package, manifest):
    failures = []
    for entry in manifest['files']:
        path = (package / entry['path']).resolve()
        try:
            path.relative_to(package)
        except ValueError:
            failures.append('manifest path outside package: ' + entry['path'])
            continue
        if not path.is_file() or path.stat().st_size != entry['bytes'] or sha(path) != entry['sha256']:
            failures.append('payload changed: ' + entry['path'])
    return failures


def project_renderer(package):
    source = (package / 'project.godot').read_text(encoding='utf-8-sig')
    match = re.search(r'^renderer/rendering_method="([^"]+)"$', source, re.MULTILINE)
    if match is None or match.group(1) not in ('gl_compatibility', 'mobile', 'forward_plus'):
        raise ValueError('Package has no supported explicit production renderer')
    return match.group(1)


def project_policy(package):
    """Read the exact production policy; test CLI overrides cannot define it."""
    source = (package / 'project.godot').read_text(encoding='utf-8-sig')

    def setting(section, key):
        block = re.search(r'^\[' + re.escape(section) + r'\][ \t]*\r?\n(.*?)(?=^\[|\Z)', source,
                          re.MULTILINE | re.DOTALL)
        match = re.search(r'^' + re.escape(key) + r'=([^\r\n]+)$', block.group(1), re.MULTILINE) if block else None
        if match is None:
            raise ValueError('Missing production setting: ' + section + '/' + key)
        return match.group(1)

    renderer = project_renderer(package)
    if setting('rendering', 'renderer/rendering_method.mobile') != '"' + renderer + '"':
        raise ValueError('Production mobile override differs from desktop renderer')
    feature = {'mobile': 'Mobile', 'gl_compatibility': 'GL Compatibility', 'forward_plus': 'Forward Plus'}[renderer]
    if '"' + feature + '"' not in setting('application', 'config/features'):
        raise ValueError('Production config/features differs from renderer')
    if setting('rendering', 'driver/threads/thread_model') != '1':
        raise ValueError('Production render thread must be Safe')
    managed = setting('fantasy_siege', 'visuals/managed_mesh_redraw')
    groups = setting('fantasy_siege', 'visuals/frame_group_count')
    critical = setting('fantasy_siege', 'visuals/critical_instance_limit')
    if managed not in ('true', 'false') or groups not in ('2', '3', '4') or not re.fullmatch(r'[1-9][0-9]*', critical):
        raise ValueError('Invalid production animation budget settings')
    return {'renderer': renderer, 'render_thread_model': 'safe', 'managed_mesh_redraw': managed == 'true',
            'frame_group_count': int(groups), 'critical_instance_limit': int(critical)}


def portrait_check(package, version):
    failures = []
    for filename in ('camp-route.svg', 'rift-isles.svg', 'brass-remnants.svg', 'lighthouse-camp.svg', 'lighthouse-rift.svg'):
        if not (package / 'assets/environments' / filename).is_file():
            failures.append('Original environment artwork missing: ' + filename)
    try:
        manifest = read_json(package / 'assets/portraits/manifest.json')
        units = read_json(package / 'resources/units.json')
        playable = {key: unit for key, unit in units.items() if unit.get('playable') is True}
        entries = manifest.get('entries', [])
        if manifest.get('passed') is not True or manifest.get('program_version') != version:
            failures.append('Portrait manifest must pass for this program version')
        if manifest.get('visuals_sha256') != sha(package / 'resources/visuals.json'):
            failures.append('Portrait recipes differ from production visuals')
        if len(playable) != 12 or len(entries) != 12 or {item.get('unit_id') for item in entries} != set(playable):
            failures.append('Portrait manifest must cover all twelve playable heroes exactly once')
        for entry in entries:
            unit_id = entry.get('unit_id', '')
            expected_png = unit_id + '.png'
            if unit_id not in playable or entry.get('visual_id') != playable[unit_id].get('visual_id'):
                failures.append('Portrait identity mismatch: ' + str(unit_id))
            if entry.get('png') != expected_png or Path(expected_png).name != expected_png:
                failures.append('Portrait filename outside expected identity: ' + str(unit_id))
                continue
            path = package / 'assets/portraits' / expected_png
            if not path.is_file() or sha(path) != entry.get('sha256'):
                failures.append('Portrait PNG missing or changed: ' + str(unit_id))
            if entry.get('native') is not True or entry.get('nonempty') is not True:
                failures.append('Portrait must contain a real native character: ' + str(unit_id))
            if type(entry.get('width')) is not int or type(entry.get('height')) is not int or min(entry['width'], entry['height']) < 64:
                failures.append('Portrait dimensions are too small: ' + str(unit_id))
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as failure:
        failures.append('Invalid portrait assets: ' + str(failure))
    return failures


def performance_check(detail, count, policy, multiplier=1.0):
    failures = []
    if type(detail.get('window_mode')) is not int or detail.get('window_mode') != 0 or detail.get('window_visible') is not True:
        failures.append('Performance requires a visible normal window')
    for key in ('sample_frames', 'focused_frames', 'hud_visible_frames', 'budget_valid_frames', 'normal_window_frames', 'full_resolution_frames'):
        if type(detail.get(key)) is not int or detail.get(key) != 300:
            failures.append('Performance requires all 300 frames: ' + key)
    if detail.get('actual_rendering_driver') != 'vulkan':
        failures.append('Performance requires the actual Vulkan rendering driver')
    for key in ('total_instances', 'native_instances', 'native_instances_min', 'native_instances_max', 'alive_min', 'alive_max', 'visible_min', 'visible_max'):
        if type(detail.get(key)) is not int or detail.get(key) != count:
            failures.append('Performance population differs: ' + key)
    if detail.get('real_renderer') is not True or not detail.get('rendering_adapter'):
        failures.append('Performance has no real rendering adapter')
    if detail.get('actual_rendering_method') != policy['renderer'] or detail.get('production_renderer') != policy['renderer']:
        failures.append('Performance renderer differs from package production default')
    for key, expected in (('render_thread_model', policy['render_thread_model']),
                          ('production_managed_mesh_redraw', policy['managed_mesh_redraw']),
                          ('production_frame_group_count', policy['frame_group_count']),
                          ('critical_instance_limit', policy['critical_instance_limit'])):
        if type(detail.get(key)) is not type(expected) or detail.get(key) != expected:
            failures.append('Performance production policy differs: ' + key)
    if detail.get('production_policy_override') is not False:
        failures.append('Performance used a production policy override')
    key_count = min(policy['critical_instance_limit'], count)
    low_count = count - key_count
    for key, expected in (('managed_instances_min', count if policy['managed_mesh_redraw'] else 0),
                          ('managed_instances_max', count if policy['managed_mesh_redraw'] else 0),
                          ('key_instances_60hz_min', key_count), ('key_instances_60hz_max', key_count),
                          ('low_priority_instances_min', low_count), ('low_priority_instances_max', low_count)):
        if type(detail.get(key)) is not int or detail.get(key) != expected:
            failures.append('Performance per-frame animation budget differs: ' + key)
    expected_groups = {str(group): low_count if group == policy['frame_group_count'] else 0 for group in (2, 3, 4)}
    for key in ('low_priority_frame_groups', 'frame_group_counts_min', 'frame_group_counts_max'):
        if detail.get(key) != expected_groups or not all(type(value) is int for value in detail.get(key, {}).values()):
            failures.append('Performance low-priority frame groups differ: ' + key)
    if detail.get('playback_multiplier') != multiplier:
        failures.append('Performance playback multiplier differs from requested scope')
    if detail.get('viewport_size') != '(1280, 720)' or detail.get('display_window_size') != '(1280, 720)':
        failures.append('Performance requires the full 1280x720 production viewport and window')
    if type(detail.get('maximum_live_floating_numbers')) is not int or detail['maximum_live_floating_numbers'] <= 0:
        failures.append('Performance has no actual combat floating numbers')
    p95 = detail.get('p95_frame_ms')
    fps = detail.get('fps_average')
    if type(p95) not in (int, float) or not 0 < p95 < 33.334:
        failures.append('Performance frame-time gate failed')
    if count == 24 and (type(fps) not in (int, float) or not math.isfinite(fps) or fps < 55):
        failures.append('Normal 24-unit FPS gate failed')
    return failures


def playback_check(detail, package, policy, production):
    failures = []
    visual_ids = set(read_json(package / 'resources/visuals.json'))
    if len(visual_ids) != 21 or detail.get('native_visuals') != 21 or set(detail.get('native_visual_ids', [])) != visual_ids or len(detail.get('native_visual_ids', [])) != 21:
        failures.append('Playback must cover all 21 production visual IDs exactly once')
    if detail.get('actual_rendering_method') != policy['renderer'] or detail.get('real_renderer') is not True or detail.get('render_thread_model') != policy['render_thread_model']:
        failures.append('Playback renderer differs from production renderer')
    expected_managed = policy['managed_mesh_redraw'] if production else False
    if detail.get('managed_mesh_redraw') is not expected_managed:
        failures.append('Playback mesh policy differs from requested scope')
    if detail.get('playback_policy') != ('production' if production else 'unmanaged_control'):
        failures.append('Playback production/control identity is missing')
    if detail.get('production_managed_mesh_redraw') is not policy['managed_mesh_redraw'] or (production and detail.get('production_policy_override') is not False):
        failures.append('Playback did not preserve the production mesh policy')
    for key, expected in (('tested_speeds', [0, 1, 2]), ('tested_sample_rates', [30, 60]), ('tested_frame_groups', [2, 3, 4])):
        if detail.get(key) != expected:
            failures.append('Playback coverage missing: ' + key)
    if detail.get('group_switch_keeps_pending_delta') is not True or detail.get('reconfigure_and_free') is not True:
        failures.append('Playback lifecycle regression missing')
    return failures


def mesh_redraw_check(detail, package, policy):
    failures = []
    visuals = read_json(package / 'resources/visuals.json')
    models = detail.get('models', [])
    if len(visuals) != 21 or detail.get('resource_count') != 21 or detail.get('raw_animation_count') != 220:
        failures.append('Mesh comparison must cover 21 resources and 220 raw animations')
    if detail.get('actual_rendering_method') != policy['renderer'] or not detail.get('rendering_adapter') or detail.get('real_renderer') is not True or detail.get('render_thread_model') != policy['render_thread_model']:
        failures.append('Mesh comparison must use a real production renderer')
    if detail.get('max_pixel_difference') != 0 or type(detail.get('max_pixel_difference')) is not int:
        failures.append('Mesh RGBA comparison contains differences')
    if len(models) != len(visuals) or {model.get('id') for model in models} != set(visuals):
        failures.append('Mesh comparison resource identities are incomplete or duplicated')
    expected_total = 4  # Reconfigure/disable/re-enable/pause comparisons.
    action_total = 0
    for model in models:
        visual_id = model.get('id')
        if visual_id not in visuals:
            continue
        relative = visuals[visual_id]['data'].removeprefix('res://').replace('actor-data.tres', 'actor.spine-json')
        path = (package / relative).resolve()
        path.relative_to(package)
        raw = read_json(path)
        names = set(raw['animations'])
        skins = {skin['name'] for skin in raw['skins']}
        expected = len(names) * len(skins) * 2 * 5
        expected_total += expected
        action_total += len(names)
        reported_names = model.get('raw_action_names', [])
        if model.get('raw_actions') != len(names) or set(reported_names) != names or len(reported_names) != len(names):
            failures.append('Mesh raw animation coverage differs: ' + str(visual_id))
        if set(model.get('skins', [])) != skins or len(model.get('skins', [])) != len(skins):
            failures.append('Mesh skin coverage differs: ' + str(visual_id))
        if model.get('comparisons') != expected:
            failures.append('Mesh per-resource comparison coverage differs: ' + str(visual_id))
    if action_total != 220 or detail.get('comparisons') != expected_total:
        failures.append('Mesh total comparison coverage differs from production assets')
    return failures


def native_check(detail, package):
    failures = []
    visuals = read_json(package / 'resources/visuals.json')
    config_sha = sha(package / 'resources/visuals.json')
    if detail.get('config_unchanged') is not True or detail.get('update_status_requested') is not False or detail.get('config_write_performed') is not False:
        failures.append('Native package verification must leave source recipes unchanged')
    if detail.get('config_sha256_before') != config_sha or detail.get('config_sha256_after') != config_sha:
        failures.append('Native recipe SHA differs from this package configuration')
    results = detail.get('results', [])
    selected = detail.get('selected_visual_ids', [])
    if len(selected) != 21 or set(selected) != set(visuals):
        failures.append('Native verification must select all 21 current production resources')
    if len(visuals) != 21 or len(results) != 21 or {item.get('visual_id') for item in results} != set(visuals):
        failures.append('Native verification must cover all 21 production resources exactly once')
    total = 0
    for item in results:
        failures.extend(qa_launch.audit_record(item.get("qa_startup", {}), package, run_checks.fatal_lines))
        visual_id = item.get('visual_id')
        if visual_id not in visuals:
            continue
        relative = visuals[visual_id]['data'].removeprefix('res://').replace('actor-data.tres', 'actor.spine-json')
        path = (package / relative).resolve()
        path.relative_to(package)
        expected = len(read_json(path)['animations'])
        total += expected
        if item.get('passed') is not True or type(item.get('animation_count')) is not int or item['animation_count'] != expected:
            failures.append('Native raw animation coverage failed: ' + str(visual_id))
    if total != 220:
        failures.append('Native verification must cover all 220 production raw animations')
    return failures


def font_art_check(detail, package):
    """Bind rendered font observations to this package's actual font and variants."""
    failures = []
    for key, relative in FONT_ART_HASHES:
        path = package / relative
        if not path.is_file() or detail.get(key) != sha(path):
            failures.append('Offscreen font art SHA differs from this package: ' + key)
    for key, expected in (('ui_font_family', 'Noto Sans SC'), ('body_weight', 400), ('emphasis_weight', 600),
                          ('font_glyph_check', True)):
        if type(detail.get(key)) is not type(expected) or detail.get(key) != expected:
            failures.append('Offscreen font art identity or glyph result differs: ' + key)
    characters = detail.get('font_glyph_characters')
    if type(characters) is not str or not set(FONT_ART_REQUIRED_CHARACTERS).issubset(characters):
        failures.append('Offscreen font glyph coverage must include actual Chinese rules, digits and symbols')
    if detail.get('font_glyph_missing') != [] or type(detail.get('font_glyph_missing')) is not list:
        failures.append('Offscreen font art must have no missing glyphs')
    variants = detail.get('font_glyph_variants')
    if variants != [400, 600] or any(type(value) is not int for value in variants or []):
        failures.append('Offscreen font glyph coverage must include both actual weight variants')
    engine_weights = detail.get('font_engine_weights')
    coordinates = detail.get('font_engine_coordinates')
    if not isinstance(engine_weights, dict) or set(engine_weights) != {'body', 'emphasis'}:
        failures.append('Offscreen font art must record actual TextServer weight observations')
    if not isinstance(coordinates, dict) or set(coordinates) != {'body', 'emphasis'}:
        failures.append('Offscreen font art must record actual TextServer coordinates for every font RID')
    for kind, expected in (('body', 400), ('emphasis', 600)):
        observed = engine_weights.get(kind) if isinstance(engine_weights, dict) else None
        if type(observed) not in (int, float) or not math.isfinite(observed) or observed != expected:
            failures.append('Offscreen font actual TextServer weight differs: ' + kind)
        records = coordinates.get(kind) if isinstance(coordinates, dict) else None
        if not isinstance(records, list) or not records:
            failures.append('Offscreen font TextServer coordinate coverage missing: ' + kind)
            continue
        for record in records:
            value = record.get(FONT_WEIGHT_TAG) if isinstance(record, dict) else None
            if type(value) not in (int, float) or not math.isfinite(value) or value != expected:
                failures.append('Offscreen font RID uses a missing or incorrect actual wght coordinate: ' + kind)
    try:
        manifest = read_json(package / 'assets/fonts/manifest.json')
        active = manifest['active']
        if manifest.get('schema') != 1 or not isinstance(active, dict):
            raise ValueError('font manifest must declare schema1 and active font')
        for key, expected in (('family', 'Noto Sans SC'), ('file', 'NotoSansSC.ttf'),
                              ('license', 'OFL.txt'), ('body_weight', 400), ('emphasis_weight', 600)):
            if type(active.get(key)) is not type(expected) or active.get(key) != expected:
                failures.append('Current font manifest identity differs: ' + key)
        if active.get('sha256') != sha(package / 'assets/fonts/NotoSansSC.ttf'):
            failures.append('Current font manifest SHA differs from actual font bytes')
        license_path = package / 'assets/fonts/OFL.txt'
        if active.get('license_sha256') != sha(license_path) or 'SIL OPEN FONT LICENSE Version 1.1' not in license_path.read_text(encoding='utf-8-sig'):
            failures.append('Current font OFL license is missing or changed')
        aliases = active.get('engine_family_aliases')
        if (not isinstance(aliases, list) or not aliases or any(type(name) is not str for name in aliases)
                or not set(aliases).issubset(FONT_INTERNAL_FAMILIES)):
            failures.append('Current font manifest has unverified internal family aliases')
        else:
            engine = detail.get('font_engine_families')
            if (not isinstance(engine, dict) or set(engine) != {'body', 'emphasis'}
                    or any(type(engine.get(kind)) is not str or engine[kind] not in aliases for kind in ('body', 'emphasis'))):
                failures.append('Offscreen font engine families differ from verified source metadata')
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as failure:
        failures.append('Current font manifest or dependency invalid: ' + str(failure))
    return failures


def navigation_art_check(detail, package):
    """Check observed controls and viewport geometry, not an aggregate PASS flag."""
    failures = []
    captures = detail.get('captures', [])
    if not isinstance(captures, list): return ['Navigation art capture metadata invalid']
    by_name = {item['name']: item for item in captures if isinstance(item, dict) and type(item.get('name')) is str}
    try:
        units = read_json(package / 'resources/units.json')
        playable = {key for key, unit in units.items() if unit.get('playable') is True}
        if len(playable) != 12: raise ValueError('twelve playable identities required')
    except (OSError, ValueError, AttributeError, TypeError) as error:
        return ['Navigation art playable identities invalid: ' + str(error)]

    def rectangle(value):
        return (isinstance(value, list) and len(value) == 4 and
                all(type(number) in (int, float) and math.isfinite(number) for number in value) and
                value[2] > 0 and value[3] > 0)

    def inside_viewport(value):
        return rectangle(value) and value[0] >= 0 and value[1] >= 0 and value[0]+value[2] <= 1281 and value[1]+value[3] <= 721

    for name in STUDY_NOTICE_CAPTURES:
        notice = by_name.get(name, {}).get('study_notice', {})
        if not isinstance(notice, dict):
            failures.append('Study notice actual footer/notification metadata missing: ' + name)
            continue
        footer_text = notice.get('footer_text', '')
        if (notice.get('footer_name') != 'StudyFooterRule' or notice.get('footer_visible') is not True
                or type(footer_text) is not str or '基础八关' not in footer_text or '收益' not in footer_text or '代价' not in footer_text):
            failures.append('Study notice necessary footer rule must remain visible: ' + name)
        footer, toast = notice.get('footer_rect'), notice.get('toast_rect')
        if (not inside_viewport(footer) or not inside_viewport(toast) or notice.get('toast_visible') is not True
                or type(notice.get('toast_text')) is not str or '已保存' not in notice.get('toast_text', '')
                or notice.get('intersects') is not False):
            failures.append('Study notice saved message must be visible and contained without overlap: ' + name)
        if rectangle(footer) and rectangle(toast) and not (
                footer[0]+footer[2] <= toast[0] or toast[0]+toast[2] <= footer[0]
                or footer[1]+footer[3] <= toast[1] or toast[1]+toast[3] <= footer[1]):
            failures.append('Study notice actual rectangles cover the necessary footer rule: ' + name)

    required = {'art_hero_spirit_beast': ('英魂', 'spirit_beast'),
                'art_study_siege': ('研修', 'rivet_gunner'),
                'art_squad': ('编队', None), 'art_squad_lower': ('编队', None)}
    prefixes = {'英魂': 'HeroList', '研修': 'StudyList', '编队': 'SquadList'}
    for name, (page, selected) in required.items():
        capture = by_name.get(name, {})
        navigation = capture.get('navigation', {})
        if not isinstance(navigation, dict):
            failures.append('Navigation art observed controls missing: ' + name)
            continue
        if (navigation.get('page') != page or navigation.get('scroll_name') != prefixes[page] + 'Scroll'
                or navigation.get('grid_name') != prefixes[page] + 'Grid' or navigation.get('restore_ready') is not True
                or type(navigation.get('scroll_vertical')) is not int or navigation['scroll_vertical'] < 0):
            failures.append('Navigation art current list identity/restoration differs: ' + name)
        view = navigation.get('view_rect')
        if not rectangle(view) or view[0] < 0 or view[1] < 0 or view[0] + view[2] > 1281 or view[1] + view[3] > 721:
            failures.append('Navigation art actual list viewport invalid: ' + name)
        if selected is not None:
            card = navigation.get('selected_rect')
            if (navigation.get('selected_id') != selected or navigation.get('selected_card') != 'HeroCard_' + selected
                    or navigation.get('selected_visible') is not True or navigation.get('selected_metadata') is not True):
                failures.append('Navigation art actual selected card differs: ' + name)
            if not rectangle(card) or not rectangle(view) or not (
                    view[0] - 1 <= card[0] and view[1] - 1 <= card[1]
                    and card[0] + card[2] <= view[0] + view[2] + 1 and card[1] + card[3] <= view[1] + view[3] + 1):
                failures.append('Navigation art selected card is outside actual viewport: ' + name)
        else:
            roster = navigation.get('saved_roster')
            cards = navigation.get('cards')
            if (not isinstance(roster, list) or not 1 <= len(roster) <= 8 or any(type(key) is not str for key in roster)
                    or len(set(roster)) != len(roster) or not set(roster).issubset(playable)):
                failures.append('Navigation art saved roster invalid: ' + name)
                continue
            if (not isinstance(cards, list) or len(cards) != 12 or any(not isinstance(card, dict) or type(card.get('unit_id')) is not str for card in cards)
                    or {card.get('unit_id') for card in cards} != playable):
                failures.append('Navigation art all twelve squad cards must be observed: ' + name)
                continue
            for card in cards:
                key = card['unit_id']
                slot = roster.index(key) + 1 if key in roster else 0
                if (card.get('card_name') != 'HeroCard_' + key or card.get('button_name') != 'RosterToggle_' + key
                        or type(card.get('slot')) is not int or card['slot'] != slot
                        or type(card.get('button_slot')) is not int or card['button_slot'] != slot
                        or (slot > 0 and card.get('button_text') != '%d号位 · 移出' % slot)):
                    failures.append('Navigation art actual saved summon slot differs: ' + name + '/' + key)

    settings = detail.get('settings_navigation')
    if not isinstance(settings, dict): return failures + ['Settings art observed failure/return state missing']
    failed = settings.get('failed', {})
    returned = settings.get('returned', {})
    if not isinstance(failed, dict) or not isinstance(returned, dict):
        return failures + ['Settings art observed failure/return state invalid']
    if (failed.get('capture') != SETTINGS_ART_CAPTURES[0] or failed.get('control_names') != ['SaveAndReturn', 'LeaveWithoutSave', 'UnsavedConsequence']
            or failed.get('button_text') != '暂不保存并返回' or type(failed.get('consequence_text')) is not str
            or '尚未保存' not in failed.get('consequence_text', '') or '若之后仍未保存' not in failed.get('consequence_text', '')):
        failures.append('Settings art must show named controls and visible conditional unsaved consequences')
    for key in ('modal_active', 'save_failed', 'consequence_visible', 'runtime_preview_retained', 'dirty_retained', 'paused'):
        if failed.get(key) is not True: failures.append('Settings art failed modal observation missing: ' + key)
    if returned.get('capture') != SETTINGS_ART_CAPTURES[1]: failures.append('Settings art temporary-return capture missing')
    for key in ('modal_closed', 'pause_restored', 'battle_snapshot_unchanged', 'runtime_preview_retained', 'dirty_retained', 'cold_reloaded_previous_settings'):
        if returned.get(key) is not True: failures.append('Settings art temporary-return observation missing: ' + key)
    for state, keys in [(failed, ('preferences_before_sha256', 'preferences_after_sha256')),
                        (returned, ('preferences_before_sha256', 'preferences_after_sha256')),
                        (returned, ('profile_before_sha256', 'profile_after_sha256'))]:
        before, after = (state.get(key) for key in keys)
        if type(before) is not str or re.fullmatch('[0-9a-f]{64}', before) is None or before != after:
            failures.append('Settings art temporary return changed saved bytes: ' + '/'.join(keys))
    if failed.get('preferences_before_sha256') != returned.get('preferences_before_sha256'):
        failures.append('Settings art failure and temporary return use different saved settings')
    return failures


def offscreen_check(detail, name, package):
    failures = qa_launch.background_host_check(detail.get('background_host_setup'), package)
    if type(detail.get('root_window_mode')) is not int or detail.get('root_window_mode') != 1:
        failures.append('Offscreen verification requires a minimized host window')
    if not isinstance(detail.get('background_first_invalid_sample'), dict) or detail['background_first_invalid_sample']:
        failures.append('Offscreen verification has a missing or invalid first-window sample')
    if type(detail.get('background_window_frame_samples')) is not int or detail['background_window_frame_samples'] <= 0:
        failures.append('Offscreen verification must monitor actual engine frames')
    if detail.get('display_window_mode') != 1:
        failures.append('Offscreen verification requires a minimized DisplayServer window')
    if name == 'art_review':
        failures.extend(font_art_check(detail, package))
        failures.extend(navigation_art_check(detail, package))
        captures = detail.get('captures', [])
        if not isinstance(captures, list) or any(not isinstance(item, dict) or type(item.get('name')) is not str for item in captures):
            return failures + ['Offscreen art capture metadata invalid']
        names = {item.get('name') for item in captures}
        if type(detail.get('screenshots')) is not int or detail.get('screenshots') != ART_CAPTURE_COUNT or len(captures) != ART_CAPTURE_COUNT or len(names) != ART_CAPTURE_COUNT:
            failures.append('Offscreen art must contain all ' + str(ART_CAPTURE_COUNT) + ' independent captures')
        if detail.get('background_capture_attempts') != ART_CAPTURE_COUNT or detail.get('background_host_valid_captures') != ART_CAPTURE_COUNT:
            failures.append('Offscreen art must keep all actual captures minimized')
        if not set(STUDY_ART_CAPTURES).issubset(names):
            failures.append('Offscreen art must include all ten study-state and studied-hero captures')
        if not set(BRIEFING_ART_CAPTURES).issubset(names):
            failures.append('Offscreen art must include all eighteen battle-briefing captures')
        if not set(RESULT_ART_CAPTURES).issubset(names):
            failures.append('Offscreen art must include all four result-report captures')
        if not set(SETTINGS_ART_CAPTURES).issubset(names):
            failures.append('Offscreen art must include both failed-settings and temporary-return captures')
        if not set(NAVIGATION_ART_CAPTURES).issubset(names):
            failures.append('Offscreen art must include selected lower-list and actual squad-slot captures')
        if detail.get('studies_sha256') != sha(package / 'resources/studies.json'):
            failures.append('Offscreen study art recipe SHA differs from this package')
        for key, relative in (('briefings_sha256', 'resources/briefings.json'), ('briefing_script_sha256', 'scripts/core/BattleBriefing.gd')):
            if detail.get(key) != sha(package / relative):
                failures.append('Offscreen briefing art SHA differs from this package: ' + key)
        for key, relative in (('main_sha256', 'scripts/ui/Main.gd'), ('stat_badge_sha256', 'scripts/ui/StatBadge.gd'),
                              ('battle_script_sha256', 'scripts/combat/SiegeBattle.gd'), ('settings_panel_sha256', 'scripts/ui/SettingsPanel.gd')):
            if detail.get(key) != sha(package / relative):
                failures.append('Offscreen UI art SHA differs from this package: ' + key)
        if detail.get('portrait_count') != 12 or detail.get('text_overflows') or detail.get('audio_shutdown_clean') is not True:
            failures.append('Offscreen art portrait/text/audio gates failed')
        for capture in captures:
            if capture.get('background_host_valid') is not True or capture.get('root_window_mode') != 1 or capture.get('display_window_mode') != 1:
                failures.append('Offscreen art capture host was invalid: ' + str(capture.get('name')))
            relative = str(capture.get('path', '')).removeprefix('res://')
            path = (package / relative).resolve()
            path.relative_to(package)
            size = capture.get('size')
            if size != [1280, 720] or any(type(value) is not int for value in size) or not path.is_file() or sha(path) != capture.get('sha256'):
                failures.append('Offscreen art image missing or changed: ' + str(capture.get('name')))
            try:
                if run_checks.png_dimensions(path) != (1280, 720):
                    failures.append('Offscreen art actual PNG size differs: ' + str(capture.get('name')))
            except (OSError, ValueError) as error:
                failures.append('Offscreen art PNG invalid: ' + str(capture.get('name')) + '/' + str(error))
        return failures
    if detail.get('background') is not True or detail.get('performance_measured') is not False:
        failures.append('Offscreen Spine report must explicitly exclude performance measurement')
    if type(detail.get('display_window_mode')) is not int or detail.get('display_window_mode') != 1 or detail.get('actual_rendering_driver') != 'vulkan':
        failures.append('Offscreen Spine verification requires a minimized real Vulkan host')
    if name in ('playback', 'playback_unmanaged'):
        if detail.get('background_host_valid_resources') != 21:
            failures.append('Offscreen playback host must stay minimized for all 21 resources')
    if name == 'mesh_redraw':
        if detail.get('comparisons') != 2624 or detail.get('background_host_valid_captures') != 2624:
            failures.append('Offscreen mesh host must stay minimized for all 2624 comparisons')
        viewports = detail.get('viewports', [])
        if len(viewports) != 2 or any(item.get('size') != [1000, 760] or item.get('transparent_bg') is not True or item.get('disable_3d') is not True for item in viewports):
            failures.append('Offscreen mesh requires two full transparent 2D viewports')
    return failures


def background_host_smoke_check(detail, package):
    failures = qa_launch.background_host_check(detail.get('background_host_setup'), package)
    if not isinstance(detail.get('failures'), list) or detail['failures']:
        failures.append('Background host smoke reported errors')
    if detail.get('foreground_verified') is not False or detail.get('performance_measured') is not False:
        failures.append('Background host smoke must exclude foreground and performance validation')
    if type(detail.get('checks')) is not int or detail['checks'] <= 0:
        failures.append('Background host smoke requires a positive integer check count')
    trace = detail.get('legacy_initialize_trace')
    state = detail.get('legacy_run_start_state')
    if not isinstance(trace, list) or len(trace) != 2 or any(not isinstance(item, dict) for item in trace) or not isinstance(state, dict):
        failures.append('Background host smoke legacy timing comparison missing')
    else:
        for item in trace + [state]:
            if any(type(item.get(key)) is not int for key in ('ticks_usec', 'window_mode', 'display_window_mode')):
                failures.append('Background host smoke legacy mode/time missing')
        reset = state.get('window_mode') != 1 or state.get('display_window_mode') != 1
        if type(detail.get('legacy_early_request_reset')) is not bool or detail['legacy_early_request_reset'] != reset:
            failures.append('Background host smoke legacy reset conclusion differs')
        if [item.get('stage') for item in trace] != ['legacy_initialize_before', 'legacy_initialize_after'] or state.get('stage') != 'legacy_run_start':
            failures.append('Background host smoke legacy stage identity differs')
    if detail.get('legacy_request_count') != 1 or detail.get('production_request_count') != 1:
        failures.append('Background host smoke request scopes differ')
    if not isinstance(detail.get('background_first_invalid_sample'), dict) or detail['background_first_invalid_sample']:
        failures.append('Background host smoke monitored an invalid window sample')
    frames = detail.get('monitored_frames')
    if not isinstance(frames, list) or len(frames) < 2 or any(not isinstance(item, dict) for item in frames):
        failures.append('Background host smoke must monitor two actual frames')
    else:
        setup = detail.get('background_host_setup')
        monitor = setup.get('monitor_start_ticks_usec') if isinstance(setup, dict) else None
        for index, sample in enumerate(frames):
            if sample.get('stage') != 'monitored_frame' or type(sample.get('sample')) is not int or sample['sample'] != index + 1 or sample.get('root_ready') is not True:
                failures.append('Background host smoke frame identity/readiness differs')
            if type(sample.get('window_mode')) is not int or sample['window_mode'] != 1 or type(sample.get('display_window_mode')) is not int or sample['display_window_mode'] != 1:
                failures.append('Background host smoke frame was not minimized')
            if type(sample.get('ticks_usec')) is not int or type(monitor) is not int or sample['ticks_usec'] < monitor:
                failures.append('Background host smoke monitored before initialization')
    if type(detail.get('root_window_mode')) is not int or detail['root_window_mode'] != 1 or type(detail.get('display_window_mode')) is not int or detail['display_window_mode'] != 1 or detail.get('actual_rendering_driver') != 'vulkan' or type(detail.get('rendering_adapter')) is not str or not detail['rendering_adapter'] or type(detail.get('display_server')) is not str or detail['display_server'] == 'headless':
        failures.append('Background host smoke requires a minimized native Vulkan host')
    document = (package / 'docs/GAME_DESIGN.md').read_text(encoding='utf-8-sig')
    header = re.search(r'^> 文档 v([^\s]+)\s+·', document, re.MULTILINE)
    if header is None or detail.get('gdd_version') != header.group(1) or detail.get('gdd_sha256') != sha(package / 'docs/GAME_DESIGN.md'):
        failures.append('Background host smoke GDD differs from this package')
    if detail.get('fixture_sha256') != sha(package / 'tests/BackgroundHostSmoke.gd'):
        failures.append('Background host smoke fixture SHA differs')
    return failures


def suite_check(detail, package, suite, version):
    failures = []
    expected_names = set(run_checks.CPU_CASES if suite == 'logic' else run_checks.CASES)
    cases = detail.get('cases', [])
    if detail.get('state') != 'complete' or detail.get('suite') != suite or len(cases) != len(expected_names) or {item.get('case') for item in cases} != expected_names or not all(item.get('passed') is True for item in cases):
        failures.append('checks must be the completed ' + str(len(expected_names)) + '-case ' + suite + ' suite')
    for name in expected_names:
        record = next((item for item in cases if item.get("case") == name), {})
        failures.extend(qa_launch.audit_record(record.get("qa_startup", {}), package, run_checks.fatal_lines))
        case = run_checks.CASES[name]
        if name == 'CampaignJourney':
            path = package / 'reports' / case.report_file
            if not path.is_file():
                failures.append('CampaignJourney structured report missing')
            else:
                report = read_json(path)
                if record.get('report_sha256') != sha(path):
                    failures.append('CampaignJourney structured report SHA differs')
                if report.get('passed') is not True or report.get('failures') or report.get('phase') != 'complete' or report.get('program_version') != version or type(report.get('checks')) is not int or report['checks'] <= 0:
                    failures.append('CampaignJourney structured report failed')
                failures.extend(qa_launch.audit_record(report.get('restart', {}).get('qa_startup', {}), package, run_checks.fatal_lines))
            continue
        if name == 'MainFlow':
            record = next((item for item in cases if item.get('case') == name), None)
            path = package / 'reports' / case.report_file
            if record is None or not path.is_file():
                failures.append('MainFlow structured report missing')
            else:
                report = read_json(path)
                if record.get('report_sha256') != sha(path):
                    failures.append('MainFlow structured report SHA differs')
                failures.extend(main_flow_check(report, package))
            continue
        if not case.report_hashes and not case.script_hashes and not case.required_report_values:
            continue
        record = next((item for item in cases if item.get('case') == name), None)
        if record is None:
            failures.append('study case missing: ' + name)
            continue
        expected = run_checks.case_artifact_context(case, package)
        if record.get('artifact_sha256') != expected:
            failures.append('study runner input SHA differs: ' + name)
        path = package / 'reports' / case.report_file
        if not path.is_file():
            failures.append('study structured report missing: ' + name)
            continue
        report = read_json(path)
        if record.get('report_sha256') != sha(path):
            failures.append('study structured report SHA differs: ' + name)
        if report.get('passed') is not True or report.get('failures') or report.get('program_version') != version or type(report.get('checks')) is not int or report['checks'] <= 0:
            failures.append('study structured report failed: ' + name)
        if case.final_phase and report.get('phase') != case.final_phase:
            failures.append('study final phase missing: ' + name)
        for key, digest in expected.items():
            if report.get(key) != digest:
                failures.append('study report input SHA differs: ' + name + '/' + key)
        for key, value in case.required_report_values:
            if type(report.get(key)) is not type(value) or report.get(key) != value:
                failures.append('study structured report required value differs: ' + name + '/' + key)
    return failures


def main_flow_check(detail, package):
    return run_checks.main_flow_check(detail, package)


def qa_startup_check(detail, package):
    failures = []
    expected = {"normal", "future", "invalid_outside", "invalid_duplicate", "invalid_missing_root",
                "invalid_relative", "invalid_missing_report", "invalid_outside_report"}
    cases = detail.get("cases", [])
    if len(cases) != len(expected) or {case.get("case") for case in cases} != expected:
        failures.append("First-autoload verification must cover all eight fresh-process modes")
    if detail.get("real_user_unchanged") is not True or detail.get("real_player_sentinels_created") is not False or detail.get("real_user_before") != detail.get("real_user_after"):
        failures.append("First-autoload verification must preserve actual existing user files")
    actual_scripts = {relative: sha(package / relative) for relative in qa_launch.SCRIPT_PATHS}
    for item in cases:
        mode = item.get("case")
        try:
            if item.get("passed") is not True or item.get("errors"):
                failures.append("First-autoload fresh process failed: " + str(mode))
            fixture = qa_launch.assert_safe_path(Path(item["fixture_report"]), package, "reports")
            if sha(fixture) != item.get("fixture_report_sha256"):
                failures.append("First-autoload fixture SHA differs: " + str(mode))
            report = read_json(fixture)
            context = report.get("qa_startup", {})
            expected_mode = "future" if mode == "future" else ("invalid" if str(mode).startswith("invalid_") else "normal")
            if report.get("passed") is not True or report.get("failures") or report.get("expected") != expected_mode or context.get("script_sha256") != actual_scripts:
                failures.append("First-autoload fixture/context differs: " + str(mode))
            first = context.get("first_loads", {})
            if mode == "normal":
                prefs = first.get("preferences", {}).get("summary", {})
                profile = first.get("profile", {}).get("summary", {})
                if prefs.get("values", {}).get("master_volume") != 0.23 or prefs.get("values", {}).get("fullscreen") is not True or profile.get("credits") != 731 or profile.get("levels", {}).get("guanyu") != 7:
                    failures.append("First-autoload did not read seeded values immediately")
            elif mode == "future":
                if any(first.get(owner, {}).get("blocked") is not True for owner in ("preferences", "profile")):
                    failures.append("First-autoload future saves were not protected")
            stdout = qa_launch.assert_safe_path(Path(item["stdout_stderr"]), package, "reports")
            if sha(stdout) != item.get("stdout_stderr_sha256") or run_checks.fatal_lines(stdout.read_text(encoding="utf-8", errors="replace")):
                failures.append("First-autoload stdout evidence differs/fatal: " + str(mode))
            evidence = item.get("launch_evidence", {})
            if mode in ("invalid_missing_report", "invalid_outside_report"):
                if context.get("qa_enabled") is not True or context.get("valid") is not False or context.get("operations") or not context.get("refused_operations"):
                    failures.append("Invalid first-autoload context performed save I/O")
                if evidence.get("startup_report_written") is not False:
                    failures.append("Invalid startup report destination used fallback")
                engine = qa_launch.assert_safe_path(Path(evidence["engine_log"]), package, "reports")
                if sha(engine) != evidence.get("engine_log_sha256") or run_checks.fatal_lines(engine.read_text(encoding="utf-8", errors="replace")):
                    failures.append("Invalid first-autoload engine log differs/fatal")
            else:
                failures.extend(qa_launch.audit_record(evidence, package, run_checks.fatal_lines, expect_valid=expected_mode != "invalid"))
            for saved in item.get("seeded", {}).values():
                path = qa_launch.assert_safe_path(Path(saved["path"]), package, "tests/.user")
                if sha(path) != saved.get("sha256"):
                    failures.append("First-autoload seeded save bytes changed")
        except (OSError, ValueError, TypeError, KeyError) as failure:
            failures.append("First-autoload evidence unreadable: " + str(failure))
    return failures


def execute(package, name, command, marker, reports, version, timeout, hidden_render=False):
    started = datetime.now(timezone.utc).isoformat()
    started_ns = time.time_ns()
    log_path = package / 'reports' / ('package_' + name + '.log')
    output = ''
    run = None
    evidence = None
    try:
        qa_launch.preflight_project(package)
        for relative in reports:
            qa_launch.assert_safe_path(package / relative, package, 'reports').unlink(missing_ok=True)
        if name == 'checks':
            for path in (package / 'reports/runtime').glob('[0-9][0-9]_*.png'):
                path.unlink()
        if '--script' in command:
            evidence = qa_launch.prepare_launch(command, package, name, background=hidden_render or name == 'art_review')
            command = evidence.command
        launch_options = {}
        if os.name == 'nt' and name not in ('checks', 'checks_background', 'native', 'portraits'):
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 0 if hidden_render or name == 'art_review' else 1
            launch_options['startupinfo'] = startup
        run = subprocess.run(command, cwd=package, capture_output=True, text=True,
                             encoding='utf-8', errors='replace', timeout=timeout, **launch_options)
        output = run_checks.joined_output(run.stdout, run.stderr)
        errors = run_checks.fatal_lines(output) + [item for item in BAD_LOG if item in output]
        details = [read_json(package / relative) for relative in reports]
        for relative, detail in zip(reports, details):
            if (package / relative).stat().st_mtime_ns < started_ns:
                errors.append('report predates this run: ' + relative)
            if not isinstance(detail, dict):
                errors.append('report is not an object: ' + relative)
                continue
            reported = detail.get('program_version', detail.get('version'))
            if reported is not None and reported != version:
                errors.append('wrong report program version: ' + str(reported))
            if detail.get('passed') is not True or detail.get('failures'):
                errors.append('structured report failed')
            if name == 'qa_startup':
                errors.extend(qa_startup_check(detail, package))
            if name == 'background_host':
                errors.extend(background_host_smoke_check(detail, package))
            if name == 'checks':
                errors.extend(suite_check(detail, package, 'full', version))
            if name == 'checks_background':
                errors.extend(suite_check(detail, package, 'logic', version))
            if name in ('main24', 'main64', 'main64_2x'):
                errors.extend(performance_check(detail, 24 if name == 'main24' else 64, project_policy(package), 2.0 if name == 'main64_2x' else 1.0))
            if name in ('playback', 'playback_unmanaged'):
                errors.extend(playback_check(detail, package, project_policy(package), name == 'playback'))
            if name == 'mesh_redraw':
                errors.extend(mesh_redraw_check(detail, package, project_policy(package)))
            if (hidden_render or name == 'art_review') and name != 'background_host':
                errors.extend(offscreen_check(detail, name, package))
            elif name in ('playback', 'playback_unmanaged', 'mesh_redraw') and detail.get('background') is True:
                errors.append('Full verification cannot reuse an offscreen Spine report')
        marker_found = re.search(r'(?m)^\s*' + re.escape(marker) + r'(?:\s|$)', run_checks.ANSI_ESCAPE.sub('', run.stdout))
        passed = run.returncode == 0 and marker_found is not None and not errors
        result = {'case': name, 'passed': passed, 'exit_code': run.returncode,
                  'errors': errors, 'reports': reports, 'started_utc': started,
                  'hidden_render': hidden_render, 'command_line': command,
                  'diagnostic_log_lines': run_checks.diagnostic_lines(output),
                  'finished_utc': datetime.now(timezone.utc).isoformat()}
    except (subprocess.TimeoutExpired, OSError, ValueError, KeyError, TypeError, AttributeError) as failure:
        if not output and run is not None:
            output = run_checks.joined_output(getattr(run, 'stdout', None), getattr(run, 'stderr', None))
        if isinstance(failure, subprocess.TimeoutExpired):
            output = run_checks.joined_output(output, run_checks.joined_output(failure.stdout, failure.stderr))
        reason = type(failure).__name__ + ': ' + str(failure)
        output = run_checks.joined_output(output, '[PACKAGE_VERIFICATION_EXCEPTION] ' + reason)
        result = {'case': name, 'passed': False, 'error': str(failure),
                  'exit_code': run.returncode if run is not None else None,
                  'errors': run_checks.fatal_lines(output) + [item for item in BAD_LOG if item in output] + ['verification_exception: ' + reason],
                  'reports': reports, 'started_utc': started,
                  'diagnostic_log_lines': run_checks.diagnostic_lines(output),
                  'finished_utc': datetime.now(timezone.utc).isoformat()}
    if evidence is not None:
        result['qa_startup'] = qa_launch.validate_evidence(evidence, run_checks.fatal_lines)
        result['errors'].extend(result['qa_startup']['errors'])
        result['passed'] = result['passed'] and result['qa_startup']['passed']
    qa_launch.assert_safe_path(log_path, package, 'reports').write_text(output, encoding='utf-8')
    result['log'] = str(log_path.relative_to(package))
    result['hidden_render'] = hidden_render
    result['command_line'] = command
    print(name, 'PASS' if result['passed'] else 'FAIL', flush=True)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=ROOT)
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--phase', choices=('full', 'background', 'offscreen'), default='full')
    args = parser.parse_args(argv)
    package = args.package.resolve()
    qa_launch.preflight_project(package)
    godot = args.godot.resolve() if args.godot else package / 'FantasySiege.exe'
    report_name = {'full': 'package_verification.json', 'background': 'package_background.json', 'offscreen': 'package_offscreen.json'}[args.phase]
    output_path = package / 'reports' / report_name
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps({'passed': False, 'phase': 'preparing', 'package': str(package)}), encoding='utf-8')
    manifest_path = package / 'reports/build_manifest.json'
    manifest = read_json(manifest_path)
    version = re.search(r'config/version="([^"]+)"', (package / 'project.godot').read_text(encoding='utf-8')).group(1)
    if version != manifest['program_version']:
        raise SystemExit('Package manifest program version does not match project')
    policy = project_policy(package)
    initial_failures = payload_check(package, manifest) + portrait_check(package, version)
    if initial_failures:
        raise SystemExit('\n'.join(initial_failures))

    import sys
    python = sys.executable
    # The package settings must drive rendering and animation policy themselves.
    render = [str(godot), '--path', str(package)]
    native_ids = ','.join(key.removeprefix('d69_') for key in read_json(package / 'resources/visuals.json'))
    plans = [
        ('checks', [python, str(package / 'tools/run_checks.py'), '--godot', str(godot), '--visual'],
         run_checks.VISUAL_CASES[-1] + ' PASS', ['reports/checks.json'], sum(case.timeout for case in run_checks.CASES.values()) + 60),
        ('native', [python, str(package / 'tools/verify_spine.py'), '--godot', str(godot), '--ids', native_ids],
         'PASS d69_' + native_ids.split(',')[-1], ['reports/spine_verify.json'], 400),
        ('portraits', [python, str(package / 'tools/generate_portraits.py'), '--check'],
         'PORTRAITS_CHECK_COMPLETE', ['reports/portraits_local.json'], 120),
        ('playback', render + ['--script', 'res://tests/SpinePlayback.gd'],
         'SPINE_PLAYBACK_COMPLETE', ['reports/spine_playback.json'], 240),
        ('playback_unmanaged', render + ['--script', 'res://tests/SpinePlayback.gd', '--', 'unmanaged'],
         'SPINE_PLAYBACK_COMPLETE', ['reports/performance_0.1.3/playback_unmanaged.json'], 240),
        ('mesh_redraw', render + ['--script', 'res://tests/SpineMeshRedraw.gd'],
         'SPINE_MESH_REDRAW_COMPLETE', ['reports/performance_0.1.3/mesh_redraw.json'], 400),
        ('main24', render + ['--script', 'res://tests/MainPerformance013.gd', '--', 'main24', 'exclusive'],
         'MAIN_PERFORMANCE_COMPLETE', ['reports/performance_0.1.3/main24.json'], 120),
        ('main64', render + ['--script', 'res://tests/MainPerformance013.gd', '--', 'main64', 'exclusive'],
         'MAIN_PERFORMANCE_COMPLETE', ['reports/performance_0.1.3/main64.json'], 120),
        ('main64_2x', render + ['--script', 'res://tests/MainPerformance013.gd', '--', 'main64_2x', 'exclusive'],
         'MAIN_PERFORMANCE_COMPLETE', ['reports/performance_0.1.3/main64_2x.json'], 120),
        ('art_review', render + ['--script', 'res://tests/ArtReview.gd'],
         'ART_REVIEW_COMPLETE', ['reports/art_review_local.json'], 240),
    ]
    if args.phase == 'background':
        plans = [('checks_background', [python, str(package / 'tools/run_checks.py'), '--godot', str(godot)],
                  run_checks.CPU_CASES[-1] + ' PASS', ['reports/checks.json'], sum(run_checks.CASES[name].timeout for name in run_checks.CPU_CASES) + 60), plans[1], plans[2]]
    elif args.phase == 'offscreen':
        plans = [
            ('background_host', render + ['--script', 'res://tests/BackgroundHostSmoke.gd'],
             'BACKGROUND_HOST_SMOKE_COMPLETE', ['reports/background_host_smoke_local.json'], 60),
            ('playback', render + ['--script', 'res://tests/SpinePlayback.gd', '--', 'background'],
             'SPINE_PLAYBACK_COMPLETE', ['reports/spine_playback.json'], 240),
            ('playback_unmanaged', render + ['--script', 'res://tests/SpinePlayback.gd', '--', 'unmanaged', 'background'],
             'SPINE_PLAYBACK_COMPLETE', ['reports/performance_0.1.3/playback_unmanaged.json'], 240),
            ('mesh_redraw', render + ['--script', 'res://tests/SpineMeshRedraw.gd', '--', 'background'],
             'SPINE_MESH_REDRAW_COMPLETE', ['reports/performance_0.1.3/mesh_redraw.json'], 400),
            ('art_review', render + ['--script', 'res://tests/ArtReview.gd'],
             'ART_REVIEW_COMPLETE', ['reports/art_review_local.json'], 240),
        ]
    if args.phase != 'offscreen':
        plans.insert(0, ('qa_startup', [python, str(package / 'tools/verify_qa_startup.py'), '--project', str(package), '--godot', str(godot)],
                         'QA_STARTUP_VERIFICATION_COMPLETE', ['reports/qa_startup_verification_local.json'], 400))
    results = []
    for name, command, marker, reports, timeout in plans:
        results.append(execute(package, name, command, marker, reports, version, timeout, hidden_render=args.phase == 'offscreen'))
        output_path.write_text(json.dumps({'passed': False, 'phase': 'running', 'program_version': version,
                                          'cases': results}, ensure_ascii=False, indent=2), encoding='utf-8')

    audit = payload_check(package, manifest) + portrait_check(package, version)
    native = read_json(package / 'reports/spine_verify.json') if (package / 'reports/spine_verify.json').exists() else {}
    native_results = native.get('results', [])
    if args.phase != 'offscreen' or native:
        audit.extend(native_check(native, package))
    if args.phase != 'offscreen':
        for phase in ('textures', 'native'):
            path = package / 'reports' / ('bootstrap_' + phase + '_startup.json')
            if not path.is_file():
                audit.append('Editor import engine-log evidence missing: ' + phase)
            else:
                audit.extend(qa_launch.audit_record(read_json(path), package, run_checks.fatal_lines))
    flow_path = package / 'reports/main_flow.json'
    flow = read_json(flow_path) if args.phase == 'full' and flow_path.exists() else {}
    if args.phase == 'full':
        audit.extend(main_flow_check(flow, package))
    for filename in ('11_guide_summon.png', '12_guide_camera.png', '13_guide_pulse.png', '10_settings.png', '14_boss_book.png', '08_unlock_result.png'):
        if args.phase == 'full' and not (package / 'reports/runtime' / filename).is_file():
            audit.append('Missing rendered image: ' + filename)
    logs = [package / item['log'] for item in results]
    if args.phase != 'offscreen':
        logs += [package / 'reports' / (name + '.log') for name in (run_checks.CPU_CASES if args.phase == 'background' else run_checks.CASES)]
        logs += [package / 'reports/spine_probes' / ('d69_' + number + '.log') for number in native_ids.split(',')]
        logs += [package / 'reports' / ('bootstrap_' + phase + '.log') for phase in ('textures', 'native')]
    for path in logs:
        if not path.is_file():
            audit.append('Missing current run log: ' + str(path.relative_to(package)))
            continue
        text = path.read_text(encoding='utf-8', errors='replace')
        if run_checks.fatal_lines(text) or any(item in text for item in BAD_LOG):
            audit.append('Error or leak in ' + str(path.relative_to(package)))
    passed = all(item['passed'] for item in results) and not audit
    scopes = {'full': 'Windows local learning package', 'background': 'Background CPU, native-resource and payload checks only',
              'offscreen': 'Offscreen Spine playback, exact native/managed pixels and UI art only; no foreground interaction, campaign journey or performance verification'}
    final = {'passed': passed, 'phase': 'complete', 'scope': scopes[args.phase],
             'delivery_ready': passed and args.phase == 'full', 'verification_phase': args.phase,
             'program_version': version, 'package': str(package), 'godot': str(godot), 'manifest_sha256': sha(manifest_path),
             'production_policy': policy,
             'performance_verified': passed and args.phase == 'full',
             'known_startup_isolation_gap': False if passed else None,
             'background_host_initialization_verified': passed and args.phase == 'offscreen',
             'qa_startup_module_version': '0.2',
             'native_probe_reused': bool(native) and args.phase == 'offscreen',
             'units_sha256': sha(package / 'resources/units.json'), 'stages_sha256': sha(package / 'resources/stages.json'),
             'cases': results, 'audit_failures': audit, 'native_resources': len(native_results),
             'raw_animations': sum(item.get('animation_count', 0) for item in native_results),
             'finished_utc': datetime.now(timezone.utc).isoformat()}
    output_path.write_text(json.dumps(final, ensure_ascii=False, indent=2), encoding='utf-8')
    print('PACKAGE_VERIFICATION', 'PASS' if passed else 'FAIL', flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
