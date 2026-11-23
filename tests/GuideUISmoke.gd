extends SceneTree

# Headless actual Main bindings and Godot-internal event dispatch. This is not
# a native render, input-device, foreground, audio-listening or performance test.
const PREFS = preload("res://scripts/core/UserPrefs.gd")
const GUIDE = preload("res://scripts/ui/GuidePanel.gd")
const QA = preload("res://scripts/core/QAStartupContext.gd")
const DIRECTORY := "res://tests/.user/guide_ui"
const PROFILE_PATH := DIRECTORY + "/profile.json"
const PREFS_PATH := DIRECTORY + "/preferences.json"
const REPORT_PATH := "res://reports/guide_ui_smoke.json"

var app
var profile
var prefs
var checks := 0
var failures: Array[String] = []
var pages: Array[Dictionary] = []
var first_visit_verified := false
var skip_verified := false
var pause_restore_verified := false
var preference_failure_verified := false
var cold_reload_verified := false
var internal_input_verified := false
var future_protection_verified := false
var exit_layer_verified := false
var profile_baseline := ""
var failure_evidence: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "isolated fixture file can be written: " + path)
	if file == null: return
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()

func button_named_text(parent: Node, value: String) -> Button:
	for node: Node in parent.find_children("*", "Button", true, false):
		if str(node.text) == value: return node as Button
	return null

func mouse_button(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	return event

func dispatch_key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	internal_input_verified = true

func cold_prefs() -> SiegeUserPrefs:
	var reader := PREFS.new()
	reader.configure_path(PREFS_PATH)
	root.add_child(reader)
	return reader

func stop_to_camp() -> void:
	app.show_home("远征")
	await process_frame
	check(not is_instance_valid(app.battle), "returning to camp releases the guide test's logical battle")

func start_first_stage() -> void:
	app.start_stage("stage_01")
	check(is_instance_valid(app.battle), "real Main creates the first-stage logical battle")
	if is_instance_valid(app.battle):
		app.battle.render_visuals = false
		app.battle.set_process(false)
	await process_frame

func verify_page(expected: int, starting: bool, record := false) -> void:
	var guide = app.guide_panel
	check(is_instance_valid(guide), "guide exists for page " + str(expected))
	if not is_instance_valid(guide): return
	check(guide.page == expected, "actual guide page index " + str(expected))
	check(guide.heading.text == GUIDE.TITLES[expected] and guide.body.text == GUIDE.TEXTS[expected], "heading and necessary rules match the current guide resource")
	check(guide.counter.text == "操作指南  %d / 3" % (expected + 1), "visible page counter matches the selected page")
	check(guide.previous.disabled == (expected == 0), "previous-page availability matches the first-page boundary")
	check(guide.starting == starting, "guide final action distinguishes battle and camp")
	var expected_next := "开始远征" if expected == 2 and starting else "关闭指南" if expected == 2 else "下一页"
	check(guide.next.text == expected_next, "guide next/finish button exposes the actual action")
	check(guide.is_ancestor_of(root.gui_get_focus_owner()), "keyboard focus remains inside the current guide")
	if starting:
		check(app.paused and app.battle._visual_playback_multiplier == 0.0, "battle and visual playback remain paused while guide is visible")
		check(guide.story == str(Catalog.stage(app.active_stage).get("story_intro", "")), "guide uses the current stage's story rather than a fixture narrative")
	if expected == 2:
		check(guide.body.text.contains("%d能量" % int(SiegeBattle.PULSE_COST)) and guide.body.text.contains("冷却%d秒" % int(SiegeBattle.PULSE_COOLDOWN)), "pulse instructions describe actual battle energy and cooldown")
	if record:
		pages.append({"page": expected, "heading": guide.heading.text, "body": guide.body.text,
			"counter": guide.counter.text, "next": guide.next.text, "previous_disabled": guide.previous.disabled,
			"story": guide.story, "starting": guide.starting, "paused": app.paused})

func verify_modal_blocks_combat() -> void:
	var guide = app.guide_panel
	if not is_instance_valid(guide) or not is_instance_valid(app.battle):
		check(false, "modal combat audit has the actual guide and battle")
		return
	var before: Dictionary = app.battle.get_snapshot().duplicate(true)
	var before_view: float = app.view_x
	var before_speed: float = app.speed
	var before_follow: bool = app.follow_frontline
	var before_units: int = app.battle.units.size()
	app.pause_button.pressed.emit()
	app.speed_button.pressed.emit()
	app.follow_button.pressed.emit()
	app.summon_buttons[0].pressed.emit()
	app.pulse_button.pressed.emit()
	app._toggle_pause()
	app._toggle_speed()
	app._summon(str(app.draft_roster[0]))
	app._pulse()
	app._input(mouse_button(Vector2(640, 400), true))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-180, 0)
	app._input(motion)
	app._input(mouse_button(Vector2(640, 400), false))
	# Space legitimately activates a focused guide button, so test Main's
	# blocked battle-pause handler here and real guide keyboard navigation below.
	var blocked_space := InputEventKey.new()
	blocked_space.keycode = KEY_SPACE
	blocked_space.pressed = true
	app._unhandled_key_input(blocked_space)
	for code: int in [KEY_1, KEY_F, KEY_P, KEY_C, KEY_RIGHT]:
		await dispatch_key(code)
	app._process(0.25)
	app._update_camera(0.25)
	var after: Dictionary = app.battle.get_snapshot()
	check(after.energy == before.energy and after.elapsed == before.elapsed and after.player_hp == before.player_hp and after.enemy_hp == before.enemy_hp, "guide blocks time, resources and combat damage through actual Main routes")
	check(app.battle.units.size() == before_units and after.cooldowns == before.cooldowns, "guide prevents summon and pulse state changes")
	check(app.paused and app.speed == before_speed and app.follow_frontline == before_follow, "underlying buttons, speed and follow shortcuts cannot pierce guide")
	check(not app.dragging and app.view_x == before_view, "guide blocks drag and keyboard/edge camera movement")
	check(app.pause_button.focus_mode == Control.FOCUS_NONE and guide.is_ancestor_of(root.gui_get_focus_owner()), "underlying battle controls are outside modal keyboard traversal")
	app._open_settings()
	app._open_guide()
	check(not is_instance_valid(app.settings_panel) and app.guide_panel == guide and app.focus_locks.size() == 1, "guide prevents duplicate guide and competing settings modal")

func verify_first_visit_and_finish() -> void:
	await start_first_stage()
	first_visit_verified = is_instance_valid(app.guide_panel) and app.paused
	check(first_visit_verified, "unseen first-stage guide opens automatically and pauses the battle")
	if not is_instance_valid(app.guide_panel): return
	verify_page(0, true, true)
	await verify_modal_blocks_combat()
	if not is_instance_valid(app.guide_panel):
		check(false, "combat input audit leaves the current guide alive")
		return
	app.guide_panel.next.grab_focus()
	var keyboard_before: Dictionary = app.battle.get_snapshot()
	await dispatch_key(KEY_SPACE)
	check(app.paused and app.battle.get_snapshot().elapsed == keyboard_before.elapsed and app.battle.get_snapshot().energy == keyboard_before.energy, "Space activates the focused guide action without unpausing or advancing combat")
	verify_page(1, true, true)
	app.guide_panel.previous.pressed.emit()
	verify_page(0, true)
	app.guide_panel.next.pressed.emit()
	app.guide_panel.next.pressed.emit()
	verify_page(2, true, true)
	var closed_guide = app.guide_panel
	app.guide_panel.next.pressed.emit()
	check(not is_instance_valid(app.guide_panel) and not app.paused, "finishing guide synchronously resumes its original running state")
	await process_frame
	check(not is_instance_valid(closed_guide), "finished guide is actually released after the queued frame")
	check(app.pause_button.focus_mode != Control.FOCUS_NONE and app.focus_locks.is_empty(), "finished guide restores the previous focus modes")
	check(bool(prefs.get_value("tutorial_seen")) and not prefs.dirty, "finishing guide commits the seen flag")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PREFS_PATH))
	check(bool(disk.get("tutorial_seen", false)), "finished guide seen flag exists on isolated disk")
	var reader := cold_prefs()
	cold_reload_verified = bool(reader.get_value("tutorial_seen"))
	check(cold_reload_verified, "new preference service cold-reads the completed guide flag")
	reader.queue_free()
	await stop_to_camp()

func verify_skip_and_reopen() -> void:
	check(prefs.set_value("tutorial_seen", false) and prefs.flush(), "save isolated unseen preference for independent skip path")
	await start_first_stage()
	var skip: Button = button_named_text(app.guide_panel, "跳过") if is_instance_valid(app.guide_panel) else null
	check(is_instance_valid(skip), "actual guide exposes a skip button")
	if is_instance_valid(skip): skip.pressed.emit()
	await process_frame
	skip_verified = not is_instance_valid(app.guide_panel) and not app.paused and bool(prefs.get_value("tutorial_seen")) and not prefs.dirty
	check(skip_verified, "skip persists seen and restores running battle without advancing it")
	await stop_to_camp()
	await start_first_stage()
	check(not is_instance_valid(app.guide_panel) and not app.paused, "a seen first stage does not force the guide again")
	await stop_to_camp()
	var camp_paused: bool = app.paused
	app._open_guide()
	verify_page(0, false)
	app.guide_panel.next.pressed.emit()
	app.guide_panel.next.pressed.emit()
	verify_page(2, false)
	app.guide_panel.next.pressed.emit()
	await process_frame
	check(not is_instance_valid(app.guide_panel) and app.paused == camp_paused and app.focus_locks.is_empty(), "camp guide can be revisited and closed without a battle or pause mutation")
	app._open_settings()
	var settings = app.settings_panel
	app._open_guide()
	check(is_instance_valid(settings) and app.settings_panel == settings and not is_instance_valid(app.guide_panel), "settings prevents a competing guide")
	settings.close()
	await process_frame
	await start_first_stage()
	app.pause_button.pressed.emit()
	check(app.paused, "real battle pause button pauses before guide revisit")
	app._open_guide()
	verify_page(0, true)
	check(app.guide_was_paused, "guide records the already-paused battle state")
	await dispatch_key(KEY_ESCAPE)
	pause_restore_verified = not is_instance_valid(app.guide_panel) and app.paused and app.battle._visual_playback_multiplier == 0.0
	check(pause_restore_verified, "Esc closes a revisited guide while preserving original pause")
	await stop_to_camp()

func verify_failed_save_and_exit_stack() -> void:
	check(prefs.set_value("tutorial_seen", false) and prefs.flush(), "save pre-failure unseen preference baseline")
	var original := FileAccess.get_file_as_string(PREFS_PATH)
	var original_backup := FileAccess.get_file_as_string(PREFS_PATH + ".bak")
	var conflict := ProjectSettings.globalize_path(PREFS_PATH + ".tmp")
	check(DirAccess.make_dir_recursive_absolute(conflict) == OK, "isolated temp-directory conflict forces the real preference writer to fail")
	await start_first_stage()
	if not is_instance_valid(app.guide_panel):
		check(false, "save-failure path has an actual unseen guide")
		return
	var skip := button_named_text(app.guide_panel, "跳过")
	check(is_instance_valid(skip), "save-failure guide exposes skip")
	if not is_instance_valid(skip): return
	skip.pressed.emit()
	await process_frame
	preference_failure_verified = not is_instance_valid(app.guide_panel) and not app.paused and bool(prefs.get_value("tutorial_seen")) and prefs.dirty and FileAccess.get_file_as_string(PREFS_PATH) == original
	check(preference_failure_verified, "failed seen save closes guide but retains runtime flag/dirty and original disk bytes")
	check(FileAccess.get_file_as_string(PREFS_PATH + ".bak") == original_backup and prefs.error_message.contains("保存失败") and app.toast.visible and app.toast.text.contains("保存失败"), "failed guide save preserves backup and makes the actual error visible")
	var reader := cold_prefs()
	check(not bool(reader.get_value("tutorial_seen")) and bool(reader.can_save()), "cold service still sees the last persisted unseen flag after failed save")
	reader.queue_free()
	await stop_to_camp()
	await start_first_stage()
	check(not is_instance_valid(app.guide_panel), "current unsaved seen value suppresses repeated auto-guide only in this process")
	app._open_guide()
	var guide = app.guide_panel
	var before_page: int = guide.page
	var before_fullscreen: bool = bool(prefs.get_value("fullscreen"))
	app._request_quit()
	check(is_instance_valid(app.exit_panel) and app._active_modal() == app.exit_panel and not app.quitting, "failed preference save opens exit confirmation above the guide rather than terminating the test")
	check(is_instance_valid(guide), "underlying guide remains alive below exit confirmation")
	var exit_modal = app.exit_panel
	check(exit_modal.is_ancestor_of(root.gui_get_focus_owner()) and guide.next.focus_mode == Control.FOCUS_NONE, "exit confirmation exclusively owns keyboard focus")
	guide.next.pressed.emit()
	exit_layer_verified = guide.page == before_page and app.guide_panel == guide
	check(exit_layer_verified, "programmatic underlying guide button cannot advance below exit confirmation")
	var exit_press_evidence := {"page_before": before_page, "page_after": guide.page,
		"active_modal_is_exit": app._active_modal() == exit_modal,
		"guide_retained": app.guide_panel == guide, "blocked": exit_layer_verified}
	await dispatch_key(KEY_F11)
	check(bool(prefs.get_value("fullscreen")) == before_fullscreen and app.exit_panel == exit_modal and app.guide_panel == guide, "F11 cannot bypass the active exit layer or mutate preferences")
	await dispatch_key(KEY_ESCAPE)
	check(not is_instance_valid(app.exit_panel) and app.guide_panel == guide and app.paused and app.focus_locks.size() == 1, "Esc dismisses only top exit layer and leaves paused guide and focus lock intact")
	var after_exit_skip := button_named_text(guide, "跳过")
	after_exit_skip.pressed.emit()
	await process_frame
	check(not is_instance_valid(app.guide_panel) and not app.paused and app.focus_locks.is_empty(), "guide can close normally after the exit layer is dismissed")
	check(FileAccess.get_file_as_string(PREFS_PATH) == original and FileAccess.get_file_as_string(PREFS_PATH + ".bak") == original_backup, "stacked exit/guide failure paths have not rewritten either preference file")
	failure_evidence = {"primary_sha256": FileAccess.get_sha256(PREFS_PATH), "backup_sha256": FileAccess.get_sha256(PREFS_PATH + ".bak"),
		"runtime_seen": bool(prefs.get_value("tutorial_seen")), "dirty_before_retry": prefs.dirty,
		"cold_seen_after_failure": false, "exit_guide_button_blocked": exit_layer_verified,
		"exit_guide_press": exit_press_evidence}
	check(DirAccess.remove_absolute(conflict) == OK, "remove only the isolated empty temp-conflict directory")
	app._open_settings()
	var settings = app.settings_panel
	check(is_instance_valid(settings), "existing settings save path is available for retry")
	settings.close()
	await process_frame
	check(not is_instance_valid(app.settings_panel) and not app.paused and not prefs.dirty and prefs.error_message.is_empty(), "existing settings retry saves dirty guide flag and resumes battle")
	reader = cold_prefs()
	check(bool(reader.get_value("tutorial_seen")), "cold service reads seen only after the later successful retry")
	reader.queue_free()
	await stop_to_camp()

func verify_future_preferences() -> void:
	write_json(PREFS_PATH, {"schema": PREFS.SCHEMA + 1, "future_guide": "preserve-newer-settings"})
	var original := FileAccess.get_file_as_string(PREFS_PATH)
	prefs.configure_path(PREFS_PATH)
	check(not prefs.can_save() and not bool(prefs.get_value("tutorial_seen")), "future preferences stay read-only with safe unseen default")
	await start_first_stage()
	check(is_instance_valid(app.guide_panel) and app.paused, "future preferences do not suppress safe first-stage guidance")
	if not is_instance_valid(app.guide_panel): return
	var skip := button_named_text(app.guide_panel, "跳过")
	check(is_instance_valid(skip), "future guide exposes skip without mutating newer settings")
	if not is_instance_valid(skip): return
	skip.pressed.emit()
	await process_frame
	future_protection_verified = not is_instance_valid(app.guide_panel) and not app.paused and not prefs.can_save() and not bool(prefs.get_value("tutorial_seen")) and FileAccess.get_file_as_string(PREFS_PATH) == original
	check(future_protection_verified, "closing future-version guide never downgrades its bytes or claims seen was saved")
	check(not prefs.dirty and app.toast.visible and app.toast.text.contains("版本较新"), "future seen write remains clean and the protection reason is visible")
	var reader := cold_prefs()
	check(not reader.can_save() and FileAccess.get_file_as_string(PREFS_PATH) == original, "future protection survives a new preference instance")
	reader.queue_free()
	await stop_to_camp()

func run() -> void:
	if DisplayServer.get_name() != "headless":
		check(false, "GuideUISmoke must run headless; foreground and rendered guide checks are separate")
		await finish()
		return
	check(QA.enabled() and QA.valid(), "first autoload startup uses the valid shared isolated context")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY)) == OK, "isolated guide fixture directory exists")
	var conflict := ProjectSettings.globalize_path(PREFS_PATH + ".tmp")
	if DirAccess.dir_exists_absolute(conflict):
		check(DirAccess.remove_absolute(conflict) == OK, "recover only an empty guide test temp-conflict directory")
	for path: String in [PREFS_PATH, PROFILE_PATH]:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	profile = root.get_node("ProfileStore")
	prefs = root.get_node("UserPrefs")
	profile.configure_path(PROFILE_PATH)
	profile.load_profile()
	check(profile._commit(profile.data.duplicate(true)), "commit only the isolated fresh-profile baseline")
	profile_baseline = FileAccess.get_file_as_string(PROFILE_PATH)
	prefs.configure_path(PREFS_PATH)
	check(prefs.set_value("master_volume", 0.0) and prefs.set_value("edge_scroll", false) and prefs.flush(), "save isolated silent guide preferences without marking guide seen")
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	await process_frame
	check(app.tab == "远征" and not is_instance_valid(app.guide_panel), "camp starts with visible guide entry but no forced modal")
	await verify_first_visit_and_finish()
	await verify_skip_and_reopen()
	await verify_failed_save_and_exit_stack()
	await verify_future_preferences()
	check(FileAccess.get_file_as_string(PROFILE_PATH) == profile_baseline and profile.credits() == 300 and profile.data.transactions.is_empty(), "guide, settings and exit tests never spend character resources or persist a victory")
	app.queue_free()
	await process_frame
	await root.get_node("GameAudio").shutdown()
	await finish()

func finish() -> void:
	var gdd_text := FileAccess.get_file_as_string("res://docs/GAME_DESIGN.md")
	var pattern := RegEx.new()
	pattern.compile("(?m)^> 文档 v([^ \\t]+)[ \\t]+·")
	var matched := pattern.search(gdd_text)
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "phase": "complete",
		"program_version": str(ProjectSettings.get_setting("application/config/version")),
		"project_sha256": FileAccess.get_sha256("res://project.godot"), "gdd_sha256": FileAccess.get_sha256("res://docs/GAME_DESIGN.md"),
		"gdd_version": matched.get_string(1) if matched != null else "",
		"main_sha256": FileAccess.get_sha256("res://scripts/ui/Main.gd"), "guide_panel_sha256": FileAccess.get_sha256("res://scripts/ui/GuidePanel.gd"),
		"user_prefs_sha256": FileAccess.get_sha256("res://scripts/core/UserPrefs.gd"), "fixture_sha256": FileAccess.get_sha256("res://tests/GuideUISmoke.gd"),
		"guide_first_visit_verified": first_visit_verified, "guide_skip_verified": skip_verified,
		"guide_pause_restore_verified": pause_restore_verified, "guide_preference_failure_verified": preference_failure_verified,
		"guide_cold_reload_verified": cold_reload_verified, "guide_future_protection_verified": future_protection_verified,
		"guide_exit_layer_verified": exit_layer_verified, "pages_verified": pages.size(), "pages": pages, "failure_evidence": failure_evidence,
		"bindings_verified": true, "engine_input_dispatch_verified": internal_input_verified,
		"input_device_verified": false, "foreground_verified": false, "performance_measured": false, "native_rendered": false,
		"cold_read_scope": "New preference Node instances in this engine; independent engine startup isolation is covered by QAStartupSmoke",
		"scope": "Headless Main guide bindings, isolated preference transactions and Godot-internal input events; no OS devices, foreground, native rendering, audio listening or performance claim",
		"isolation": DIRECTORY, "qa_startup": QA.snapshot()}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write guide UI smoke report")
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("GUIDE_UI_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
