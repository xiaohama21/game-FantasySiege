extends SceneTree

# Actual Main victories and defeats use regular summons and fixed-step combat.
# Save-error and future-schema files are explicit isolated boundary fixtures.
const DIRECTORY := "res://tests/.user/result_ui"
const PROFILE_PATH := DIRECTORY + "/profile.json"
const PREFERENCES_PATH := DIRECTORY + "/preferences.json"
const INPUTS := {"project_sha256": "project.godot", "gdd_sha256": "docs/GAME_DESIGN.md", "briefings_sha256": "resources/briefings.json", "units_sha256": "resources/units.json", "stages_sha256": "resources/stages.json", "studies_sha256": "resources/studies.json"}
const SCRIPTS := ["scripts/combat/SiegeBattle.gd", "scripts/core/UnitStats.gd", "scripts/ui/Main.gd", "scripts/ui/StatBadge.gd"]
var app
var profile
var checks := 0
var failures: Array[String] = []
var victories := 0
var defeats := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func node_named(name: String) -> Node:
	return app.screen.find_child(name, true, false)

func press(name: String) -> void:
	var button := node_named(name)
	check(button is Button, "actual result navigation exists: " + name)
	if button is Button: button.pressed.emit()

func labels_contain(value: String) -> bool:
	for label: Node in app.screen.find_children("*", "Label", true, false):
		if value in str(label.text): return true
	return false

func disk_state(include_preferences: bool = true) -> Dictionary:
	var state: Dictionary = {}
	var files: Array[String] = [PROFILE_PATH]
	if include_preferences: files.append(PREFERENCES_PATH)
	for file: String in files:
		for suffix: String in ["", ".bak", ".tmp"]:
			var path := file + suffix
			state[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return state

func input_state() -> Dictionary:
	var state: Dictionary = {}
	for key: String in INPUTS: state[key] = FileAccess.get_sha256("res://" + str(INPUTS[key]))
	var scripts: Dictionary = {}
	for path: String in SCRIPTS: scripts[path] = FileAccess.get_sha256("res://" + path)
	state.scripts_sha256 = scripts
	return state

func prepare(stage: String = "stage_01") -> void:
	app.start_stage(stage)
	check(is_instance_valid(app.battle) and app.active_stage == stage, "actual Main starts the selected report battle")
	if is_instance_valid(app.battle):
		app.battle.render_visuals = false
		app.battle.auto_step = false
		app.battle.set_process(false)
	app.set_process(false)

func summon_available() -> void:
	var counts: Dictionary = {}
	var frontline := 0
	var army := 0
	for actor: Dictionary in app.battle.units:
		if not bool(actor.alive) or int(actor.team) != 1: continue
		counts[actor.id] = int(counts.get(actor.id, 0)) + 1
		army += 1
		if float(actor.range) < 100.0: frontline += 1
	var choices: Array[String] = []
	if frontline < 2: choices.append("iron_guard")
	if army >= 4 and int(counts.get("rune_medic", 0)) < 1: choices.append("rune_medic")
	if int(counts.get("ember_archer", 0)) < 3: choices.append("ember_archer")
	if int(counts.get("zhugeliang", 0)) < 2: choices.append("zhugeliang")
	if frontline < 4: choices.append("guanyu")
	choices.append_array(["lubu", "zhaoyun", "diaochan"])
	var snapshot: Dictionary = app.battle.get_snapshot()
	if int(snapshot.active_count) >= SiegeBattle.MAX_UNITS: return
	for id: String in choices:
		if not app.battle._roster.has(id): continue
		if float(snapshot.cooldowns.get(id, 0)) > SiegeBattle.READY_EPSILON: continue
		if float(snapshot.energy) + SiegeBattle.READY_EPSILON < float(Catalog.unit(id).get("cost", 0)): continue
		app._summon(id)
		return

func play_to_result(summon: bool) -> void:
	var steps := 0
	while is_instance_valid(app.battle) and str(app.battle.get_snapshot().outcome) == "running" and steps < 1200:
		if summon:
			summon_available()
			var snapshot: Dictionary = app.battle.get_snapshot()
			if int(snapshot.active_count) >= 6 and float(snapshot.energy) >= SiegeBattle.PULSE_COST and float(snapshot.pulse_cooldown) <= SiegeBattle.READY_EPSILON:
				var enemy_exists := false
				for actor: Dictionary in app.battle.units:
					if bool(actor.alive) and int(actor.team) == -1: enemy_exists = true; break
				if enemy_exists: app._pulse()
		app._process(0.5)
		steps += 1
	check(is_instance_valid(app.result_panel) and is_instance_valid(app.battle) and str(app.battle.get_snapshot().outcome) != "running", "regular combat reaches actual Main result within bounded logical time")
	if not is_instance_valid(app.battle): return
	if str(app.battle.get_snapshot().outcome) == "victory": victories += 1
	else: defeats += 1

func assert_report_visible() -> void:
	check(node_named("ResultReport") != null and node_named("ResultReward") != null, "result separates actual report from reward/save state")
	check(app.result_report == app.battle.get_battle_report(), "Main result uses the actual complete frozen battle report")
	var report: Dictionary = app.result_report
	for key: String in ["damage", "healing", "base_damage"]:
		var widget := node_named("Stat_report_" + key)
		check(widget != null, "visible total contribution field exists: " + key)
		if widget == null: continue
		var value: Node = widget.find_child("Value", true, false)
		var caption: Node = widget.find_child("Caption", true, false)
		var icon: Node = widget.find_child("Icon", true, false)
		check(value is Label and value.text == "%.0f" % float(report.totals[key]), "visible total value matches actual effective contribution: " + key)
		check(caption is Label and not str(caption.text).is_empty(), "contribution icon retains necessary Chinese caption: " + key)
		check(icon is TextureRect and icon.texture != null and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "contribution SVG loads and cannot swallow input: " + key)
	for member: Dictionary in report.members:
		var row := node_named("ResultMember_" + str(member.id))
		check(row != null, "actual opening-roster report row exists: " + str(member.id))
		if row == null: continue
		for pair: Array in [["DamageValue", "damage"], ["HealingValue", "healing"], ["BaseDamageValue", "base_damage"]]:
			var value: Node = row.find_child(str(pair[0]), true, false)
			check(value is Label and value.text == "%.0f" % float(member[str(pair[1])]), "visible hero contribution matches frozen report: " + str(member.id) + "/" + str(pair[1]))
	check(labels_contain("脉冲") and labels_contain("有效"), "report explains pulse and effective-statistics scope in Chinese")

func test_pause_and_speed() -> void:
	prepare()
	var before: Dictionary = app.battle.get_battle_report()
	app._toggle_pause()
	app._process(0.7)
	check(app.battle.get_battle_report() == before, "actual Main pause leaves report time and contribution unchanged")
	app._toggle_speed()
	app._process(0.7)
	check(app.speed == 2.0 and app.battle.get_battle_report() == before, "changing to 2x while paused advances neither report nor battle")
	app._toggle_pause()
	app._process(0.25)
	check(absf(float(app.battle.get_battle_report().elapsed) - float(before.elapsed) - 0.5) < 0.0001, "resumed 2x report uses actual logical time")
	check(app._stop_battle(), "pause/speed fixture stops without reward or persistence")
	app.show_home()

func test_saved_victory() -> void:
	prepare()
	play_to_result(true)
	check(bool(app.result_victory) and bool(app.result_saved) and app.run_token.is_empty(), "real first victory commits reward before result navigation")
	assert_report_visible()
	var report: Dictionary = app.result_report.duplicate(true)
	var award: Dictionary = app.result_award.duplicate(true)
	var data: Dictionary = profile.data.duplicate(true)
	var files := disk_state()
	var profile_files := disk_state(false)
	check(bool(award.get("first_clear", false)) and int(award.get("credits", 0)) == int(Catalog.stage("stage_01").rewards.credits) + int(Catalog.stage("stage_01").rewards.first_clear_credits), "first-clear reward uses the actual saved award")
	for repeat in 4: app._render_result()
	check(profile.data == data and disk_state() == files and app.result_report == report and app.result_award == award, "repeated result rendering grants no repeated reward and keeps the same battle")
	var last_award: Dictionary = profile.last_award.duplicate(true)
	profile.last_award.credits = 999999
	app._render_result()
	check(app.result_award == award and app.result_report == report, "result is based on its own saved award snapshot, not unrelated later last_award")
	profile.last_award = last_award
	var actions: Array = [node_named("ResultContinue"), node_named("ResultBriefing"), node_named("ResultSquad"), node_named("ResultHome")]
	app._open_settings()
	var modal_files := disk_state()
	for action: Node in actions:
		check(action is Button, "result action exists behind modal")
		if action is Button: action.pressed.emit()
	check(is_instance_valid(app.settings_panel) and app.active_stage == "stage_01" and is_instance_valid(app.result_panel), "settings modal rejects all underlying result navigation")
	check(disk_state() == modal_files and profile.data == data, "blocked modal result actions change no file or reward")
	check(app.settings_panel.close(), "result settings closes normally")
	check(disk_state(false) == profile_files, "settings closure leaves profile files unchanged")
	press("ResultContinue")
	check(app.active_stage == "stage_02" and is_instance_valid(app.battle) and not is_instance_valid(app.result_panel), "saved victory continues to the actually unlocked next stage")
	if is_instance_valid(app.battle): app.battle.render_visuals = false; app.battle.set_process(false)
	check(app._stop_battle(), "unfinished next-stage navigation stops without reward")
	app.show_home()
	check(profile.data == data, "continuing and leaving an unfinished next stage grants no reward")

func test_defeat_navigation() -> void:
	var data: Dictionary = profile.data.duplicate(true)
	var files := disk_state()
	prepare()
	play_to_result(false)
	check(not bool(app.result_victory) and app.run_token.is_empty(), "actual no-summon defeat has no pending reward token")
	assert_report_visible()
	check(int(app.result_report.totals.summons) == 0 and float(app.result_report.totals.damage) == 0.0, "actual no-summon defeat shows zero friendly contribution")
	app._render_result()
	check(profile.data == data and disk_state() == files, "defeat result rendering does not grant currency or write growth")
	press("ResultBriefing")
	check(app.tab == "敌情" and app.selected_briefing == "stage_01" and not is_instance_valid(app.battle), "defeat can open the correct enemy briefing for preparation")
	check(profile.data == data and disk_state() == files, "defeat briefing navigation preserves saved progress")

func test_failed_reward_and_recovery() -> void:
	prepare()
	var expected: Dictionary = profile.reward_preview("stage_01")
	var data: Dictionary = profile.data.duplicate(true)
	var files := disk_state()
	var credits := int(profile.credits())
	profile.save_path = DIRECTORY + "/missing/profile.json"
	play_to_result(true)
	check(bool(app.result_victory) and not bool(app.result_saved) and not app.run_token.is_empty(), "real victory with isolated write failure keeps reward pending")
	assert_report_visible()
	var report: Dictionary = app.result_report.duplicate(true)
	check(profile.data == data and disk_state() == files and labels_contain("保存"), "failed reward is clearly explained and leaves profile bytes/resource values unchanged")
	for name: String in ["ResultContinue", "ResultBriefing", "ResultSquad", "ResultHome"]:
		var action := node_named(name)
		check(action is Button and action.disabled, "unsaved victory blocks leaving action: " + name)
		if action is Button: action.pressed.emit()
	check(is_instance_valid(app.result_panel) and app.active_stage == "stage_01" and app.result_report == report and profile.data == data, "emitting disabled leaving signals cannot silently lose pending victory")
	for repeat in 3: app._render_result()
	check(profile.data == data and disk_state() == files and app.result_report == report, "reading an unsaved report does not retry or grant reward")
	profile.save_path = PROFILE_PATH
	press("ResultRetry")
	check(bool(app.result_saved) and app.run_token.is_empty() and is_instance_valid(app.result_panel), "successful explicit retry keeps the player at the same result")
	check(app.result_report == report and int(profile.credits()) == credits + int(expected.credits), "recovered result preserves battle contribution and grants actual reward once")
	var recovered: Dictionary = profile.data.duplicate(true)
	var recovered_files := disk_state()
	app._retry_reward()
	app._render_result()
	check(profile.data == recovered and disk_state() == recovered_files and app.result_report == report, "repeat retry/render cannot duplicate recovered reward")
	press("ResultSquad")
	check(app.tab == "编队" and not is_instance_valid(app.battle), "recovered victory can navigate to actual saved squad page")
	check(profile.data == recovered and disk_state() == recovered_files, "squad navigation does not modify restored reward")

func test_future_file_isolation() -> void:
	prepare()
	play_to_result(true)
	var report: Dictionary = app.result_report.duplicate(true)
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": SiegeProfile.SCHEMA + 1, "preserve": "future-result"}))
	file.close()
	var future_files := disk_state()
	profile.load_profile()
	check(not profile.can_modify(), "future schema is detected by existing profile protection")
	app._render_result()
	press("ResultContinue")
	check(app.active_stage == "stage_01" and is_instance_valid(app.result_panel), "future profile cannot enter a new stage through result navigation")
	check(disk_state() == future_files and app.result_report == report, "result rendering and blocked next-stage leave future bytes and report unchanged")
	press("ResultHome")
	check(not is_instance_valid(app.battle) and app.tab in ["远征", "英魂"], "read-only result can return to browse camp")
	check(disk_state() == future_files, "read-only home navigation preserves future profile and backups")

func test_gallery_values_and_modal() -> void:
	var files := disk_state()
	var profile_files := disk_state(false)
	var data: Dictionary = profile.data.duplicate(true)
	app.selected_visual = str(Catalog.unit("rune_medic").visual_id)
	app._gallery_category("heroes")
	var expected: Dictionary = app._hero_calculation("rune_medic")
	var damage := node_named("Stat_damage")
	var interval := node_named("Stat_attack_interval")
	var armor := node_named("Stat_magic_armor")
	check(damage != null and damage.find_child("Caption", true, false).text == "治疗" and damage.find_child("Value", true, false).text == "%.0f" % float(expected.special.amount), "gallery healer shows final effective healing amount with one clear Chinese caption")
	check(interval != null and interval.find_child("Caption", true, false).text == "攻击间隔" and interval.find_child("Value", true, false).text == "%.2fs" % float(expected.attack_interval), "gallery explicitly names its actual attack interval")
	check(armor != null and armor.find_child("Value", true, false).text == "%.0f" % float(expected.magic_armor), "gallery displays actual central magic resistance")
	var picker := node_named("GalleryPicker")
	var selected: String = app.selected_visual
	app._open_settings()
	var during_modal := disk_state()
	check(picker is OptionButton, "actual gallery picker exists")
	if picker is OptionButton: picker.item_selected.emit(0)
	check(app.selected_visual == selected and is_instance_valid(app.settings_panel), "top settings modal blocks the gallery picker signal")
	check(disk_state() == during_modal and profile.data == data, "blocked gallery picking writes no settings or profile")
	check(app.settings_panel.close(), "gallery settings closes normally")
	check(disk_state(false) == profile_files, "gallery settings closure preserves profile files")
	for id: String in ["obsidian_warden", "rail_colossus"]:
		app.selected_visual = str(Catalog.unit(id).visual_id)
		app._gallery_category("enemies")
		var special: Dictionary = UnitStats.calculate(Catalog.unit(id), 1).special
		var phase := node_named("GalleryPhase")
		check(phase != null and labels_contain(str(special.phase_name)) and labels_contain("半血"), "gallery names the actual boss phase and trigger: " + id)
		for pair: Array in [["伤害", "phase_damage_mult"], ["间隔", "phase_attack_mult"], ["移速", "phase_speed_mult"]]:
			check(labels_contain(str(pair[0]) + "×%.2f" % float(special[str(pair[1])])), "gallery shows the actual boss phase multiplier: " + id + "/" + str(pair[1]))
	check(profile.data == data and disk_state(false) == profile_files, "gallery reading preserves the profile and future-schema bytes")

func run() -> void:
	check(DisplayServer.get_name() == "headless", "result UI suite stays headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	for file: String in [PROFILE_PATH, PREFERENCES_PATH]:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(file + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(file + suffix))
	profile = root.get_node("ProfileStore")
	profile.configure_path(PROFILE_PATH)
	profile.load_profile()
	check(profile._commit(profile.data.duplicate(true)), "save fresh declared isolated profile")
	var prefs = root.get_node("UserPrefs")
	prefs.configure_path(PREFERENCES_PATH)
	prefs.set_value("master_volume", 0.0)
	prefs.set_value("tutorial_seen", true)
	check(prefs.flush(), "save silent isolated result preferences")
	var before := input_state()
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	await process_frame
	test_pause_and_speed()
	test_saved_victory()
	test_defeat_navigation()
	test_failed_reward_and_recovery()
	test_future_file_isolation()
	test_gallery_values_and_modal()
	check(victories == 3 and defeats == 1, "three real victories and one real no-summon defeat verified")
	check(input_state() == before, "result fixtures do not rewrite production code or recipes")
	check(app._stop_battle(), "result fixture releases any logical battle")
	app.queue_free()
	await process_frame
	await root.get_node("GameAudio").shutdown()
	var gdd_version := ""
	for line: String in FileAccess.get_file_as_string("res://docs/GAME_DESIGN.md").split("\n"):
		if line.begins_with("> 文档 v"):
			gdd_version = line.trim_prefix("> 文档 v").split(" · ")[0]
			break
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "phase": "complete", "program_version": str(ProjectSettings.get_setting("application/config/version")), "gdd_version": gdd_version, "victories": victories, "defeats": defeats, "scope": "Headless actual Main first-clear/revisit victories, no-summon defeat, visible effective contribution and reward save/retry/navigation with isolated files; no native rendering, foreground input or performance claim.", "isolation": DIRECTORY}
	report.merge(before, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var output := FileAccess.open("res://reports/result_ui_smoke.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("RESULT_UI_SMOKE " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
