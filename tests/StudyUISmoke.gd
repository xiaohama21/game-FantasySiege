extends SceneTree

# Headless Main bindings and real profile transactions; no rendered/native or performance claim.
const DIRECTORY := "res://tests/.user/study_ui"
const PROFILE_PATH := DIRECTORY + "/profile.json"
var app
var profile
var checks := 0
var failures: Array[String] = []
var matrix_cases := 0
var navigation_checks := 0
var navigation_records: Array[Dictionary] = []
var battle_diagnostic: Dictionary = {}
var navigation_toast_valid := true
var navigation_toast_records: Array[Dictionary] = []

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

func settle_list_layout() -> void:
	for _frame in 4: await process_frame

func list_scroll(value: String) -> ScrollContainer:
	return node_named(value) as ScrollContainer

func list_scroll_limit(scroll: ScrollContainer) -> int:
	var bar := scroll.get_v_scroll_bar()
	return maxi(0, floori(bar.max_value - bar.page))

func card_fully_visible(scroll_name: String, id: String) -> bool:
	var scroll := list_scroll(scroll_name)
	var card := node_named("HeroCard_" + id) as Control
	return is_instance_valid(scroll) and is_instance_valid(card) and bool(scroll.get_meta("list_restore_ready", false)) and bool(card.get_meta("list_selected", false)) and scroll.get_global_rect().encloses(card.get_global_rect())

func verify_list_position(name: String, expected: int, context: String) -> void:
	var scroll := list_scroll(name)
	check(is_instance_valid(scroll), context + ": rebuilt list exists")
	if not is_instance_valid(scroll): return
	var after := scroll.scroll_vertical
	check(bool(scroll.get_meta("list_restore_ready", false)), context + ": layout restoration completes")
	check(after == expected and after >= 0 and after <= list_scroll_limit(scroll), context + ": real vertical position remains valid and unchanged")
	navigation_records.append({"context": context, "scroll": name, "expected": expected, "actual": after, "limit": list_scroll_limit(scroll)})

func verify_roster_slots(expected: Array, context: String) -> void:
	check(app.draft_roster == expected and profile.data.roster == expected, context + ": slots read the actual committed roster")
	for id: String in Catalog.playable_roster():
		var card := node_named("HeroCard_" + id)
		var button := node_named("RosterToggle_" + id) as Button
		var slot: int = expected.find(id) + 1
		check(is_instance_valid(card) and is_instance_valid(button), context + ": roster controls exist " + id)
		if not is_instance_valid(card) or not is_instance_valid(button): continue
		check(int(card.get_meta("roster_slot", -1)) == slot and int(button.get_meta("roster_slot", -1)) == slot, context + ": real card and action expose saved slot " + id)
		check(button.text == "%d号位 · 移出" % slot if slot > 0 else button.text == "加入编队", context + ": visible action identifies actual slot " + id)
	check(labels_contain("至少保留一名") and labels_contain("1—8号位对应召唤键"), context + ": roster limits and key mapping stay visible")

func verify_study_toast(context: String, expected_text: String) -> void:
	var footer := node_named("StudyFooterRule") as Label
	var message: Label = app.toast
	var controls_exist: bool = app.tab == "研修" and is_instance_valid(footer) and is_instance_valid(message)
	check(controls_exist, context + ": actual study footer and transaction toast exist")
	if not controls_exist:
		navigation_toast_valid = false
		return
	var footer_rect := footer.get_global_rect()
	var toast_rect := message.get_global_rect()
	var text_visible: bool = footer.is_visible_in_tree() and message.is_visible_in_tree() and footer.text.contains("基础八关") and footer.text.contains("研修只改变出战策略") and message.text.contains(expected_text)
	var separate: bool = not footer_rect.intersects(toast_rect)
	var footer_inside: bool = footer_rect.position.y >= 0 and footer_rect.end.y <= 720
	var toast_inside: bool = toast_rect.position.y >= 0 and toast_rect.end.y <= 720
	check(text_visible, context + ": base-route rule and actual transaction result remain visible")
	check(separate, context + ": toast does not cover the footer rule")
	check(footer_inside and toast_inside, context + ": footer and whole toast stay within the 720px viewport")
	navigation_toast_valid = navigation_toast_valid and text_visible and separate and footer_inside and toast_inside
	navigation_toast_records.append({"context": context, "message": message.text, "footer": footer.text, "footer_rect": [footer_rect.position.x, footer_rect.position.y, footer_rect.size.x, footer_rect.size.y], "toast_rect": [toast_rect.position.x, toast_rect.position.y, toast_rect.size.x, toast_rect.size.y], "text_visible": text_visible, "nonoverlapping": separate, "footer_inside": footer_inside, "toast_inside": toast_inside})

func audit_list_navigation() -> void:
	var started_checks := checks
	var roster: Array = Catalog.playable_roster()
	var last_id: String = str(roster[-1])
	var other_id: String = str(roster[-2])
	var candidate: Dictionary = profile.data.duplicate(true)
	candidate.owned = roster.duplicate()
	candidate.cleared = Catalog.stages().map(func(stage: Dictionary) -> String: return str(stage.id))
	candidate.credits = 10000
	candidate.study_routes = {}
	for id: String in roster: candidate.levels[id] = 3
	candidate.roster = roster.slice(0, 8)
	check(profile._commit(candidate), "save isolated eligible navigation fixture")
	app._select_hero(last_id)
	await settle_list_layout()
	check(card_fully_visible("HeroListScroll", last_id), "last hero selection reveals its complete current card")
	var scroll := list_scroll("HeroListScroll")
	if not is_instance_valid(scroll):
		navigation_checks = checks - started_checks
		return
	check(scroll.scroll_vertical > 0, "last hero selection uses a genuine lower scroll position")
	var position := scroll.scroll_vertical
	var before_level: int = profile.level(last_id)
	app._train(last_id)
	await settle_list_layout()
	verify_list_position("HeroListScroll", position, "successful hero training")
	check(profile.level(last_id) == before_level + 1 and displayed_stats(last_id) == app._hero_calculation(last_id), "training refresh retains same central final stats")
	var stored_bytes := FileAccess.get_file_as_string(PROFILE_PATH)
	var stored_data: Dictionary = profile.data.duplicate(true)
	profile.save_path = DIRECTORY + "/missing/navigation_profile.json"
	app._train(last_id)
	await settle_list_layout()
	verify_list_position("HeroListScroll", position, "failed hero training")
	check(profile.data == stored_data and FileAccess.get_file_as_string(PROFILE_PATH) == stored_bytes, "failed training preserves profile values and disk bytes")
	profile.save_path = PROFILE_PATH
	app.show_home("研修")
	await settle_list_layout()
	check(card_fully_visible("StudyListScroll", last_id), "cross-page changed hero selection is fully visible in study")
	position = list_scroll("StudyListScroll").scroll_vertical
	app._unlock_study(last_id)
	await settle_list_layout()
	verify_list_position("StudyListScroll", position, "successful study unlock")
	verify_study_toast("successful study unlock", "两条研修路线已解锁")
	check(profile.study_unlocked(last_id) and profile.study_route(last_id) == "base", "navigation unlock uses real transaction and retains base")
	app._select_study(other_id)
	await settle_list_layout()
	check(card_fully_visible("StudyListScroll", other_id), "another lower study choice reveals its complete current card")
	position = list_scroll("StudyListScroll").scroll_vertical
	stored_bytes = FileAccess.get_file_as_string(PROFILE_PATH)
	stored_data = profile.data.duplicate(true)
	profile.save_path = DIRECTORY + "/missing/navigation_profile.json"
	app._unlock_study(other_id)
	await settle_list_layout()
	verify_list_position("StudyListScroll", position, "failed study unlock")
	verify_study_toast("failed study unlock", "保存失败")
	check(not profile.study_unlocked(other_id) and profile.data == stored_data and FileAccess.get_file_as_string(PROFILE_PATH) == stored_bytes, "failed study unlock retains cost, state and original bytes")
	profile.save_path = PROFILE_PATH
	app._select_study(last_id)
	await settle_list_layout()
	var routes: Array = Catalog.study_routes(last_id)
	var study_scroll := list_scroll("StudyListScroll")
	study_scroll.scroll_vertical = mini(350, list_scroll_limit(study_scroll))
	position = study_scroll.scroll_vertical
	await settle_list_layout()
	check(position > 0 and not card_fully_visible("StudyListScroll", last_id), "manual study scrolling can browse away while detail remains selected")
	var credits: int = profile.credits()
	app._set_study_route(last_id, str(routes[0].id))
	await settle_list_layout()
	verify_list_position("StudyListScroll", position, "successful route selection respects manual position")
	verify_study_toast("successful route selection", "已保存")
	check(profile.study_route(last_id) == str(routes[0].id) and profile.credits() == credits, "successful route refresh retains free switching and central selection")
	stored_bytes = FileAccess.get_file_as_string(PROFILE_PATH)
	stored_data = profile.data.duplicate(true)
	profile.save_path = DIRECTORY + "/missing/navigation_profile.json"
	app._set_study_route(last_id, str(routes[1].id))
	await settle_list_layout()
	verify_list_position("StudyListScroll", position, "failed route selection")
	verify_study_toast("failed route selection", "保存失败")
	check(profile.data == stored_data and FileAccess.get_file_as_string(PROFILE_PATH) == stored_bytes, "failed route selection cannot alter profile or original file")
	profile.save_path = PROFILE_PATH
	app._set_study_route(last_id, "base")
	await settle_list_layout()
	verify_list_position("StudyListScroll", position, "free base restoration")
	verify_study_toast("free base restoration", "已保存")
	check(profile.study_route(last_id) == "base" and profile.credits() == credits, "base restore remains free")
	app._select_study(last_id)
	app._set_study_route(last_id, str(routes[0].id))
	app._set_study_route(last_id, "base")
	await settle_list_layout()
	check(card_fully_visible("StudyListScroll", last_id), "repeated selection survives synchronous route rebuilds and reveals the hidden card")
	verify_study_toast("synchronous selection and route rebuilding", "已保存")
	check(profile.study_route(last_id) == "base" and profile.credits() == credits, "synchronous selection and route changes retain real free transactions")
	app._select_study(str(roster[0]))
	await settle_list_layout()
	check(card_fully_visible("StudyListScroll", str(roster[0])) and list_scroll("StudyListScroll").scroll_vertical == 0, "bottom-to-first study selection uses new content coordinates and reveals first card")
	app._select_hero(last_id)
	await settle_list_layout()
	app._select_hero(str(roster[0]))
	await settle_list_layout()
	check(card_fully_visible("HeroListScroll", str(roster[0])) and list_scroll("HeroListScroll").scroll_vertical == 0, "bottom-to-first hero selection uses new content coordinates and reveals first card")
	app._select_hero(other_id)
	await settle_list_layout()
	check(card_fully_visible("HeroListScroll", other_id), "changed selection is visible in heroes")
	var hero_scroll := list_scroll("HeroListScroll")
	hero_scroll.scroll_vertical = mini(110, list_scroll_limit(hero_scroll))
	var hero_position := hero_scroll.scroll_vertical
	app.show_home("研修")
	await settle_list_layout()
	check(card_fully_visible("StudyListScroll", other_id), "study notices a selection changed in another page")
	study_scroll = list_scroll("StudyListScroll")
	study_scroll.scroll_vertical = mini(210, list_scroll_limit(study_scroll))
	var study_position := study_scroll.scroll_vertical
	stored_data = profile.data.duplicate(true)
	stored_bytes = FileAccess.get_file_as_string(PROFILE_PATH)
	app.show_home("英魂")
	await settle_list_layout()
	verify_list_position("HeroListScroll", hero_position, "unchanged hero selection returns to independent position")
	app.show_home("研修")
	await settle_list_layout()
	verify_list_position("StudyListScroll", study_position, "unchanged study selection returns to independent position")
	check(profile.data == stored_data and FileAccess.get_file_as_string(PROFILE_PATH) == stored_bytes, "scroll and selection memory never write the profile")
	app.show_home("英魂")
	await settle_list_layout()
	hero_scroll = list_scroll("HeroListScroll")
	hero_scroll.size.y = 250
	await settle_list_layout()
	hero_scroll.scroll_vertical = list_scroll_limit(hero_scroll)
	var enlarged_range_position := hero_scroll.scroll_vertical
	app.show_home("英魂")
	await settle_list_layout()
	hero_scroll = list_scroll("HeroListScroll")
	check(enlarged_range_position > list_scroll_limit(hero_scroll), "navigation fixture genuinely reduces the available scroll range")
	verify_list_position("HeroListScroll", list_scroll_limit(hero_scroll), "restoration clamps a reduced scroll range")
	app.show_home("编队")
	await settle_list_layout()
	var squad_scroll := list_scroll("SquadListScroll")
	squad_scroll.scroll_vertical = mini(200, list_scroll_limit(squad_scroll))
	position = squad_scroll.scroll_vertical
	check(position > 0, "squad fixture uses real lower rows")
	var committed_roster: Array = profile.data.roster.duplicate()
	verify_roster_slots(committed_roster, "initial eight-person roster")
	app._toggle_roster(str(committed_roster[0]))
	await settle_list_layout()
	verify_list_position("SquadListScroll", position, "successful roster removal")
	committed_roster.remove_at(0)
	verify_roster_slots(committed_roster, "removal shifts actual slots")
	app._toggle_roster(last_id)
	await settle_list_layout()
	verify_list_position("SquadListScroll", position, "successful lower-row roster addition")
	committed_roster.append(last_id)
	verify_roster_slots(committed_roster, "addition uses actual eighth slot")
	stored_bytes = FileAccess.get_file_as_string(PROFILE_PATH)
	stored_data = profile.data.duplicate(true)
	profile.save_path = DIRECTORY + "/missing/navigation_profile.json"
	app._toggle_roster(str(committed_roster[0]))
	await settle_list_layout()
	verify_list_position("SquadListScroll", position, "failed roster save")
	verify_roster_slots(committed_roster, "failed save retains real slot labels")
	check(profile.data == stored_data and FileAccess.get_file_as_string(PROFILE_PATH) == stored_bytes, "failed roster save preserves array and bytes")
	profile.save_path = PROFILE_PATH
	app._toggle_roster(str(roster[0]))
	await settle_list_layout()
	verify_list_position("SquadListScroll", position, "maximum eight-person boundary")
	verify_roster_slots(committed_roster, "rejected ninth member keeps slot order")
	check(profile.data == stored_data and FileAccess.get_file_as_string(PROFILE_PATH) == stored_bytes, "ninth member rejection preserves profile")
	candidate = profile.data.duplicate(true)
	candidate.roster = [last_id]
	check(profile._commit(candidate), "save declared single-member navigation fixture")
	app.show_home("编队")
	await settle_list_layout()
	app._toggle_roster(last_id)
	await settle_list_layout()
	verify_list_position("SquadListScroll", position, "minimum one-person boundary")
	verify_roster_slots([last_id], "last-member rejection keeps first slot")
	stored_data = profile.data.duplicate(true)
	stored_bytes = FileAccess.get_file_as_string(PROFILE_PATH)
	app._select_hero(last_id)
	app._select_study(str(roster[0]))
	app.show_home("编队")
	await settle_list_layout()
	verify_list_position("SquadListScroll", position, "rapid navigation discards previous list restoration")
	check(node_named("HeroListScroll") == null and node_named("StudyListScroll") == null, "old deferred tasks cannot recreate or affect another page")
	check(profile.data == stored_data and FileAccess.get_file_as_string(PROFILE_PATH) == stored_bytes, "rapid UI rebuilding does not write profile")
	navigation_checks = checks - started_checks

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
	await audit_list_navigation()
	# Main passes a deep-copied active study selection to a real logical battle.
	var dot_key_probe: Dictionary = {}
	dot_key_probe.guanyu = "guard"
	var bracket_key_probe: Dictionary = {}
	bracket_key_probe["guanyu"] = "guard"
	var dot_key: Variant = dot_key_probe.keys()[0]
	var bracket_key: Variant = bracket_key_probe.keys()[0]
	check(dot_key is StringName and not dot_key is String, "fresh dictionary dot assignment creates a StringName fixture key")
	check(bracket_key is String and not bracket_key is StringName, "literal bracket assignment uses real save/API String key type")
	battle_diagnostic["fixture_key_types"] = {"dot": type_string(typeof(dot_key)), "bracket": type_string(typeof(bracket_key))}
	candidate = profile.data.duplicate(true)
	candidate.levels.guanyu = 3
	candidate.study_routes["guanyu"] = "guard"
	candidate.roster = ["guanyu"]
	check(profile._commit(candidate), "save battle study fixture")
	var route_key_types: Array[Dictionary] = []
	for id: Variant in profile.data.study_routes:
		route_key_types.append({"id": str(id), "type": type_string(typeof(id)), "is_string": id is String, "is_string_name": id is StringName})
		check(id is String, "battle fixture study key follows real save/API String type " + str(id))
	battle_diagnostic["profile_route_key_types"] = route_key_types
	var expected_opening_modifiers := {"guanyu": Catalog.study_modifiers("guanyu", "guard")}
	check(profile.study_modifiers_snapshot() == expected_opening_modifiers, "typed fixture builds the actual guard modifier snapshot before Main start")
	battle_diagnostic["profile_before_start"] = profile.data.duplicate(true)
	app._select_hero("spirit_beast")
	app.start_stage("stage_01")
	app.battle.render_visuals = false
	app.set_process(false)
	await settle_list_layout()
	check(app.active_card_scroll == null and node_named("HeroListScroll") == null and node_named("StudyListScroll") == null, "opening battle invalidates a pending list restore")
	check(app.battle.try_summon("guanyu"), "Main starts and summons studied hero")
	var expected := UnitStats.calculate(Catalog.unit("guanyu"), 3, Catalog.study_modifiers("guanyu", "guard"))
	var actor: Dictionary = {}
	for unit: Dictionary in app.battle.units:
		if str(unit.get("id", "")) == "guanyu" and int(unit.get("team", 0)) == 1:
			actor = unit
			break
	var actual_unit: Dictionary = {}
	for key: String in ["uid", "id", "team", "level", "max_hp", "armor", "stats"]:
		actual_unit[key] = actor.get(key)
	battle_diagnostic["actual_unit"] = actual_unit
	battle_diagnostic["expected_unit"] = expected.duplicate(true)
	battle_diagnostic["profile_after_start"] = profile.data.duplicate(true)
	battle_diagnostic["battle_levels"] = app.battle._levels.duplicate(true)
	battle_diagnostic["battle_study_modifiers"] = app.battle._study_modifiers.duplicate(true)
	battle_diagnostic["auto_step"] = bool(app.battle.auto_step)
	check(app.battle._study_modifiers == expected_opening_modifiers, "Main battle receives the exact nonempty guard modifier snapshot")
	print("STUDY_UI_BATTLE_DIAGNOSTIC " + JSON.stringify(battle_diagnostic))
	check(not actor.is_empty() and is_equal_approx(float(actor.max_hp), float(expected.hp)) and is_equal_approx(float(actor.armor), float(expected.armor)), "Main battle inherits current central study HP and armor for the actual summoned hero")
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
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "matrix_cases": matrix_cases, "navigation_checks": navigation_checks, "navigation_records": navigation_records, "navigation_toast_valid": navigation_toast_valid and not navigation_toast_records.is_empty(), "navigation_toast_records": navigation_toast_records, "battle_diagnostic": battle_diagnostic, "program_version": str(ProjectSettings.get_setting("application/config/version")), "project_sha256": FileAccess.get_sha256("res://project.godot"), "studies_sha256": FileAccess.get_sha256("res://resources/studies.json"), "units_sha256": FileAccess.get_sha256("res://resources/units.json"), "scripts_sha256": {"scripts/ui/Main.gd": FileAccess.get_sha256("res://scripts/ui/Main.gd"), "scripts/ui/StatBadge.gd": FileAccess.get_sha256("res://scripts/ui/StatBadge.gd")}, "scope": "Headless actual Main study/hero bindings, per-page list restoration and visible committed 1—8 roster slots, isolated profile transactions and logical battle. No foreground input, native rendering or performance claim.", "isolation": DIRECTORY}
	var report := FileAccess.open("res://reports/study_ui_smoke.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "\t"))
	report.close()
	print("STUDY_UI_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
