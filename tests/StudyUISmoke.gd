extends SceneTree

# Headless Main bindings and real profile transactions; no rendered/native or performance claim.
const DIRECTORY := "res://tests/.user/study_ui"
const PROFILE_PATH := DIRECTORY + "/profile.json"
var app
var profile
var checks := 0
var failures: Array[String] = []
var matrix_cases := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func node_named(value: String) -> Node:
	return app.screen.find_child(value, true, false)

func labels_contain(value: String) -> bool:
	for label: Node in app.screen.find_children("*", "Label", true, false):
		if value in str(label.text): return true
	return false

func displayed_stats(id: String) -> Dictionary:
	for panel: Node in app.screen.find_children("*", "Panel", true, false):
		if panel.get_meta("unit_id", "") == id: return panel.get_meta("unit_stats", {})
	return {}

func badge_matches(key: String, value: String, caption: String) -> bool:
	var badge := node_named("Stat_" + key)
	if not badge is Control: return false
	var text := badge.find_child("Value", true, false)
	var title := badge.find_child("Caption", true, false)
	var icon := badge.find_child("Icon", true, false)
	return text is Label and title is Label and icon is TextureRect and text.is_visible_in_tree() and title.is_visible_in_tree() and text.text == value and title.text == caption and icon.texture != null and icon.mouse_filter == Control.MOUSE_FILTER_IGNORE

func run() -> void:
	check(DisplayServer.get_name() == "headless", "Study UI fixture must remain headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	for file: String in ["profile.json", "preferences.json"]:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(DIRECTORY + "/" + file + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(DIRECTORY + "/" + file + suffix))
	profile = root.get_node("ProfileStore")
	profile.configure_path(PROFILE_PATH)
	profile.load_profile()
	var prefs = root.get_node("UserPrefs")
	prefs.configure_path(DIRECTORY + "/preferences.json")
	prefs.set_value("tutorial_seen", true)
	prefs.set_value("master_volume", 0.0)
	check(prefs.flush(), "isolated silent UI preferences save")
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.show_home("研修")
	check(app.tab == "研修" and node_named("StudyDetails") != null, "Main exposes dedicated study page")
	check(node_named("StudyUnlock").disabled and labels_contain("第四关首通"), "locked page shows conditions and blocks unlock")
	check(node_named("StudySelect_sweep").disabled and node_named("StudyRestore").disabled, "locked routes and base restore stay unavailable")
	app._select_study("spirit_beast")
	check(node_named("StudyUnlock").disabled and labels_contain("未契约"), "unowned study stays visible and unavailable")
	var candidate: Dictionary = profile.data.duplicate(true)
	candidate.cleared = ["stage_01", "stage_02", "stage_03", "stage_04"]
	candidate.credits = 2000
	candidate.levels.guanyu = 3
	check(profile._commit(candidate), "save eligible isolated study fixture")
	app._select_study("guanyu")
	check(not node_named("StudyUnlock").disabled, "eligible Main offers one-time unlock")
	node_named("StudyUnlock").pressed.emit()
	check(profile.credits() == 1820 and profile.study_unlocked("guanyu") and profile.study_route("guanyu") == "base", "UI unlock charges once and retains base")
	check(node_named("StudyUnlock").disabled and not node_named("StudySelect_sweep").disabled, "unlocked UI exposes free route choice")
	node_named("StudySelect_sweep").pressed.emit()
	check(profile.study_route("guanyu") == "sweep" and profile.credits() == 1820 and labels_contain("横扫"), "route selection saves without additional cost")
	var existing := node_named("StudySelect_guard")
	app._open_settings()
	existing.pressed.emit()
	check(profile.study_route("guanyu") == "sweep", "top settings modal rejects underlying study action")
	check(app.settings_panel.close(), "settings modal closes normally")
	var saved_bytes := FileAccess.get_file_as_string(PROFILE_PATH)
	profile.save_path = DIRECTORY + "/missing/profile.json"
	node_named("StudySelect_guard").pressed.emit()
	check(profile.study_route("guanyu") == "sweep" and profile.credits() == 1820 and labels_contain("保存失败"), "failed UI route transaction keeps previous route and explains failure")
	check(FileAccess.get_file_as_string(PROFILE_PATH) == saved_bytes, "failed route UI leaves saved bytes unchanged")
	profile.save_path = PROFILE_PATH
	node_named("StudyRestore").pressed.emit()
	check(profile.study_route("guanyu") == "base" and profile.credits() == 1820, "UI restores base for free")
	# A declared presentation fixture compares every identity/level/route through actual Main binding.
	for id: String in Catalog.playable_roster():
		for level: int in [1, 3, 20]:
			var routes: Array = [Catalog.study_route(id, "base")]
			routes.append_array(Catalog.study_routes(id))
			for route: Dictionary in routes:
				candidate = profile.data.duplicate(true)
				candidate.owned = Catalog.playable_roster()
				candidate.levels[id] = level
				candidate.study_routes[id] = str(route.id)
				check(profile._commit(candidate), "save declared UI matrix fixture " + id)
				var expected := UnitStats.calculate(Catalog.unit(id), level, route.modifiers)
				app._select_study(id)
				check(displayed_stats(id) == expected, "study current values match central result " + id + "/" + str(level) + "/" + str(route.id))
				check(labels_contain(str(route.name)), "study current route name visible " + id)
				app._select_hero(id)
				check(displayed_stats(id) == expected, "hero detail uses same route/level central result " + id)
				var healer := str(expected.special.get("type", "")) == "heal"
				check(badge_matches("hp", "%.0f" % float(expected.hp), "生命"), "visible hero life badge uses central rounded value " + id)
				check(badge_matches("damage", "%.0f" % float(expected.special.get("amount", 0) if healer else expected.damage), "治疗" if healer else "伤害"), "visible hero damage/healing badge uses central final amount and caption " + id)
				check(badge_matches("armor", "%.0f" % float(expected.armor), "护甲"), "visible hero armor badge uses central rounded value " + id)
				check(badge_matches("range", "%.0f" % float(expected.range), "射程"), "visible hero range badge uses central rounded value " + id)
				check(badge_matches("attack_interval", "%.2fs" % float(expected.attack_interval), "出手间隔"), "visible hero interval badge uses central final timing " + id)
				check(badge_matches("cost", "%d" % int(Catalog.unit(id).get("cost", 0)), "召唤能量"), "visible hero cost badge uses actual summon recipe " + id)
				var details: String = app._skill_details(Catalog.unit(id), expected)
				if str(expected.special.get("type", "")) == "heal": check(("每次治疗 %.0f" % float(expected.special.amount)) in details, "healing UI shows final amount once " + id)
				elif str(expected.special.get("type", "")) == "slow": check(("%.2fs" % float(expected.special.duration)) in details, "slow UI shows final intelligence and route duration " + id)
				elif float(expected.aoe_radius) <= 0 and str(expected.special.get("type", "")) != "siege":
					check(("射程 %.0f" % float(expected.range)) in details and ("护甲 %.0f" % float(expected.armor)) in details, "ordinary skill text uses final range and armor " + id)
				await process_frame
				matrix_cases += 1
	# Main passes a deep-copied active study selection to a real logical battle.
	candidate = profile.data.duplicate(true)
	candidate.levels.guanyu = 3
	candidate.study_routes.guanyu = "guard"
	candidate.roster = ["guanyu"]
	check(profile._commit(candidate), "save battle study fixture")
	app.start_stage("stage_01")
	app.battle.render_visuals = false
	app.set_process(false)
	check(app.battle.try_summon("guanyu"), "Main starts and summons studied hero")
	var expected := UnitStats.calculate(Catalog.unit("guanyu"), 3, Catalog.study_modifiers("guanyu", "guard"))
	var actor: Dictionary = app.battle.units[0]
	check(is_equal_approx(float(actor.max_hp), float(expected.hp)) and is_equal_approx(float(actor.armor), float(expected.armor)), "Main battle inherits current central study HP and armor")
	profile.data.study_routes.guanyu = "sweep"
	profile.data.levels.guanyu = 20
	check(app.battle._levels.guanyu == 3, "Main battle retains opening level snapshot")
	app.battle._energy = 400.0
	app.battle._cooldowns.guanyu = 0.03
	app.battle._pulse_cooldown = 0.03
	app._update_hud()
	check(app.summon_buttons[0].disabled and app.summon_labels[0].ready.text == "0.1s", "positive 0.03s summon cooldown remains unavailable and readable")
	check(app.pulse_button.disabled and "0.1s" in app.pulse_button.text, "positive 0.03s pulse cooldown remains unavailable and readable")
	check(not app.battle.try_summon("guanyu") and not app.battle.try_pulse() and app.battle._energy == 400.0, "UI cooldown boundary matches actual rejected actions without cost")
	app.battle.advance(0.04)
	app._update_hud()
	check(not app.summon_buttons[0].disabled and not app.pulse_button.disabled, "real fixed-step countdown restores ready HUD at zero")
	app._combat_event("heal", Vector2(200, 400), 50.88864, 1)
	var heal_text_found := false
	for mote: Dictionary in app.motes:
		if is_instance_valid(mote.node) and mote.node.text == "+51": heal_text_found = true
	check(heal_text_found, "healing floating text rounds like the same final skill amount")
	check(app._stop_battle(), "study UI cleans logical battle")
	var future := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	future.store_string(JSON.stringify({"schema": SiegeProfile.SCHEMA + 1, "preserve": "future-study"}))
	future.close()
	saved_bytes = FileAccess.get_file_as_string(PROFILE_PATH)
	profile.load_profile()
	app.show_home("研修")
	check(node_named("StudyUnlock").disabled and labels_contain("仅可浏览"), "future schema has visible read-only protection")
	app._unlock_study("guanyu")
	check(FileAccess.get_file_as_string(PROFILE_PATH) == saved_bytes, "future schema remains byte-identical after attempted UI action")
	app.queue_free()
	await process_frame
	await root.get_node("GameAudio").shutdown()
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "matrix_cases": matrix_cases, "program_version": str(ProjectSettings.get_setting("application/config/version")), "project_sha256": FileAccess.get_sha256("res://project.godot"), "studies_sha256": FileAccess.get_sha256("res://resources/studies.json"), "units_sha256": FileAccess.get_sha256("res://resources/units.json"), "scripts_sha256": {"scripts/ui/Main.gd": FileAccess.get_sha256("res://scripts/ui/Main.gd"), "scripts/ui/StatBadge.gd": FileAccess.get_sha256("res://scripts/ui/StatBadge.gd")}, "scope": "Headless actual Main study/hero bindings with six visible central-value SVG stat badges, isolated profile transactions and logical battle. No foreground input, native rendering or performance claim.", "isolation": DIRECTORY}
	var report := FileAccess.open("res://reports/study_ui_smoke.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "\t"))
	report.close()
	print("STUDY_UI_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
