extends SceneTree

# Actual Main bindings in a headless process with isolated save files.
const DIRECTORY := "res://tests/.user/briefing_ui"
const PROFILE_PATH := DIRECTORY + "/profile.json"
const PREFERENCES_PATH := DIRECTORY + "/preferences.json"
const INPUT_PATHS := ["project.godot", "docs/GAME_DESIGN.md", "resources/briefings.json", "resources/studies.json", "resources/units.json", "resources/stages.json", "scripts/core/BattleBriefing.gd", "scripts/core/UnitStats.gd", "scripts/combat/SiegeBattle.gd", "scripts/ui/Main.gd", "scripts/ui/StatBadge.gd"]
var app
var profile
var checks := 0
var failures: Array[String] = []
var stage_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func node_named(value: String) -> Node:
	return app.screen.find_child(value, true, false)

func press(value: String) -> void:
	var button := node_named(value)
	check(button != null, "actual Main control exists: " + value)
	if button != null: button.pressed.emit()

func labels_contain(value: String) -> bool:
	for label: Node in app.screen.find_children("*", "Label", true, false):
		if value in str(label.text): return true
	return false

func member_stats() -> Dictionary:
	var result: Dictionary = {}
	for label: Node in app.screen.find_children("*", "Label", true, false):
		if label.has_meta("briefing_member_id"):
			result[str(label.get_meta("briefing_member_id"))] = label.get_meta("unit_stats", {}).duplicate(true)
	return result

func disk_state(include_preferences: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var files: Array[String] = [PROFILE_PATH]
	if include_preferences: files.append(PREFERENCES_PATH)
	for file: String in files:
		for suffix: String in ["", ".bak", ".tmp"]:
			var path := file + suffix
			result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return result

func input_state() -> Dictionary:
	var result: Dictionary = {}
	for path: String in INPUT_PATHS: result[path] = FileAccess.get_sha256("res://" + path)
	return result

func assert_badge(grid: Node, key: String, value: String, caption: String, icon_id: String) -> void:
	var badge := grid.find_child("Stat_" + key, true, false)
	check(badge is Control, "actual briefing stat badge exists: " + key)
	if not badge is Control: return
	var text := badge.find_child("Value", true, false)
	var title := badge.find_child("Caption", true, false)
	var icon := badge.find_child("Icon", true, false)
	check(text is Label and title is Label and text.is_visible_in_tree() and title.is_visible_in_tree() and text.text == value and title.text == caption, "visible briefing value and Chinese caption match central recipe: " + key)
	check(icon is TextureRect and icon.texture != null and icon.texture.resource_path == "res://assets/ui/icons/" + icon_id + ".svg", "briefing badge loads the actual shared SVG texture: " + key)
	if icon is TextureRect and text is Label and title is Label:
		check(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE and text.mouse_filter == Control.MOUSE_FILTER_IGNORE and title.mouse_filter == Control.MOUSE_FILTER_IGNORE, "briefing stat badge and SVG leave mouse input available: " + key)

func assert_variant_badges(label: Node, stats: Dictionary) -> void:
	# Each metadata label is immediately followed by its own six-value grid.
	var children := label.get_parent().get_children()
	var index := children.find(label) + 1
	check(index > 0 and index < children.size() and children[index] is GridContainer, "each enemy wave recipe has its own visible stat grid")
	if index <= 0 or index >= children.size() or not children[index] is GridContainer: return
	var grid: Node = children[index]
	var kind: String = {"physical": "物理", "magic": "魔法", "true": "真实"}.get(str(stats.damage_type), "物理")
	assert_badge(grid, "hp", "%.0f" % float(stats.hp), "生命", "heart")
	assert_badge(grid, "damage", "%.0f" % float(stats.damage), kind + "伤害", "orb" if stats.damage_type == "magic" else "sword")
	assert_badge(grid, "armor", "%.0f" % float(stats.armor), "护甲", "shield")
	assert_badge(grid, "magic_armor", "%.0f" % float(stats.magic_armor), "魔抗", "ward")
	assert_badge(grid, "range", "%.0f" % float(stats.range), "射程", "range")
	assert_badge(grid, "hit_delay", "%.2fs" % float(stats.hit_delay), "前摇", "clock")

func assert_svg_icons() -> void:
	var icons: Dictionary = {}
	for node: Node in app.screen.find_children("*", "TextureRect", true, false):
		if node.texture == null or not str(node.texture.resource_path).begins_with("res://assets/ui/icons/"): continue
		icons[str(node.texture.resource_path)] = true
		check(str(node.texture.resource_path).ends_with(".svg") and node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "real shared SVG icon loads and does not consume mouse input")
	check(icons.size() >= 6, "actual briefing renders at least six distinct shared SVG meanings")

func assert_displayed(stage_id: String) -> void:
	var summary := BattleBriefing.summarize(stage_id)
	var expected_variants := 0
	for enemy: Dictionary in summary.enemies: expected_variants += enemy.variants.size()
	var displayed_variants := 0
	for label: Node in app.screen.find_children("*", "Label", true, false):
		if not label.has_meta("briefing_enemy_id"): continue
		var id := str(label.get_meta("briefing_enemy_id"))
		var modifiers: Dictionary = label.get_meta("wave_modifiers", {})
		var actual: Dictionary = label.get_meta("unit_stats", {})
		var expected := UnitStats.calculate(Catalog.unit(id), 1, modifiers)
		check(actual == expected, "enemy displayed values use central wave stats: " + stage_id + "/" + id)
		assert_variant_badges(label, expected)
		var found := false
		for enemy: Dictionary in summary.enemies:
			if str(enemy.id) != id: continue
			for variant: Dictionary in enemy.variants:
				if float(variant.hp_mult) == float(modifiers.get("hp_mult", 0)) and float(variant.damage_mult) == float(modifiers.get("damage_mult", -1)) and variant.stats == actual: found = true
		check(found, "displayed variant belongs to this stage's actual waves: " + stage_id + "/" + id)
		displayed_variants += 1
	check(displayed_variants == expected_variants, "all stage enemy variants appear: " + stage_id)
	var readiness := BattleBriefing.readiness(stage_id, profile.data.roster, profile.data.levels, profile.study_modifiers_snapshot(), profile.data.owned)
	var displayed := member_stats()
	check(displayed.size() == readiness.members.size(), "displayed saved roster count matches readiness: " + stage_id)
	for member: Dictionary in readiness.members:
		check(displayed.get(str(member.id), {}) == member.stats, "displayed squad uses central saved level and route: " + str(member.id))
	check(labels_contain("计划出场") and labels_contain("上限"), "planned-time and population-delay explanation is always visible")
	check(labels_contain("可选提醒") and labels_contain("脉冲"), "optional advice and pulse rule are always visible")
	assert_svg_icons()

func run() -> void:
	check(DisplayServer.get_name() == "headless", "briefing UI fixture must remain headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	for file: String in [PROFILE_PATH, PREFERENCES_PATH]:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(file + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(file + suffix))
	profile = root.get_node("ProfileStore")
	profile.configure_path(PROFILE_PATH)
	profile.load_profile()
	check(profile._commit(profile.data.duplicate(true)), "save initial isolated briefing profile")
	var prefs = root.get_node("UserPrefs")
	prefs.configure_path(PREFERENCES_PATH)
	prefs.set_value("tutorial_seen", true)
	prefs.set_value("master_volume", 0.0)
	check(prefs.flush(), "save silent isolated briefing preferences")
	var source_before := input_state()
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	await process_frame
	var saved_before := disk_state()
	var profile_saved_before := disk_state(false)
	var data_before: Dictionary = profile.data.duplicate(true)
	var prefs_before: Dictionary = prefs._values.duplicate(true)
	var stages := Catalog.stages().duplicate(true)
	check(stages.size() == 8, "all eight current stages are covered")
	for stage: Dictionary in stages:
		var id := str(stage.id)
		var chapter := int(stage.get("chapter", 1))
		app._select_chapter(chapter)
		var entry := node_named("Briefing_" + id)
		check(entry != null and not entry.disabled, "campaign enemy-information entry is browsable: " + id)
		if entry != null: entry.pressed.emit()
		check(app.tab == "敌情" and app.selected_briefing == id and app.selected_chapter == chapter, "entry opens the correct stage and chapter: " + id)
		check(node_named("BriefingEnemies") is ScrollContainer and node_named("BriefingPreparation") is ScrollContainer, "both actual briefing sections have scrolling containers")
		assert_displayed(id)
		var start := node_named("BriefingStart")
		check(start != null and start.disabled == (not profile.stage_unlocked(id)), "start permission follows the actual stage unlock: " + id)
		if not profile.stage_unlocked(id):
			press("BriefingStart")
			check(not is_instance_valid(app.battle) and app.tab == "敌情", "emitted locked start cannot enter battle: " + id)
		press("BriefingReturn")
		check(app.tab == "远征" and app.selected_chapter == chapter, "return preserves the selected chapter: " + id)
		stage_count += 1
	check(profile.data == data_before and prefs._values == prefs_before and disk_state() == saved_before, "browsing all eight stages leaves profile, preferences and backup/temp files unchanged")
	# Signals are emitted on existing underlying controls to exercise Main's modal wrapper.
	app._select_chapter(1)
	var campaign_entry := node_named("Briefing_stage_01")
	var modal_disk := disk_state()
	app._open_settings()
	if campaign_entry != null: campaign_entry.pressed.emit()
	check(app.tab == "远征" and is_instance_valid(app.settings_panel), "settings modal blocks underlying campaign briefing entry")
	check(disk_state() == modal_disk and profile.data == data_before, "blocked campaign briefing action does not write or mutate profile/preferences")
	check(app.settings_panel.close(), "campaign settings modal closes")
	check(disk_state(false) == profile_saved_before and prefs._values == prefs_before, "normal settings close preserves profile files and preference values")
	app._open_briefing("stage_01")
	var controls: Array = [node_named("BriefingStart"), node_named("BriefingReturn"), node_named("BriefingSquad")]
	modal_disk = disk_state()
	app._open_settings()
	for control: Node in controls:
		check(control != null, "underlying briefing action exists")
		if control != null: control.pressed.emit()
	check(app.tab == "敌情" and not is_instance_valid(app.battle) and is_instance_valid(app.settings_panel), "settings modal blocks briefing start, return and squad actions")
	check(disk_state() == modal_disk and profile.data == data_before and prefs._values == prefs_before, "blocked briefing actions do not write or mutate profile/preferences")
	check(app.settings_panel.close(), "briefing settings modal closes")
	check(disk_state(false) == profile_saved_before and profile.data == data_before and prefs._values == prefs_before, "normal settings close preserves profile files/data and preference values")
	press("BriefingSquad")
	check(app.tab == "编队", "briefing squad button opens actual squad page")
	# Declared setup enables the existing saved training and study transactions.
	var candidate: Dictionary = profile.data.duplicate(true)
	candidate.cleared = ["stage_01", "stage_02", "stage_03", "stage_04"]
	candidate.credits = 5000
	candidate.levels.guanyu = 3
	check(profile._commit(candidate), "save declared eligible isolated progression fixture")
	check(profile.set_roster(["guanyu", "rune_medic"]), "save first actual roster change")
	app._open_briefing("stage_05")
	var base_stats := member_stats()
	check(base_stats.keys().size() == 2 and base_stats.has("guanyu") and base_stats.has("rune_medic"), "reopened briefing reflects saved two-member roster")
	check(profile.unlock_study("guanyu") and profile.set_study_route("guanyu", "guard"), "save actual study unlock and guard route")
	check(profile.upgrade("guanyu"), "save actual hero training transaction")
	check(profile.set_roster(["guanyu", "zhaoyun"]), "save second actual roster change")
	app._open_briefing("stage_05")
	var studied_stats := member_stats()
	check(studied_stats.has("guanyu") and studied_stats.has("zhaoyun") and not studied_stats.has("rune_medic"), "reopened briefing reflects the latest successfully saved roster")
	var expected := UnitStats.calculate(Catalog.unit("guanyu"), profile.level("guanyu"), profile.study_modifiers_snapshot().get("guanyu", {}))
	check(studied_stats.get("guanyu", {}) == expected and base_stats.get("guanyu", {}) != expected, "saved training and guard route update displayed central stats")
	check(labels_contain(str(Catalog.study_route("guanyu", "guard").name)), "saved guard study name is visible")
	assert_displayed("stage_05")
	var stored_snapshot: Dictionary = profile.data.duplicate(true)
	var stored_modifiers: Dictionary = profile.study_modifiers_snapshot()
	var stored_disk := disk_state()
	press("BriefingStart")
	check(is_instance_valid(app.battle) and app.active_stage == "stage_05", "valid briefing start opens the selected actual logical battle")
	if is_instance_valid(app.battle):
		app.battle.render_visuals = false
		app.battle.set_process(false)
		check(app.battle._roster == stored_snapshot.roster and app.battle._levels == stored_snapshot.levels and app.battle._study_modifiers == stored_modifiers, "battle receives the same saved roster, levels and study snapshot")
		check(app.battle._waves == BattleBriefing.summarize("stage_05").timeline, "opened battle uses the same planned wave order")
		app.battle._energy = app.battle._capacity
		check(app.battle.try_summon("guanyu"), "actual logical battle summons the prepared hero")
		if not app.battle.units.is_empty():
			var actor: Dictionary = app.battle.units[0]
			check(actor.stats == expected.stats and actor.special == expected.special and actor.level == expected.level, "actual summoned attributes, skill and level match preparation")
			for key: String in ["damage", "armor", "magic_armor", "range", "attack_interval", "hit_delay", "aoe_radius", "heal_multiplier"]:
				check(is_equal_approx(float(actor[key]), float(expected[key])), "actual summoned final field matches displayed central preparation: " + key)
			check(is_equal_approx(float(actor.max_hp), float(expected.hp)), "actual summoned maximum life matches displayed preparation")
			check(is_equal_approx(float(actor.speed), float(expected.speed) * float(app.battle._move_speed_multiplier)), "actual summoned movement uses central speed and stage multiplier")
		profile.data.levels.guanyu = 20
		profile.data.study_routes.guanyu = "sweep"
		profile.data.roster = ["lubu"]
		check(app.battle._roster == stored_snapshot.roster and app.battle._levels == stored_snapshot.levels and app.battle._study_modifiers == stored_modifiers, "battle snapshots do not alias later profile changes")
		profile.data = stored_snapshot.duplicate(true)
	check(app._stop_battle(), "briefing UI fixture stops logical battle cleanly")
	check(disk_state() == stored_disk, "starting and stopping battle does not grant rewards or rewrite saved preparation")
	app._open_briefing("missing_stage")
	check(app.tab == "远征" and not is_instance_valid(app.battle) and labels_contain("未找到该关卡的敌情"), "unknown briefing returns with visible explanation and no battle")
	check(disk_state() == stored_disk, "unknown stage handling does not write saves")
	# A future save is preserved byte for byte, while navigation remains available.
	var future := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	future.store_string(JSON.stringify({"schema": SiegeProfile.SCHEMA + 1, "preserve": "future-briefing"}))
	future.close()
	var future_disk := disk_state()
	profile.load_profile()
	app._open_briefing("stage_01")
	await process_frame
	check(not profile.can_modify() and node_named("BriefingStart").disabled, "future-schema briefing is browsable and cannot start")
	check(is_instance_valid(app.toast) and app.toast.visible and "仅可浏览" in app.toast.text, "future-schema browse protection is visibly explained")
	if is_instance_valid(app.toast):
		for name: String in ["BriefingStart", "BriefingReturn", "BriefingSquad"]:
			var button := node_named(name)
			check(button != null and not app.toast.get_global_rect().intersects(button.get_global_rect()), "future-schema toast does not cover briefing action: " + name)
	press("BriefingStart")
	check(not is_instance_valid(app.battle) and app.tab == "敌情", "emitted future-schema start cannot bypass read-only protection")
	press("BriefingSquad")
	check(app.tab == "编队", "future-schema user can browse squad without editing")
	app._open_briefing("stage_08")
	press("BriefingReturn")
	check(app.tab == "远征" and app.selected_chapter == 2, "future-schema return preserves chapter two")
	check(disk_state() == future_disk, "all future-schema briefing actions preserve profile/preferences bytes and backups")
	check(input_state() == source_before and Catalog.stages() == stages, "briefing fixture leaves source recipes, scripts and catalog unchanged")
	app.queue_free()
	await process_frame
	await root.get_node("GameAudio").shutdown()
	var scripts: Dictionary = {}
	for path: String in ["scripts/core/BattleBriefing.gd", "scripts/core/UnitStats.gd", "scripts/combat/SiegeBattle.gd", "scripts/ui/Main.gd", "scripts/ui/StatBadge.gd"]: scripts[path] = FileAccess.get_sha256("res://" + path)
	var gdd := FileAccess.get_file_as_string("res://docs/GAME_DESIGN.md")
	var gdd_version := ""
	for line: String in gdd.split("\n"):
		if line.begins_with("> 文档 v"):
			gdd_version = line.trim_prefix("> 文档 v").split(" · ")[0]
			break
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "stage_count": stage_count, "program_version": str(ProjectSettings.get_setting("application/config/version")), "project_sha256": source_before["project.godot"], "gdd_version": gdd_version, "gdd_sha256": source_before["docs/GAME_DESIGN.md"], "briefings_sha256": source_before["resources/briefings.json"], "studies_sha256": source_before["resources/studies.json"], "units_sha256": source_before["resources/units.json"], "stages_sha256": source_before["resources/stages.json"], "scripts_sha256": scripts, "isolation": DIRECTORY, "scope": "Headless actual Main eight-stage briefing bindings, central wave and saved preparation stats, isolated transactions, modal and future-schema protection, and logical battle snapshot. No OS input, native rendering, foreground or performance claim."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var report := FileAccess.open("res://reports/briefing_ui_smoke.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "\t"))
	report.close()
	print("BRIEFING_UI_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
