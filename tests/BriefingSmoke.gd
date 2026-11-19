extends SceneTree

const ISOLATION := "res://tests/.user/briefing_smoke"
const INPUTS := {
	"project_sha256": "res://project.godot",
	"gdd_sha256": "res://docs/GAME_DESIGN.md",
	"briefings_sha256": "res://resources/briefings.json",
	"units_sha256": "res://resources/units.json",
	"stages_sha256": "res://resources/stages.json",
	"studies_sha256": "res://resources/studies.json",
}
const SCRIPT_INPUTS := ["scripts/core/BattleBriefing.gd", "scripts/core/UnitStats.gd", "scripts/combat/SiegeBattle.gd"]
var checks := 0
var failures: Array[String] = []
var stage_count := 0
var matrix_cases := 0
var enemy_recipe_cases := 0
var boss_ids: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.0001

func _battle(stage_id: String, roster: Array = [], levels: Dictionary = {}, modifiers: Dictionary = {}) -> SiegeBattle:
	var battle := SiegeBattle.new()
	battle.auto_step = false
	battle.render_visuals = false
	root.add_child(battle)
	battle.start(stage_id, roster, levels, modifiers)
	return battle

func _dispose(battle: SiegeBattle) -> void:
	battle.stop()
	_check(battle.units.is_empty() and battle._waves.is_empty() and battle._unit_lookup.is_empty(), "battle stop releases fixture actors and wave state")
	battle.free()

func _assert_spawn(battle: SiegeBattle, actor: Dictionary, stats: Dictionary, label: String) -> void:
	_check(not actor.is_empty(), label + ": actual spawn exists")
	if actor.is_empty(): return
	for key: String in ["hp", "damage", "armor", "magic_armor", "range", "attack_interval", "hit_delay", "aoe_radius"]:
		_check(_near(float(actor[key]), float(stats[key])), label + ": actual " + key)
	_check(_near(float(actor.max_hp), float(stats.hp)), label + ": actual maximum HP")
	_check(_near(float(actor.speed), float(stats.speed) * battle._move_speed_multiplier), label + ": central speed plus actual stage march multiplier")
	_check(actor.stats == stats.stats and actor.special == stats.special, label + ": actual attributes and complete special recipe")
	_check(str(actor.damage_type) == str(stats.damage_type) and int(actor.level) == int(stats.level), label + ": actual damage identity and level")
	_check(actor.visual == null, label + ": fixture never loads a native actor")

func _wave_for_variant(timeline: Array, id: String, variant: Dictionary) -> Dictionary:
	for wave: Dictionary in timeline:
		if str(wave.get("unit_id", "")) != id: continue
		if maxf(0.01, UnitStats.modifier_value(wave, "hp_mult")) == float(variant.hp_mult) and maxf(0.0, UnitStats.modifier_value(wave, "damage_mult")) == float(variant.damage_mult):
			return wave.duplicate(true)
	return {}

func _test_stages() -> void:
	var hostile_levels: Dictionary = {}
	var hostile_studies: Dictionary = {}
	for id: String in Catalog.units():
		hostile_levels[id] = 20
		hostile_studies[id] = {"hp_mult": 25.0, "damage_mult": 30.0, "armor_add": 50.0, "range_mult": 2.0, "slow_ratio": 0.1, "base_damage_multiplier": 5.0}
	for stage: Dictionary in Catalog.stages():
		var id := str(stage.id)
		var summary := BattleBriefing.summarize(id)
		var battle := _battle(id, Catalog.initial_roster(), hostile_levels, hostile_studies)
		stage_count += 1
		_check(summary.stage == Catalog.stage(id), id + ": original stage metadata remains intact")
		_check(summary.timeline == battle._waves, id + ": complete planned dictionaries match actual battle waves")
		_check(int(summary.total_count) == battle._waves.size(), id + ": total planned population matches battle")
		_check(_near(float(summary.last_time), float(battle._waves.back().time)), id + ": final planned time matches battle")
		var total := 0
		for enemy: Dictionary in summary.enemies:
			var times: Array[float] = []
			for wave: Dictionary in battle._waves:
				if str(wave.get("unit_id", "")) == str(enemy.id): times.append(float(wave.time))
			_check(int(enemy.count) == times.size() and _near(float(enemy.first_time), times.front()) and _near(float(enemy.last_time), times.back()), id + "/" + str(enemy.id) + ": grouped count and arrival span")
			var variant_count := 0
			for variant: Dictionary in enemy.variants:
				var wave := _wave_for_variant(summary.timeline, str(enemy.id), variant)
				_check(not wave.is_empty(), id + ": grouped recipe belongs to an actual scheduled wave")
				var actor := battle._spawn(str(enemy.id), -1, wave)
				_assert_spawn(battle, actor, variant.stats, id + "/" + str(enemy.id) + " enemy recipe")
				_check(int(actor.get("level", -1)) == 1, id + ": player levels and research never promote enemies")
				if not actor.is_empty() and actor.special.has("phase_threshold"):
					var base_damage := float(actor.damage)
					var base_interval := float(actor.attack_interval)
					var base_speed := float(actor.speed)
					actor.hp = float(actor.max_hp) * float(variant.stats.special.phase_threshold)
					battle._check_phase(actor)
					_check(bool(actor.phase) and not str(variant.stats.special.get("phase_name", "")).is_empty(), str(enemy.id) + ": named phase triggers at summarized HP ratio")
					_check(_near(float(actor.damage) / base_damage, float(variant.stats.special.phase_damage_mult)) and _near(float(actor.attack_interval) / base_interval, float(variant.stats.special.phase_attack_mult)) and _near(float(actor.speed) / base_speed, float(variant.stats.special.phase_speed_mult)), str(enemy.id) + ": actual phase multipliers equal summarized recipe")
					if not boss_ids.has(str(enemy.id)): boss_ids.append(str(enemy.id))
				variant_count += int(variant.count)
				enemy_recipe_cases += 1
				# Restart before the next recipe so the population limit is irrelevant.
				battle.stop()
				battle.start(id, Catalog.initial_roster(), hostile_levels, hostile_studies)
			_check(variant_count == int(enemy.count), id + "/" + str(enemy.id) + ": every grouped recipe contributes its exact count")
			total += int(enemy.count)
		_check(total == int(summary.total_count), id + ": enemy groups cover every planned actor")
		_dispose(battle)
	_check(stage_count == 8 and boss_ids.has("obsidian_warden") and boss_ids.has("rail_colossus"), "all eight stages and both authored Boss phases verified")

func _test_wave_boundaries() -> void:
	var saved_stages := Catalog.stages().duplicate(true)
	var stage := Catalog.stage("stage_01")
	stage.id = "briefing_boundary_fixture"
	stage.waves = [
		{"unit_id": "riftling", "count": -2, "time": -100.0, "interval": -5.0},
		{"unit_id": "riftling", "count": 3, "time": -3.0, "interval": 2.0, "hp_mult": -1.0, "damage_mult": -4.0},
		{"unit_id": "riftling", "count": 2, "time": 0.0, "interval": -10.0, "hp_mult": true, "damage_mult": "bad"},
		{"unit_id": "riftling", "count": 1, "time": 0.0, "hp_mult": INF, "damage_mult": NAN},
		{"unit_id": "riftling", "count": 1, "time": 0.0, "hp_mult": 1.6, "damage_mult": 1.3},
	]
	Catalog._stages.append(stage)
	var summary := BattleBriefing.summarize(str(stage.id))
	var battle := _battle(str(stage.id))
	var sequences: Array[int] = []
	for index: int in summary.timeline.size():
		var planned: Dictionary = summary.timeline[index]
		var actual: Dictionary = battle._waves[index]
		sequences.append(int(planned.sequence))
		_check(str(planned.unit_id) == str(actual.unit_id) and int(planned.sequence) == int(actual.sequence) and _near(float(planned.time), float(actual.time)), "boundary schedule preserves actual stable wave order")
	_check(sequences == [0, 1, 3, 4, 5, 6, 2] and int(summary.total_count) == 7 and _near(float(summary.last_time), 1.0), "negative count/time/interval use battle boundaries and equal-time order")
	_check(summary.enemies.size() == 1 and summary.enemies[0].variants.size() == 3, "invalid numeric recipes normalize to the same effective variant")
	for variant: Dictionary in summary.enemies[0].variants:
		var source := _wave_for_variant(summary.timeline, "riftling", variant)
		var actor := battle._spawn("riftling", -1, source)
		_assert_spawn(battle, actor, variant.stats, "boundary enemy recipe")
		if _near(float(variant.hp_mult), 0.01): _check(float(variant.damage_mult) == 0.0 and int(variant.count) == 3, "negative multipliers clamp to positive minimum HP and zero damage")
		if _near(float(variant.hp_mult), 1.0): _check(float(variant.damage_mult) == 1.0 and int(variant.count) == 3, "boolean/string/nonfinite multipliers use central fallback")
		battle.stop()
		battle.start(str(stage.id), [])
	_dispose(battle)
	Catalog._stages = saved_stages
	_check(Catalog.stage(str(stage.id)).is_empty(), "boundary fixture restores Catalog without writing source data")

func _test_matrix() -> void:
	var players := Catalog.playable_roster()
	_check(players.size() == 12, "all twelve authored player identities exist")
	for id: String in players:
		var routes: Array = [{"id": "base", "modifiers": {}}]
		routes.append_array(Catalog.study_routes(id))
		_check(routes.size() == 3, id + ": base and two real research routes exist")
		for level: int in [1, 3, 20]:
			for route: Dictionary in routes:
				var levels := {id: level}
				var modifiers := {id: route.modifiers.duplicate(true)}
				var ready := BattleBriefing.readiness("stage_08", [id], levels, modifiers, [id])
				var expected := UnitStats.calculate(Catalog.unit(id), level, route.modifiers)
				_check(ready.members.size() == 1 and str(ready.members[0].id) == id and int(ready.members[0].level) == level, id + ": isolated readiness keeps the saved member and level")
				_check(ready.members[0].stats == expected, id + ": readiness reads the full central level/research result")
				var battle := _battle("stage_08", [id], levels, modifiers)
				_assert_spawn(battle, battle._spawn(id, 1), ready.members[0].stats, id + "/Lv" + str(level) + "/" + str(route.id))
				for suggestion: Dictionary in ready.recommendations:
					_check(suggestion.alternatives.is_empty(), id + ": isolated ownership never suggests an unavailable substitute")
				matrix_cases += 1
				_dispose(battle)
	_check(matrix_cases == 108, "all 108 player/level/real-route readiness and actual-spawn cases completed")

func _recommendation(ready: Dictionary, capability: String) -> Dictionary:
	for item: Dictionary in ready.recommendations:
		if str(item.capability) == capability: return item
	return {}

func _test_readiness_rules() -> void:
	var roster := ["zhaoyun", "iron_guard", "rune_medic", "ember_archer"]
	var ready := BattleBriefing.readiness("stage_02", roster, {}, {}, roster)
	_check(ready.capabilities.low_cost == ["zhaoyun", "iron_guard"], "only low-cost damaging melee can fill the low-cost reinforcement role")
	_check(not ready.capabilities.frontline.has("rune_medic") and not ready.capabilities.magic.has("rune_medic"), "healers do not masquerade as a frontline or magical attacker")
	ready = BattleBriefing.readiness("stage_02", roster, {}, {"zhaoyun": {"range_mult": 2.0}, "iron_guard": {"damage_mult": 0.0}}, roster)
	_check(ready.capabilities.low_cost.is_empty(), "research-expanded range and zero damage remove low-cost melee capability")
	ready = BattleBriefing.readiness("stage_08", ["guanyu", "rune_medic", "diaochan", "rivet_gunner"], {}, {"guanyu": {"aoe_radius_mult": 0.0}, "rune_medic": {"heal_amount_mult": 0.0}, "diaochan": {"slow_ratio": 1.0}, "rivet_gunner": {"base_damage_multiplier": 1.0}}, Catalog.playable_roster())
	_check(ready.capabilities.aoe.is_empty() and ready.capabilities.healing.is_empty() and ready.capabilities.slow.is_empty() and ready.capabilities.siege.is_empty(), "capabilities reflect actual disabled area/heal/control/siege effects")
	var all_players := Catalog.playable_roster()
	var expected_frontline := ["guanyu", "lubu", "iron_guard", "star_hammer", "spirit_beast"]
	for id: String in all_players:
		ready = BattleBriefing.readiness("stage_01", [id], {}, {}, [id])
		_check(ready.capabilities.frontline.has(id) == expected_frontline.has(id), id + ": explicit guarding identity remains distinct from other capabilities")
	var owned := ["iron_guard", "rivet_gunner", "rivet_gunner", "riftling", "unknown", 99]
	ready = BattleBriefing.readiness("stage_05", ["iron_guard"], {}, {}, owned)
	_check(_recommendation(ready, "true_damage").alternatives == ["rivet_gunner"] and _recommendation(ready, "siege").alternatives == ["rivet_gunner"], "missing capabilities suggest the owned unfielded siege hero exactly once")
	for suggestion: Dictionary in ready.recommendations:
		_check(not str(suggestion.reason).is_empty() and not str(suggestion.message).is_empty(), "every stage suggestion retains its separate reason and readable message")
		for id: String in suggestion.alternatives:
			_check(owned.has(id) and id != "iron_guard" and all_players.has(id), "substitute never exceeds ownership or duplicates the squad")
	ready = BattleBriefing.readiness("stage_05", ["iron_guard", "rivet_gunner"], {}, {}, owned)
	_check(_recommendation(ready, "true_damage").present == ["rivet_gunner"] and _recommendation(ready, "true_damage").alternatives.is_empty(), "covered capability reports its actual member rather than unnecessary substitutes")
	ready = BattleBriefing.readiness("stage_05", ["iron_guard"], {}, {}, ["iron_guard"])
	_check(_recommendation(ready, "true_damage").alternatives.is_empty() and "训练" in str(_recommendation(ready, "true_damage").message), "missing unavailable hero receives a legal tactical fallback")
	ready = BattleBriefing.readiness("stage_01", ["unknown", "riftling", 7, "iron_guard", "iron_guard", "guanyu"], {}, {}, ["iron_guard"])
	_check(ready.members.size() == 1 and str(ready.members[0].id) == "iron_guard", "unknown/enemy/numeric/duplicate/unowned roster entries are rejected")
	ready = BattleBriefing.readiness("stage_01", all_players, {}, {}, all_players)
	var admitted: Array[String] = []
	for member: Dictionary in ready.members: admitted.append(str(member.id))
	_check(admitted == all_players.slice(0, 8), "readiness accepts at most the first eight valid owned members")
	ready = BattleBriefing.readiness("stage_01", [], {}, {}, [])
	_check(ready.members.is_empty(), "empty ownership and roster never manufacture a squad")
	for suggestion: Dictionary in ready.recommendations: _check(suggestion.present.is_empty() and suggestion.alternatives.is_empty(), "empty ownership never recommends an unauthorized hero")
	_check(BattleBriefing.summarize("").is_empty() and BattleBriefing.summarize("unknown_stage").is_empty(), "empty and unknown stages return no briefing")
	ready = BattleBriefing.readiness("unknown_stage", ["iron_guard"], {}, {}, ["iron_guard"])
	_check(ready.recommendations.is_empty(), "unknown stages generate no authored recommendations")
	var invalid_battle := _battle("unknown_stage", ["iron_guard"])
	_check(invalid_battle._waves.is_empty() and invalid_battle._outcome == "idle", "unknown briefing agrees with battle refusal to start")
	_dispose(invalid_battle)

func _test_copies() -> void:
	var stage_before := Catalog.stage("stage_01")
	var units_before := Catalog.units().duplicate(true)
	var roster := ["guanyu", "rune_medic"]
	var owned := ["guanyu", "rune_medic", "iron_guard"]
	var levels := {"guanyu": 3, "rune_medic": 3}
	var modifiers := {"guanyu": {"hp_mult": 1.2, "ignored": {"items": [1]}}, "rune_medic": {"heal_amount_mult": 1.3}}
	var input_before := {"roster": roster.duplicate(true), "owned": owned.duplicate(true), "levels": levels.duplicate(true), "modifiers": modifiers.duplicate(true)}
	var summary := BattleBriefing.summarize("stage_01")
	summary.stage.waves[0].hp_mult = 999.0
	_check(float(summary.timeline[0].hp_mult) == float(stage_before.waves[0].hp_mult), "stage metadata and expanded wave recipes are independent copies")
	summary.timeline[0].hp_mult = 999.0
	summary.enemies[0].variants[0].stats.special["copy_probe"] = {"items": [2]}
	_check(Catalog.stage("stage_01") == stage_before and BattleBriefing.summarize("stage_01").stage == stage_before, "returned stage/timeline/stat edits cannot mutate Catalog or subsequent briefings")
	var ready := BattleBriefing.readiness("stage_01", roster, levels, modifiers, owned)
	ready.members[0].stats.special["copy_probe"] = {"items": [3]}
	ready.capabilities.frontline.append("unauthorized")
	ready.recommendations[0].present.append("unauthorized")
	var again := BattleBriefing.readiness("stage_01", roster, levels, modifiers, owned)
	_check(not again.members[0].stats.special.has("copy_probe") and not again.capabilities.frontline.has("unauthorized") and not again.recommendations[0].present.has("unauthorized"), "member stats/capability/recommendation arrays do not leak edits into later reads")
	_check({"roster": roster, "owned": owned, "levels": levels, "modifiers": modifiers} == input_before and Catalog.units() == units_before, "briefing reads preserve all caller inputs and unit recipes")

func _disk_state() -> Dictionary:
	var result: Dictionary = {}
	for filename: String in ["profile.json", "preferences.json"]:
		for suffix: String in ["", ".bak", ".tmp"]:
			var path := ISOLATION + "/" + filename + suffix
			result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ISOLATION))
	var profile := root.get_node("ProfileStore")
	var prefs := root.get_node("UserPrefs")
	profile.configure_path(ISOLATION + "/profile.json")
	prefs.configure_path(ISOLATION + "/preferences.json")
	var profile_before: Dictionary = profile.data.duplicate(true)
	var preferences_before: Dictionary = prefs._values.duplicate(true)
	var disk_before := _disk_state()
	var hashes: Dictionary = {}
	for key: String in INPUTS: hashes[key] = FileAccess.get_sha256(INPUTS[key])
	var scripts: Dictionary = {}
	for path: String in SCRIPT_INPUTS: scripts[path] = FileAccess.get_sha256("res://" + path)
	_test_stages()
	_test_wave_boundaries()
	_test_matrix()
	_test_readiness_rules()
	_test_copies()
	_check(profile.data == profile_before and prefs._values == preferences_before and _disk_state() == disk_before, "read-only briefing never writes profile/preferences or changes autoload state")
	for key: String in INPUTS: _check(FileAccess.get_sha256(INPUTS[key]) == hashes[key], "fixture preserves authored input bytes: " + key)
	for path: String in SCRIPT_INPUTS: _check(FileAccess.get_sha256("res://" + path) == scripts[path], "fixture preserves script input bytes: " + path)
	var gdd_version := ""
	for line: String in FileAccess.get_file_as_string(INPUTS.gdd_sha256).split("\n"):
		if line.begins_with("> 文档 v"):
			gdd_version = line.trim_prefix("> 文档 v").get_slice(" ", 0)
			break
	_check(gdd_version == "0.5.6", "briefing acceptance is attached to GDD 0.5.6")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "phase": "complete", "program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")), "gdd_version": gdd_version, "stage_count": stage_count, "matrix_cases": matrix_cases, "enemy_recipe_cases": enemy_recipe_cases, "boss_ids": boss_ids, "scripts_sha256": scripts, "isolation": ISOLATION, "visuals": false, "performance_verified": false, "scope": "Read-only briefing versus actual headless SiegeBattle waves and spawns; eight stages, enemy recipe boundaries, 108 player/level/research cases and owned squad recommendations. No rendered Spine, foreground input or performance acceptance."}
	for key: String in hashes: report[key] = hashes[key]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var file := FileAccess.open("res://reports/briefing_smoke.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BRIEFING_SMOKE " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
