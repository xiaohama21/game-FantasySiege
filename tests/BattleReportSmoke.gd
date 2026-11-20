extends SceneTree

# Boundary fixtures use the production scheduler and resolver; no campaign
# victory, reward, native rendering or foreground performance is claimed.
const DIRECTORY := "res://tests/.user/battle_report"
const INPUTS := {"project_sha256": "project.godot", "gdd_sha256": "docs/GAME_DESIGN.md", "briefings_sha256": "resources/briefings.json", "units_sha256": "resources/units.json", "stages_sha256": "resources/stages.json", "studies_sha256": "resources/studies.json"}
const SCRIPTS := ["scripts/combat/SiegeBattle.gd", "scripts/core/UnitStats.gd"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.0001

func make_battle(roster: Array, levels: Dictionary = {}, studies: Dictionary = {}) -> SiegeBattle:
	var battle := SiegeBattle.new()
	battle.auto_step = false
	battle.render_visuals = false
	root.add_child(battle)
	battle.start("stage_01", roster, levels, studies)
	battle._waves.clear()
	return battle

func dispose(battle: SiegeBattle) -> void:
	battle.stop()
	var report := battle.get_battle_report()
	check(report.members.is_empty() and report.roster.is_empty() and not bool(report.fixture), "stop removes this battle's members and fixture marker")
	for value: Variant in report.totals.values(): check(near(float(value), 0.0), "stop clears every report accumulator")
	battle.free()

func member(report: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in report.members:
		if str(row.id) == id: return row
	return {}

func resolve_attack(battle: SiegeBattle, attacker: Dictionary, target: Dictionary, heal: bool = false) -> void:
	var before := battle._hits.size()
	battle._begin_attack(attacker, target, heal)
	check(battle._hits.size() == before + 1, "production attack schedules exactly one pending hit")
	battle._elapsed += maxf(0.0, float(attacker.hit_delay)) + 0.001
	battle._resolve_hits()

func zero_totals(report: Dictionary, label: String) -> void:
	for value: Variant in report.totals.values(): check(near(float(value), 0.0), label + ": zero initial accumulator")

func test_initial_and_actions() -> void:
	var levels := {"iron_guard": 3}
	var studies := {"iron_guard": Catalog.study_routes("iron_guard")[0].modifiers.duplicate(true)}
	var roster: Array = ["iron_guard", "rune_medic"]
	var battle := make_battle(roster, levels, studies)
	var initial := battle.get_battle_report()
	check(initial.roster == roster and initial.members.size() == 2 and str(initial.outcome) == "running", "report includes the actual opening roster, including zero-summon members")
	zero_totals(initial, "new battle")
	levels.iron_guard = 20
	studies.iron_guard.hp_mult = 99.0
	roster.clear()
	check(int(battle.get_battle_report().levels.iron_guard) == 3 and battle.get_battle_report().roster.size() == 2, "opening level, roster and study input are deep-copied")
	var copy := battle.get_battle_report()
	copy.members[0].damage = 9999.0
	copy.levels.iron_guard = 20
	copy.study_modifiers.iron_guard.hp_mult = 100.0
	check(battle.get_battle_report() == initial, "read reports cannot mutate live accumulators or nested opening snapshots")
	check(not battle.try_summon("missing") and not battle.try_pulse(), "unavailable summon and enemy-free pulse are rejected")
	check(battle.get_battle_report() == initial, "rejected actions do not create report contribution or energy spend")
	var energy := float(battle._energy)
	check(battle.try_summon("iron_guard"), "actual affordable summon succeeds")
	var report := battle.get_battle_report()
	check(int(report.totals.summons) == 1 and int(member(report, "iron_guard").summons) == 1, "successful instance is counted once for its actual hero")
	check(near(float(report.totals.energy_spent), energy - float(battle._energy)), "summon energy spend equals actual energy deduction")
	check(not battle.try_summon("iron_guard"), "cooldown rejects immediate repeated summon")
	check(battle.get_battle_report() == report, "rejected repeat does not change report")
	battle._energy = 0.0
	check(not battle.try_summon("rune_medic"), "insufficient energy rejects another hero")
	check(battle.get_battle_report() == report, "failed alternate summon is not counted")
	dispose(battle)

func test_damage_and_overkill() -> void:
	var battle := make_battle(["zhaoyun"])
	var hero := battle._spawn("zhaoyun", 1)
	var enemy := battle._spawn("obsidian_guard", -1)
	var event_amounts: Array[float] = []
	battle.combat_event.connect(func(kind: String, _where: Vector2, amount: float, team: int):
		if kind == "hit" and team == 1: event_amounts.append(amount))
	var before := float(enemy.hp)
	resolve_attack(battle, hero, enemy)
	var effective := before - float(enemy.hp)
	var report := battle.get_battle_report()
	check(effective > 0.0 and near(float(report.totals.damage), effective), "ordinary attack report uses actual armor-resolved HP loss")
	check(near(float(member(report, "zhaoyun").damage), effective) and near(float(report.totals.healing), 0), "damage belongs to the actual attacker and not healing")
	check(near(float(report.totals.damage_taken), 0.0), "enemy damage received is not counted as player damage taken")
	enemy.hp = 3.0
	var old_damage := float(report.totals.damage)
	resolve_attack(battle, hero, enemy)
	report = battle.get_battle_report()
	check(not bool(enemy.alive) and near(float(report.totals.damage) - old_damage, 3.0), "overkill only records the remaining three HP")
	check(not event_amounts.is_empty() and event_amounts.back() > 3.0, "original combat_event retains resolved hit amount instead of changing to report-only effective damage")
	var before_dead: Dictionary = report.totals.duplicate(true)
	check(near(battle._damage_unit(enemy, 1000.0, "true", 1), 0.0), "original dead-target damage return remains zero")
	resolve_attack(battle, hero, enemy)
	check(battle.get_battle_report().totals == before_dead, "further attacks against dead targets add no contribution")
	dispose(battle)

func test_area_and_healing() -> void:
	var battle := make_battle(["guanyu", "rune_medic", "iron_guard"])
	var hero := battle._spawn("guanyu", 1)
	var one := battle._spawn("riftling", -1)
	var two := battle._spawn("riftling", -1)
	var distant := battle._spawn("riftling", -1)
	one.x = 500.0
	two.x = 510.0
	distant.x = 1200.0
	one.hp = 7.0
	two.hp = 11.0
	var untouched := float(distant.hp)
	resolve_attack(battle, hero, one)
	var report := battle.get_battle_report()
	check(not bool(one.alive) and not bool(two.alive) and near(float(distant.hp), untouched), "actual area attack affects nearby victims and leaves distant enemy untouched")
	check(near(float(report.totals.damage), 18.0) and near(float(member(report, "guanyu").damage), 18.0), "area damage sums actual HP loss of each victim for one attacker")
	var medic := battle._spawn("rune_medic", 1)
	var ally := battle._spawn("iron_guard", 1)
	ally.hp = float(ally.max_hp) - 3.0
	var hp_before := float(ally.hp)
	resolve_attack(battle, medic, ally, true)
	report = battle.get_battle_report()
	check(near(float(report.totals.healing), float(ally.hp) - hp_before) and near(float(report.totals.healing), 3.0), "healing counts only actual restored HP")
	check(near(float(member(report, "rune_medic").healing), 3.0) and near(float(member(report, "rune_medic").damage), 0.0), "effective healing belongs to healer and does not become offensive damage")
	var totals: Dictionary = report.totals.duplicate(true)
	resolve_attack(battle, medic, ally, true)
	check(battle.get_battle_report().totals == totals, "healing a full target adds no over-heal contribution")
	dispose(battle)

func test_received_damage_and_death() -> void:
	var battle := make_battle(["iron_guard"])
	var ally := battle._spawn("iron_guard", 1)
	var enemy := battle._spawn("riftling", -1)
	ally.hp = 1.0
	resolve_attack(battle, enemy, ally)
	var report := battle.get_battle_report()
	check(not bool(ally.alive) and int(report.totals.fallen) == 1 and int(member(report, "iron_guard").fallen) == 1, "one fallen instance is recorded once for its hero")
	check(near(float(report.totals.damage_taken), 1.0) and near(float(member(report, "iron_guard").damage_taken), 1.0), "received damage excludes overkill and belongs to the actual defender")
	check(near(float(report.totals.damage), 0.0), "enemy attacks never count as friendly offensive contribution")
	var totals: Dictionary = report.totals.duplicate(true)
	battle._damage_unit(ally, 50.0, "true", -1)
	battle._decay_corpses(5.0)
	check(battle.get_battle_report().totals == totals, "dead-target repeat and corpse cleanup do not create another death")
	dispose(battle)

func test_pulse() -> void:
	var battle := make_battle(["iron_guard"])
	var ally := battle._spawn("iron_guard", 1)
	var one := battle._spawn("obsidian_guard", -1, {"hp_mult": 10.0})
	var two := battle._spawn("obsidian_guard", -1, {"hp_mult": 10.0})
	one.x = 600.0
	two.x = 620.0
	battle._begin_attack(one, ally, false)
	battle._hits.append(battle._hits.back().duplicate(true))
	var health := float(one.hp) + float(two.hp)
	var ally_hp := float(ally.hp)
	var energy := float(battle._energy)
	check(battle.try_pulse(), "actual pulse with valid enemies succeeds")
	var report := battle.get_battle_report()
	var lost := health - float(one.hp) - float(two.hp)
	check(int(report.totals.pulse_uses) == 1 and int(report.totals.pulse_targets) == 2, "one pulse records its actual affected enemies")
	check(int(report.totals.pulse_interrupts) == 1, "two pending entries from one attacking enemy count as one actual interrupt")
	check(near(float(report.totals.pulse_damage), lost) and near(float(report.totals.damage), lost), "pulse effective damage contributes to friendly totals and its separate channel")
	check(near(float(member(report, "iron_guard").damage), 0.0), "pulse is not attributed to the nearby hero")
	check(near(float(report.totals.energy_spent), energy - float(battle._energy)), "pulse spend equals actual deduction")
	check(battle._hits.is_empty(), "pulse removes the actual pending enemy hits")
	check(not battle.try_pulse() and battle.get_battle_report() == report, "rejected cooldown pulse changes no count, damage or spend")
	battle._elapsed += 5.0
	battle._resolve_hits()
	check(near(float(ally.hp), ally_hp), "interrupted attack cannot later damage the hero")
	dispose(battle)

func test_base_finish_and_reset() -> void:
	var battle := make_battle(["rivet_gunner"], {"rivet_gunner": 3}, {"rivet_gunner": Catalog.study_modifiers("rivet_gunner", "siege")})
	var hero := battle._spawn("rivet_gunner", 1)
	var observed: Array[Dictionary] = []
	battle.battle_finished.connect(func(_victory: bool): observed.append(battle.get_battle_report()))
	battle._enemy_hp = 9.0
	resolve_attack(battle, hero, {"base": true, "uid": 0, "team": -1, "x": battle.enemy_x})
	var report := battle.get_battle_report()
	check(str(report.outcome) == "victory" and near(float(report.totals.base_damage), 9.0), "attack on a low-life base records effective siege damage and actual victory")
	check(near(float(member(report, "rivet_gunner").base_damage), 9.0) and near(float(report.totals.damage), 0.0), "base damage belongs to gunner and is separate from unit damage")
	check(observed.size() == 1 and observed[0] == report, "battle_finished observers see the already frozen complete report")
	var copy := battle.get_battle_report()
	copy.members[0].base_damage = 999.0
	copy.totals.base_damage = 999.0
	battle.advance(3.0)
	battle._decay_corpses(5.0)
	check(battle.get_battle_report() == report, "returned-copy edits, post-finish advance and corpse decay cannot mutate frozen report")
	battle.start("stage_01", ["iron_guard"])
	var next := battle.get_battle_report()
	check(str(next.outcome) == "running" and next.members.size() == 1 and next.roster == ["iron_guard"], "new start replaces previous victory and roster")
	zero_totals(next, "restarted battle")
	dispose(battle)

func test_time_and_fixture() -> void:
	var one := make_battle(["iron_guard"])
	var two := make_battle(["iron_guard"])
	one.try_summon("iron_guard")
	two.try_summon("iron_guard")
	var elapsed := float(one.get_battle_report().elapsed)
	one._process(5.0)
	check(near(float(one.get_battle_report().elapsed), elapsed), "externally controlled battle does not advance merely from _process")
	one.advance(1.0)
	two.advance(0.5 * 2.0)
	check(near(float(one.get_battle_report().elapsed), float(two.get_battle_report().elapsed)) and one.get_battle_report().totals == two.get_battle_report().totals, "equivalent one-times and two-times logical time retain the same report")
	check(one.seed_performance_units(4), "real performance seeding API accepts a valid fixture")
	check(bool(one.get_battle_report().fixture), "performance-seeded report is explicitly marked as a fixture")
	check(near(float(one.get_battle_report().totals.energy_spent), 0.0), "performance seed does not fabricate paid summon energy")
	dispose(one)
	dispose(two)
	var empty := SiegeBattle.new()
	empty.render_visuals = false
	empty.auto_step = false
	root.add_child(empty)
	empty.start("stage_01", [])
	var iterations := 0
	while str(empty.get_snapshot().outcome) == "running" and iterations < 1000:
		empty.advance(0.5)
		iterations += 1
	var report := empty.get_battle_report()
	check(str(report.outcome) == "defeat" and report.members.is_empty(), "natural no-army stage ends in defeat with no invented contributors")
	check(int(report.totals.summons) == 0 and near(float(report.totals.damage), 0.0) and near(float(report.totals.healing), 0.0), "empty-army defeat keeps friendly contribution at zero")
	dispose(empty)

func input_state() -> Dictionary:
	var values: Dictionary = {}
	for key: String in INPUTS: values[key] = FileAccess.get_sha256("res://" + str(INPUTS[key]))
	var scripts: Dictionary = {}
	for path: String in SCRIPTS: scripts[path] = FileAccess.get_sha256("res://" + path)
	values.scripts_sha256 = scripts
	return values

func disk_state() -> Dictionary:
	var values: Dictionary = {}
	for file: String in ["profile.json", "preferences.json"]:
		for suffix: String in ["", ".bak", ".tmp"]:
			var path := DIRECTORY + "/" + file + suffix
			values[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return values

func run() -> void:
	check(DisplayServer.get_name() == "headless", "battle report suite stays headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var profile = root.get_node("ProfileStore")
	profile.configure_path(DIRECTORY + "/profile.json")
	profile.load_profile()
	var prefs = root.get_node("UserPrefs")
	prefs.configure_path(DIRECTORY + "/preferences.json")
	var before := input_state()
	var files_before := disk_state()
	var profile_before: Dictionary = profile.data.duplicate(true)
	test_initial_and_actions()
	test_damage_and_overkill()
	test_area_and_healing()
	test_received_damage_and_death()
	test_pulse()
	test_base_finish_and_reset()
	test_time_and_fixture()
	check(input_state() == before, "battle report fixtures never rewrite production scripts, design or recipes")
	check(disk_state() == files_before and profile.data == profile_before, "report accumulation never writes isolated saves or modifies profile data")
	await root.get_node("GameAudio").shutdown()
	var gdd_version := ""
	for line: String in FileAccess.get_file_as_string("res://docs/GAME_DESIGN.md").split("\n"):
		if line.begins_with("> 文档 v"):
			gdd_version = line.trim_prefix("> 文档 v").split(" · ")[0]
			break
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "phase": "complete", "program_version": str(ProjectSettings.get_setting("application/config/version")), "gdd_version": gdd_version, "scope": "Headless production hit-resolver boundary fixtures, natural empty-army defeat, frozen report and no save writes; no native graphics, foreground input, natural paid campaign or performance claim.", "isolation": DIRECTORY}
	report.merge(before, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var file := FileAccess.open("res://reports/battle_report_smoke.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BATTLE_REPORT_SMOKE " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
