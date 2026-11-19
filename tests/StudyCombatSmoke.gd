extends SceneTree

## Isolated, non-rendered research and status-effect regression.
const LEGACY_LEVEL_ONE := {
	"guanyu": [698.5, 70.528, 1.640927, 46.215, 16.7, 0, 0],
	"zhaoyun": [368.0, 39.68, 0.833333, 84.8, 10.6, 0, 0],
	"zhugeliang": [258.0, 80.6, 1.945525, 38.798, 15.0, 0, 2.4],
	"diaochan": [261.6, 31.616, 1.201923, 45.32, 14.8, 0, 2.95],
	"lubu": [975.0, 117.8, 2.259615, 37.08, 18.0, 0, 0],
	"iron_guard": [609.6, 17.024, 1.513672, 42.756, 17.0, 0, 0],
	"ember_archer": [185.3, 42.56, 1.212687, 49.538, 7.3, 0, 0],
	"rune_medic": [204.425, 36.48, 1.647287, 40.96, 14.8, 43.0464, 0],
	"riftling": [74.2, 14.56, 1.057692, 63.86, 2.3, 0, 0],
	"ash_runner": [112.875, 23.84, 0.892857, 110.04, 3.9, 0, 0],
	"obsidian_guard": [787.4, 51.072, 1.862745, 30.45, 21.8, 0, 0],
	"ember_caster": [204.25, 35.264, 1.744186, 36.864, 13.3, 0, 0],
	"obsidian_warden": [2793.0, 82.16, 3.294574, 27.648, 14.6, 0, 0],
	"star_hammer": [1105.0, 27.28, 1.464844, 30.54, 26.7, 0, 0],
	"rivet_gunner": [196.2, 63.856, 2.32342, 38.052, 9.0, 0, 0],
	"moon_mage": [236.5, 59.52, 2.422481, 38.912, 15.5, 0, 2.64],
	"spirit_beast": [635.0, 53.504, 1.420455, 78.15, 10.0, 0, 0],
	"brass_chomper": [173.6, 25.696, 1.136364, 65.646, 11.2, 0, 0],
	"brass_guard": [1040.0, 57.04, 2.107843, 29.435, 23.7, 0, 0],
	"rail_stoker": [277.95, 41.344, 2.034884, 35.84, 16.8, 0, 0],
	"rail_colossus": [4080.0, 96.6, 3.613281, 27.486, 19.8, 0, 0],
}
var checks := 0
var failures: Array[String] = []
var cases: Array[String] = []
var matrix_cases := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _near(actual: float, expected: float) -> bool:
	return absf(actual-expected)<0.0001

func _battle(modifiers: Dictionary = {}, levels: Dictionary = {}) -> SiegeBattle:
	var battle := SiegeBattle.new()
	battle.auto_step = false
	battle.render_visuals = false
	root.add_child(battle)
	battle.start("stage_01", Catalog.initial_roster(), levels, modifiers)
	battle._waves.clear()
	return battle

func _quiet(battle: SiegeBattle) -> void:
	for unit: Dictionary in battle.units:
		unit.attack_timer = 1000.0
		unit.speed = 0.0

func _hit(battle: SiegeBattle, attacker: Dictionary, target: Dictionary, heal: bool = false) -> void:
	battle._begin_attack(attacker, target, heal)
	battle._elapsed = maxf(battle._elapsed, float(battle._hits.back().due))
	battle._resolve_hits()

func _run() -> void:
	var isolation := "res://tests/.user/study_combat"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolation))
	root.get_node("ProfileStore").configure_path(isolation+"/profile.json")
	root.get_node("UserPrefs").configure_path(isolation+"/preferences.json")
	var units_sha := FileAccess.get_sha256("res://resources/units.json")
	var studies_sha := FileAccess.get_sha256("res://resources/studies.json")
	_test_legacy()
	_test_modifiers()
	_test_snapshot()
	_test_route_matrix()
	_test_real_combat()
	await _test_slow_sources()
	_test_slow_area()
	_check(FileAccess.get_sha256("res://resources/units.json")==units_sha, "fixture does not rewrite unit recipes")
	_check(FileAccess.get_sha256("res://resources/studies.json")==studies_sha, "matrix does not rewrite study recipes")
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"phase":"complete","visuals":false,"isolation":isolation,"program_version":str(ProjectSettings.get_setting("application/config/version","unknown")),"unit_stats_sha256":FileAccess.get_sha256("res://scripts/core/UnitStats.gd"),"siege_battle_sha256":FileAccess.get_sha256("res://scripts/combat/SiegeBattle.gd"),"units_sha256":units_sha,"studies_sha256":studies_sha,"matrix_cases":matrix_cases,"cases":cases,"scope":"Central research stat outputs, 108 configured player/level/route battle-spawn cases, isolated battle snapshots and independent-source slow expiry; headless logic only, no Spine, window or performance claim"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var file := FileAccess.open("res://reports/study_combat_smoke.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("STUDY_COMBAT_SMOKE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _test_legacy() -> void:
	_check(Catalog.units().size()==21 and LEGACY_LEVEL_ONE.size()==21, "all twenty-one original units have frozen references")
	var keys := ["hp","damage","attack_interval","speed","magic_armor"]
	for id: String in LEGACY_LEVEL_ONE:
		var definition := Catalog.unit(id)
		var calculated := UnitStats.calculate(definition,1)
		for index: int in keys.size():
			_check(_near(float(calculated[keys[index]]),float(LEGACY_LEVEL_ONE[id][index])), id+": legacy "+keys[index])
		_check(_near(float(calculated.armor),float(definition.armor)), id+": base armor unchanged")
		_check(_near(float(calculated.range),float(definition.range)), id+": base range unchanged")
		_check(_near(float(calculated.hit_delay),float(definition.hit_delay)), id+": base hit timing unchanged")
		_check(_near(float(calculated.aoe_radius),float(definition.aoe_radius)), id+": base area unchanged")
		_check(str(calculated.damage_type)==str(definition.damage_type), id+": damage identity unchanged")
		_check(_near(float(calculated.special.get("amount",0.0)),float(LEGACY_LEVEL_ONE[id][5])), id+": old healing once")
		_check(_near(float(calculated.special.get("duration",0.0)),float(LEGACY_LEVEL_ONE[id][6])), id+": old slow duration once")
	for id: String in Catalog.playable_roster():
		for level: int in [1,3,20]:
			var calculated := UnitStats.calculate(Catalog.unit(id),level)
			_check(float(calculated.hit_delay)>=0 and float(calculated.hit_delay)<float(calculated.attack_interval), id+": valid timing at level "+str(level))
	cases.append("frozen_21_units_and_36_player_timings")

func _fixture() -> Dictionary:
	return {"hp":100.0,"damage":20.0,"armor":40.0,"range":100.0,"speed":50.0,"attack_interval":2.0,"hit_delay":0.4,"aoe_radius":50.0,"damage_type":"magic","primary_attribute":"intelligence","attributes":{"strength":10.0,"agility":20.0,"intelligence":30.0},"special":{"type":"slow","duration":2.0,"ratio":0.65,"nested":{"items":[1]}}}

func _test_modifiers() -> void:
	var definition := _fixture()
	var modifiers := {"hp_mult":1.2,"damage_mult":1.3,"armor_add":10.0,"speed_mult":1.1,"range_mult":1.2,"attack_interval_mult":0.8,"hit_delay_mult":0.75,"aoe_radius_mult":1.5,"heal_amount_mult":1.25,"slow_ratio":0.3,"slow_duration_mult":1.4,"base_damage_multiplier":2.1}
	var calculated := UnitStats.calculate(definition,3,modifiers)
	var expected := {"hp":158.592,"damage":40.2688,"armor":50.0,"magic_armor":45.4,"speed":58.63,"range":120.0,"attack_interval":1.470588235294,"hit_delay":0.3,"aoe_radius":75.0}
	for key: String in expected:
		_check(_near(float(calculated[key]),float(expected[key])), "central modifier "+key)
	_check(_near(float(calculated.special.ratio),0.3) and _near(float(calculated.special.duration),3.752), "slow override and duration include intelligence once")
	_check(_near(float(calculated.special.base_damage_multiplier),2.1), "central siege override")
	_check(str(calculated.damage_type)=="magic" and _near(float(calculated.stats.intelligence),34.0), "modifiers retain attribute and damage identity")
	calculated.special.nested.items.append(2)
	_check(definition.special.nested.items==[1], "nested special is not shared with input")
	_check(UnitStats.calculate(definition,3,modifiers).special.nested.items==[1], "nested special is not shared across calculations")
	definition.special = {"type":"heal"}
	var healer := UnitStats.calculate(definition,3,modifiers)
	_check(_near(float(healer.special.amount),67.45024), "fallback heal uses final damage and intelligence once")
	definition.special.amount = 23.0
	_check(_near(float(UnitStats.calculate(definition,3,modifiers).special.amount),38.525), "explicit healing amount is independently scaled once")
	definition = _fixture()
	var baseline := UnitStats.calculate(definition,3)
	for invalid: Dictionary in [{"hp_mult":INF},{"damage_mult":NAN},{"armor_add":"99"},{"speed_mult":true},{"range_mult":[]},{"base_damage_multiplier":NAN},{"damage_type":"true","special":{"type":"heal"},"intelligence":999}]:
		_check(UnitStats.calculate(definition,3,invalid)==baseline, "invalid or unknown modifier ignored: "+str(invalid.keys()))
	var clamped := UnitStats.calculate(definition,3,{"hp_mult":-5.0,"damage_mult":-1.0,"armor_add":-999.0,"speed_mult":-1.0,"range_mult":0.0,"attack_interval_mult":-1.0,"hit_delay_mult":-1.0,"aoe_radius_mult":-1.0,"slow_ratio":0.0})
	_check(float(clamped.hp)>=1 and float(clamped.damage)==0 and float(clamped.speed)==0, "health, damage and speed lower bounds")
	_check(float(clamped.armor)==0 and _near(float(clamped.magic_armor),20.4), "final magic armor follows final armor")
	_check(float(clamped.range)==16 and float(clamped.aoe_radius)==0 and float(clamped.hit_delay)==0 and float(clamped.attack_interval)>0, "range and timing lower bounds")
	_check(float(clamped.special.ratio)==0.1, "slow ratio has lower bound")
	var long_delay := UnitStats.calculate(definition,20,{"attack_interval_mult":0.2,"hit_delay_mult":999.0})
	_check(float(long_delay.hit_delay)>=0 and float(long_delay.hit_delay)<float(long_delay.attack_interval), "oversized research delay ends before next attack")
	_check(float(UnitStats.calculate(definition,1,{"slow_ratio":2.0}).special.ratio)==1.0, "slow ratio has upper bound")
	cases.append("all_whitelisted_modifiers_and_copy_boundaries")

func _test_snapshot() -> void:
	var research := {"iron_guard":{"hp_mult":1.3,"armor_add":7.0},"obsidian_guard":{"damage_mult":5.0},"rune_medic":{"heal_amount_mult":1.4}}
	var levels := {"iron_guard":4}
	var battle := _battle(research,levels)
	research.iron_guard.hp_mult = 99.0
	research.rune_medic.heal_amount_mult = 99.0
	levels.iron_guard = 20
	var first := battle._spawn("iron_guard",1)
	var second := battle._spawn("iron_guard",1)
	var expected := UnitStats.calculate(Catalog.unit("iron_guard"),4,{"hp_mult":1.3,"armor_add":7.0})
	_check(first.level==4 and second.level==4 and _near(float(first.hp),float(expected.hp)) and _near(float(second.hp),float(expected.hp)), "later summons inherit copied level and research snapshot")
	_check(_near(float(first.armor),float(expected.armor)) and _near(float(first.magic_armor),float(expected.magic_armor)), "spawn reads central final armor")
	first.special.base_damage_multiplier = 999.0
	_check(not second.special.has("base_damage_multiplier") and not Catalog.unit("iron_guard").special is Dictionary, "summon specials remain independent")
	var enemy := battle._spawn("obsidian_guard",-1,{"hp_mult":1.5,"damage_mult":1.8})
	var enemy_expected := UnitStats.calculate(Catalog.unit("obsidian_guard"),1,{"hp_mult":1.5,"damage_mult":1.8})
	_check(enemy.level==1 and _near(float(enemy.damage),float(enemy_expected.damage)) and _near(float(enemy.hp),float(enemy_expected.hp)), "enemy ignores player studies and keeps central wave multipliers")
	var medic := battle._spawn("rune_medic",1)
	_check(_near(float(medic.special.amount),60.26496), "later healer uses start-time study snapshot")
	battle.start("stage_02",Catalog.initial_roster())
	_check(battle._study_modifiers.is_empty() and battle.units.is_empty(), "restart clears previous study and actor state")
	var restarted := battle._spawn("iron_guard",1)
	_check(restarted.level==1 and _near(float(restarted.hp),609.6), "restart without study uses original unit")
	battle.stop()
	_check(battle._study_modifiers.is_empty(), "stop clears research snapshot")
	battle.free()
	cases.append("start_snapshot_enemy_isolation_and_restart")

func _test_route_matrix() -> void:
	for id: String in Catalog.playable_roster():
		var routes: Array[String] = ["base"]
		for route: Dictionary in Catalog.study_routes(id): routes.append(str(route.id))
		_check(routes.size()==3, id+": matrix includes base and both authored routes")
		for level: int in [1,3,20]:
			for route: String in routes:
				var modifiers := Catalog.study_modifiers(id,route)
				var expected := UnitStats.calculate(Catalog.unit(id),level,modifiers)
				var levels := {}
				levels[id] = level
				var study_snapshot := {}
				study_snapshot[id] = modifiers
				var battle := SiegeBattle.new()
				battle.auto_step = false
				battle.render_visuals = false
				root.add_child(battle)
				battle.start("stage_01",[id],levels,study_snapshot)
				# Mutating the caller after start must not alter either summon.
				modifiers.damage_mult = 99.0
				var actor := battle._spawn(id,1)
				var label := "%s/Lv%s/%s" % [id,level,route]
				_check(_near(float(actor.hp),float(expected.hp)) and _near(float(actor.max_hp),float(expected.hp)), label+": actual hp and maxhp equal central result")
				for key: String in ["damage","armor","magic_armor","range","attack_interval","hit_delay","aoe_radius"]:
					_check(_near(float(actor[key]),float(expected[key])), label+": actual "+key+" equals central result")
				_check(_near(float(actor.speed),float(expected.speed)*battle._move_speed_multiplier), label+": actual speed includes only stage movement rule")
				_check(str(actor.damage_type)==str(expected.damage_type), label+": actual damage type equals central result")
				_check(actor.stats==expected.stats and int(actor.level)==int(expected.level), label+": actual level and attributes equal central result")
				_check(actor.special==expected.special, label+": actual skill output equals central result")
				actor.special.copy_probe = {"items":[1]}
				actor.special.copy_probe.items.append(2)
				var second := battle._spawn(id,1)
				_check(second.special==expected.special and not expected.special.has("copy_probe"), label+": repeated summon and preview skill dictionaries independent")
				var original_special: Variant = Catalog.unit(id).get("special", "")
				_check(not (original_special is Dictionary) or not original_special.has("copy_probe"), label+": Catalog skill recipe remains independent")
				matrix_cases += 1
				battle.free()
	_check(matrix_cases==108, "all 108 configured player-level-route spawn cases completed")
	cases.append("configured_108_battle_spawn_matrix")

func _test_real_combat() -> void:
	var battle := _battle({"iron_guard":{"armor_add":12.0}})
	var target := battle._spawn("iron_guard",1)
	var before := float(target.hp)
	var raw := battle._damage_unit(target,100.0,"magic",-1)
	_check(_near(raw,100.0*50.0/73.0) and _near(before-float(target.hp),raw), "actual magic hit reads research armor")
	battle.free()
	battle = _battle({"zhaoyun":{"range_mult":1.5,"hit_delay_mult":0.5,"attack_interval_mult":0.85}})
	var attacker := battle._spawn("zhaoyun",1)
	target = battle._spawn("obsidian_guard",-1)
	attacker.x = 200.0
	target.x = 200.0 + float(Catalog.unit("zhaoyun").range) + 10.0
	attacker.speed = 0.0
	target.speed = 0.0
	target.attack_timer = 1000.0
	before = float(target.hp)
	battle.advance(SiegeBattle.FIXED_STEP)
	_check(battle._hits.size()==1 and int(battle._hits[0].attacker)==int(attacker.uid), "research range starts real attack outside original range")
	_check(_near(float(battle._hits[0].due)-battle._elapsed,float(attacker.hit_delay)), "real queued hit reads central delay")
	_check(_near(float(attacker.attack_timer),float(attacker.attack_interval)), "real attack timer reads research interval")
	battle.advance(float(attacker.hit_delay)*0.4)
	_check(_near(float(target.hp),before), "research delayed hit does not resolve early")
	battle.advance(float(attacker.hit_delay)*0.7+SiegeBattle.FIXED_STEP)
	_check(float(target.hp)<before, "research delayed hit resolves on actual fixed clock")
	battle.free()
	battle = _battle({"guanyu":{"aoe_radius_mult":1.5}})
	attacker = battle._spawn("guanyu",1)
	target = battle._spawn("obsidian_guard",-1)
	var area_target := battle._spawn("obsidian_guard",-1)
	var outside := battle._spawn("obsidian_guard",-1)
	target.x = 300.0
	area_target.x = 300.0+float(Catalog.unit("guanyu").aoe_radius)+10.0
	outside.x = 300.0+float(attacker.aoe_radius)+10.0
	var area_hp := float(area_target.hp)
	var outside_hp := float(outside.hp)
	_hit(battle,attacker,target)
	_check(float(area_target.hp)<area_hp and _near(float(outside.hp),outside_hp), "research area expands actual hit selection only to final radius")
	battle.free()
	battle = _battle({"rune_medic":{"heal_amount_mult":1.3}})
	var medic := battle._spawn("rune_medic",1)
	target = battle._spawn("iron_guard",1)
	target.hp = 100.0
	medic.heal_multiplier = 999.0
	_hit(battle,medic,target,true)
	_check(_near(float(target.hp),100.0+55.96032), "actual heal consumes final special without repeating intelligence")
	battle.free()
	battle = _battle({"rivet_gunner":{"base_damage_multiplier":2.2}})
	attacker = battle._spawn("rivet_gunner",1)
	before = battle._enemy_hp
	_hit(battle,attacker,{"base":true,"team":-1,"x":battle.enemy_x})
	_check(_near(before-battle._enemy_hp,63.856*2.2), "research siege multiplier affects actual base damage")
	battle.free()
	battle = _battle({"zhaoyun":{"speed_mult":1.2}})
	attacker = battle._spawn("zhaoyun",1)
	before = float(attacker.x)
	battle._move_actor(attacker,1000.0,0.25)
	_check(_near(float(attacker.x)-before,84.8*1.2*battle._move_speed_multiplier*0.25), "research speed drives real movement with stage rule")
	battle.free()
	cases.append("actual_research_combat_effects")

func _test_slow_sources() -> void:
	var battle := _battle({"moon_mage":{"slow_ratio":0.3,"slow_duration_mult":1.0/2.64,"hit_delay_mult":0.0},"diaochan":{"slow_ratio":0.6,"slow_duration_mult":3.0/2.95,"hit_delay_mult":0.0}})
	var strong := battle._spawn("moon_mage",1)
	var weak := battle._spawn("diaochan",1)
	var target := battle._spawn("obsidian_guard",-1)
	strong.damage = 0.0
	weak.damage = 0.0
	strong.aoe_radius = 0.0
	_hit(battle,strong,target)
	_hit(battle,weak,target)
	_check(target.slow_sources.size()==2 and _near(float(target.slow_ratio),0.3) and _near(float(target.slow_timer),3.0), "actual slow hits keep independent strong-short and weak-long sources")
	_quiet(battle)
	battle.advance(0.4)
	var strong_remaining := float(target.slow_sources[int(strong.uid)].remaining)
	_hit(battle,weak,target)
	_check(_near(float(target.slow_sources[int(strong.uid)].remaining),strong_remaining), "refreshing weak source cannot renew strong source")
	_check(_near(float(target.slow_sources[int(weak.uid)].remaining),3.0), "same source refreshes its own deadline")
	_quiet(battle)
	battle.advance(0.7)
	_check(not target.slow_sources.has(int(strong.uid)) and _near(float(target.slow_ratio),0.6) and _near(float(target.slow_timer),2.3), "strong source expires to still-valid weaker source")
	battle._damage_unit(weak,999999.0,"true",-1)
	_quiet(battle)
	battle.advance(1.0)
	_check(battle._unit_by_uid(int(weak.uid)).is_empty() and target.slow_sources.has(int(weak.uid)) and _near(float(target.slow_ratio),0.6), "dead and removed caster does not erase delivered slow early")
	var paused_remaining := float(target.slow_timer)
	battle.set_visual_playback(0.0)
	await create_timer(0.1).timeout
	_check(_near(float(target.slow_timer),paused_remaining), "real scene frames do not consume paused fixed-step slow")
	battle.set_visual_playback(1.0)
	battle.advance(2.0)
	_check(target.slow_sources.is_empty() and float(target.slow_ratio)==1.0 and float(target.slow_timer)==0.0, "all sources expire and restore original speed")
	_hit(battle,strong,target)
	battle.stop()
	_check(target.slow_sources.is_empty() and float(target.slow_ratio)==1.0 and float(target.slow_timer)==0.0, "stop clears retained source state and summaries")
	battle.free()
	cases.append("FS030_independent_refresh_expiry_death_and_pause")

func _test_slow_area() -> void:
	var battle := _battle({"moon_mage":{"aoe_radius_mult":1.3,"hit_delay_mult":0.0}})
	var caster := battle._spawn("moon_mage",1)
	var first := battle._spawn("obsidian_guard",-1)
	var second := battle._spawn("obsidian_guard",-1)
	var outside := battle._spawn("obsidian_guard",-1)
	caster.damage = 0.0
	first.x = 300.0
	second.x = 400.0
	outside.x = 430.0
	_hit(battle,caster,first)
	_check(first.slow_sources.has(int(caster.uid)) and second.slow_sources.has(int(caster.uid)) and outside.slow_sources.is_empty(), "AoE slow uses central area and separate per-victim sources")
	var second_remaining := float(second.slow_timer)
	battle._tick_slows(first,0.4)
	_check(_near(float(second.slow_timer),second_remaining) and _near(float(first.slow_timer),second_remaining-0.4), "AoE victims do not share source dictionaries")
	battle.free()
	cases.append("AoE_slow_source_isolation")
