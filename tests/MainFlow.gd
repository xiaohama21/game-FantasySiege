extends SceneTree

var app
var failures: Array[String] = []
var checks := 0
var screenshots := 0
var directory := "res://tests/.user/main_flow"
var observe_host := false
var host_observed_frames := 0
var host_normal_window_frames := 0
var host_focused_frames := 0
var capture_states: Array[Dictionary] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error(message)

func _initialize() -> void:
	process_frame.connect(_observe_host_frame)
	call_deferred("run")

func _observe_host_frame() -> void:
	if not observe_host: return
	host_observed_frames += 1
	# F11 may legitimately select fullscreen during the input regression.
	# Minimized or hidden hosts cannot satisfy the foreground flow contract.
	if root.mode!=Window.MODE_MINIMIZED and DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED and root.visible:
		host_normal_window_frames += 1
	if root.has_focus(): host_focused_frames += 1

func _rendering_driver() -> String:
	if RenderingServer.has_method("get_current_rendering_driver_name"): return str(RenderingServer.call("get_current_rendering_driver_name")).to_lower()
	return "unknown"

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var pic := root.get_texture().get_image()
	var path := "res://reports/runtime/" + name + ".png"
	var state := {"name": name, "path": path, "sha256": "", "size": [pic.get_width(), pic.get_height()], "window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode(), "window_visible": root.visible, "focused": root.has_focus(), "actual_rendering_driver": _rendering_driver()}
	var saved := pic.save_png(path) == OK
	check(saved, "save screenshot " + name)
	if saved: state.sha256 = FileAccess.get_sha256(path)
	capture_states.append(state)
	check(state.window_mode == Window.MODE_WINDOWED and state.display_window_mode == DisplayServer.WINDOW_MODE_WINDOWED and state.window_visible, "screenshot uses a normal visible window: " + name)
	check(state.focused, "screenshot uses a focused foreground window: " + name)
	check(state.size == [1280, 720] and root.size == Vector2i(1280, 720) and DisplayServer.window_get_size() == Vector2i(1280, 720), "screenshot preserves the full 1280x720 window: " + name)
	check(state.actual_rendering_driver == "vulkan", "screenshot uses the actual Vulkan driver: " + name)
	screenshots += 1

func controls(node: Node) -> Array:
	var result: Array = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(controls(child))
	return result

func text_exists(value: String) -> bool:
	for node: Node in controls(app.screen):
		if (node is Label or node is Button) and value in node.text: return true
	return false

func portrait_count(node: Node) -> int:
	var count := 0
	for control: Node in controls(node):
		if not control.has_meta("portrait_unit_id"): continue
		var id := str(control.get_meta("portrait_unit_id"))
		if id.is_empty(): continue
		count += 1
		check(bool(control.get("has_art")), "character artwork must load: " + id)
		check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE and control.focus_mode == Control.FOCUS_NONE, "character artwork cannot block card input: " + id)
	return count

func mouse_button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	return event

func native_units() -> void:
	for actor: Dictionary in app.battle.units:
		if bool(actor.get("alive", false)):
			check(is_instance_valid(actor.get("visual")) and actor.visual.using_spine(), "battle must use native Spine: " + str(actor.get("id", "")))
			if is_instance_valid(actor.get("visual")):
				check(actor.visual.position.is_equal_approx(Vector2(float(actor.x), 510)), "rendered position matches fixed-step world coordinate: " + str(actor.id))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("MainFlow requires a rendered display for real screenshots; omit --headless.")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.visible = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/runtime"))
	var path := directory + "/profile.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var profile = root.get_node("ProfileStore")
	profile.configure_path(path)
	profile.load_profile()
	var prefs := root.get_node("UserPrefs")
	var pref_path := directory + "/preferences.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(pref_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(pref_path + suffix))
	prefs.configure_path(pref_path)
	prefs.set_value("tutorial_seen", true)
	prefs.set_value("master_volume", 0.0)
	prefs.flush()
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	root.warp_mouse(Vector2(640, 400))
	observe_host = true
	await capture("01_campaign")
	check(app.tab == "远征", "campaign opens")
	check(is_instance_valid(app.world._landscape) and app.world._landscape.texture != null and app.world._home_beacon.texture != null and not app.world._rift_beacon.visible, "camp has illustrated route and friendly lighthouse")
	check(text_exists("04") and text_exists("推荐主力"), "four first-chapter cards and recommendation visible")
	app._select_chapter(2)
	await capture("06_chapter_two")
	check(text_exists("浮空核心") and text_exists("先点亮"), "second chapter and stage locks visible")
	app.start_stage("stage_08")
	check(not is_instance_valid(app.battle), "UI rejects locked stage without starting battle")
	app._select_chapter(1)
	app.show_home("英魂")
	check(Catalog.playable_roster().size() == 12, "twelve playable heroes")
	await capture("02_attributes")
	check(portrait_count(app.screen) == 13, "hero collection and selected detail show all twelve identities plus large artwork")
	var before: int = profile.level("guanyu")
	app._train("guanyu")
	check(profile.level("guanyu") == before + 1, "UI training writes profile")
	app._select_hero("star_hammer")
	check(text_exists("后契约") and text_exists("力量") and text_exists("敏捷") and text_exists("智力"), "unowned hero has visible rules and unlock condition")
	var credits: int = profile.credits()
	app._train("star_hammer")
	check(profile.credits() == credits and profile.level("star_hammer") == 1, "unowned hero cannot train")
	app.show_home("编队")
	await capture("03_squad")
	check(portrait_count(app.screen) == 12, "squad shows all character artwork including locked heroes")
	check(text_exists("未契约"), "squad includes locked collection")
	app.show_home("图鉴")
	await process_frame
	check(is_instance_valid(app.viewer) and app.viewer.using_spine(), "gallery shows true Spine")
	check(Catalog.visuals().size() == 21, "twenty-one source visuals available")
	app._gallery_category("enemies")
	check(text_exists("裂隙短刺") and not text_exists("d69_"), "enemy encyclopedia shows skills without technical IDs")
	await capture("09_enemy_book")
	app.selected_visual = "d69_094"
	app._gallery_category("enemies")
	check(text_exists("0.85") and text_exists("半血") and text_exists("P打断重击"), "boss book gives actual windup, phase and pulse counter")
	await capture("14_boss_book")
	app._gallery_category("heroes")
	await capture("04_gallery")
	var selection: String = app.selected_actor
	app.show_home("英魂")
	check(app.selected_actor == selection, "gallery selection does not overwrite hero selection")
	var stage_id := "stage_01"
	prefs.set_value("tutorial_seen", false)
	prefs.flush()
	app.start_stage(stage_id)
	check(portrait_count(app.screen) == app.draft_roster.size(), "all summon slots show the actual roster's character artwork")
	check(app.world._landscape.texture != null and app.world._rift_beacon.visible and app.world._rift_beacon.texture != null, "battle has actual illustrated chapter background and two unique beacons")
	check(is_instance_valid(app.battle), "battle created")
	check(is_instance_valid(app.guide_panel) and app.paused, "first stage automatically opens paused tutorial")
	check(app.pause_button.focus_mode == Control.FOCUS_NONE and app.guide_panel.is_ancestor_of(root.gui_get_focus_owner()), "tutorial takes focus and removes underlying buttons from keyboard traversal")
	app.pause_button.pressed.emit()
	app._toggle_speed()
	check(app.paused and app.speed == 1.0 and is_instance_valid(app.guide_panel), "underlying GUI press and direct speed change cannot pierce tutorial")
	var guide_energy: float = app.battle.get_snapshot().energy
	var guide_elapsed: float = app.battle.get_snapshot().elapsed
	var guide_view: float = app.view_x
	app._summon(str(app.draft_roster[0]))
	app._pulse()
	app._input(mouse_button(Vector2(640, 400), true))
	app._update_camera(0.2)
	await capture("11_guide_summon")
	check(app.battle.get_snapshot().energy == guide_energy and app.battle.get_snapshot().elapsed == guide_elapsed, "tutorial blocks combat and costs no resources")
	check(not app.dragging and app.view_x == guide_view, "tutorial blocks map input")
	app.guide_panel.next.pressed.emit()
	check(app.guide_panel.page == 1 and app.guide_panel.previous.disabled == false, "tutorial next button shows camera page")
	await capture("12_guide_camera")
	app.guide_panel.next.pressed.emit()
	check(app.guide_panel.page == 2 and app.guide_panel.body.text.contains("80") and app.guide_panel.next.text == "开始远征", "tutorial final page describes actual pulse rules")
	await capture("13_guide_pulse")
	app.guide_panel.next.pressed.emit()
	check(not is_instance_valid(app.guide_panel) and not app.paused, "finishing tutorial resumes original running state")
	check(app.pause_button.focus_mode != Control.FOCUS_NONE and app.focus_locks.is_empty(), "tutorial restores original keyboard focus modes")
	check(bool(JSON.parse_string(FileAccess.get_file_as_string(pref_path)).get("tutorial_seen", false)), "completed tutorial persists in independent preferences")
	check(app.world.world_width == 2560 and app.view_max == 1280, "two-screen battlefield")
	check(app.battle.get_parent() == app.world_host, "battle shares camera parent")
	check(app.screen.z_index > 29, "HUD and result layer above every battle actor")
	var fixed_hud: Vector2 = app.energy_label.global_position
	app._input(mouse_button(Vector2(640, 400), true))
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(-220, 0)
	app._input(drag)
	check(app.dragging and app.view_x == 220 and not app.follow_frontline, "mouse drag pans world and disables follow")
	check(app.energy_label.global_position == fixed_hud and app.world_host.position.x == -220, "HUD fixed while world pans")
	app._input(mouse_button(Vector2(640, 620), false))
	check(not app.dragging, "release over HUD ends dragging")
	app._input(mouse_button(Vector2(640, 620), true))
	check(not app.dragging, "HUD cannot start map drag")
	app._set_view_position(-100)
	check(app.view_x == 0, "camera clamps left")
	app._set_view_position(9999)
	check(app.view_x == 1280, "camera clamps right")
	await capture("07_battle_right")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_LEFT
	key.keycode = KEY_LEFT
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	var previous: float = app.view_x
	app._update_camera(0.2)
	check(app.view_x < previous, "left arrow continuously pans view")
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	app._resume_follow()
	app._update_camera(1.0)
	check(app.follow_frontline and app.view_x < 100, "follow returns to opening frontline")
	app._toggle_pause()
	var elapsed: float = app.battle.get_snapshot().elapsed
	var energy: float = app.battle.get_snapshot().energy
	app._pulse()
	check(app.battle.get_snapshot().energy == energy, "paused pulse has no cost")
	await process_frame
	check(is_equal_approx(app.battle.get_snapshot().elapsed, elapsed), "pause stops logic")
	app._open_settings()
	check(is_instance_valid(app.settings_panel) and app.paused, "settings opens above paused battle")
	app.pause_button.pressed.emit()
	app._toggle_pause()
	app._toggle_speed()
	check(app.paused and app.speed == 1.0 and app.pause_button.focus_mode == Control.FOCUS_NONE, "settings rejects underlying button and direct combat control changes")
	for step in 24:
		var owner := root.gui_get_focus_owner()
		check(is_instance_valid(owner) and app.settings_panel.is_ancestor_of(owner), "settings keyboard focus stays in modal " + str(step))
		if is_instance_valid(owner):
			var next := owner.find_next_valid_focus()
			if is_instance_valid(next): next.grab_focus()
	app.settings_panel.volume_sliders.music_volume.value = 25
	app.settings_panel.option_buttons.edge_scroll.button_pressed = false
	app.settings_panel.option_buttons.damage_numbers.button_pressed = false
	var settings_view: float = app.view_x
	var before_mote: int = app.mote_cursor
	app._floating_text("123", Vector2(640, 510), Color.WHITE)
	app._input(mouse_button(Vector2(640, 400), true))
	app._update_camera(0.2)
	app._open_guide()
	await capture("10_settings")
	check(app.mote_cursor == before_mote and not app.dragging and app.view_x == settings_view, "settings options mute motes and block map input")
	check(not is_instance_valid(app.guide_panel), "settings prevents a second modal")
	check(app.battle.get_snapshot().elapsed == elapsed, "settings keeps combat paused")
	app.settings_panel.option_buttons.damage_numbers.button_pressed = true
	check(app.settings_panel.close(), "settings close writes independent preferences")
	check(not is_instance_valid(app.settings_panel) and app.paused, "settings restores preexisting pause")
	check(is_equal_approx(float(prefs.get_value("music_volume")), 0.25) and not bool(prefs.get_value("edge_scroll")), "settings persist changed options")
	app._toggle_pause()
	app._open_settings()
	check(app.paused and bool(app.settings_panel.close()) and not app.paused, "closing settings also resumes previously running battle")
	app._toggle_pause()
	app._open_guide()
	app.guide_panel.close()
	check(app.paused and not is_instance_valid(app.guide_panel), "reopened guide preserves existing pause")
	app._toggle_pause()
	var valid_pref_path: String = prefs.save_path
	var saved_pref_bytes := FileAccess.get_file_as_string(valid_pref_path)
	prefs.save_path = directory + "/missing_preferences/preferences.json"
	var fullscreen_key := InputEventKey.new()
	fullscreen_key.keycode = KEY_F11
	fullscreen_key.pressed = true
	app._unhandled_key_input(fullscreen_key)
	check(prefs.dirty and is_instance_valid(app.toast) and app.toast.text == prefs.error_message, "F11 preference write failure is visibly reported")
	app._unhandled_key_input(fullscreen_key)
	app._open_settings()
	app._request_quit()
	check(not app.quitting and is_instance_valid(app.exit_panel) and text_exists("设置尚未保存"), "unsaved settings block normal window close")
	check(not app.toast.visible, "old toast cannot cover exit confirmation title")
	check(app.focus_locks.size() == 2 and app.exit_panel.is_ancestor_of(root.gui_get_focus_owner()), "exit confirmation owns focus above settings")
	await capture("15_unsaved_settings")
	check(not app.toast.visible, "exit title remains unobstructed after actual rendered frames")
	var fullscreen_before_confirmation: bool = prefs.get_value("fullscreen", false)
	Input.parse_input_event(fullscreen_key)
	await process_frame
	fullscreen_key.pressed = false
	Input.parse_input_event(fullscreen_key)
	check(prefs.get_value("fullscreen", false) == fullscreen_before_confirmation and app.focus_locks.size() == 2, "F11 cannot change settings through the exit confirmation")
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	Input.parse_input_event(escape_key)
	await process_frame
	escape_key.pressed = false
	Input.parse_input_event(escape_key)
	check(not is_instance_valid(app.exit_panel) and is_instance_valid(app.settings_panel), "real Escape dismisses the top exit confirmation and preserves settings")
	check(app.paused and app.focus_locks.size() == 1 and app.settings_panel.is_ancestor_of(root.gui_get_focus_owner()), "dismissing exit warning returns focus and pause to settings")
	check(FileAccess.get_file_as_string(valid_pref_path) == saved_pref_bytes, "failed settings save preserves previous file bytes")
	prefs.save_path = valid_pref_path
	check(prefs.flush() and app.settings_panel.close() and not app.paused, "restored preferences path allows retry and resume")
	app._toggle_speed()
	check(app.speed == 2, "speed toggles")
	app._pulse()
	check(app.battle.get_snapshot().pulse_cooldown > 34, "pulse button triggers real cooldown")
	check(not app.world.pulses.is_empty(), "pulse visual uses world coordinates")
	for i in 60:
		for id: String in app.draft_roster: app.battle.try_summon(id)
		app.battle.advance(0.8)
		await process_frame
	app._update_hud()
	native_units()
	await capture("05_battle")
	var old = app.battle
	app.start_stage(stage_id)
	check(old.units.is_empty(), "restart cleans old instances")
	# Two victories run through the actual battle signal and persistent UI award path.
	for id: String in ["stage_01", "stage_02"]:
		app.start_stage(id)
		if id == "stage_01": profile.save_path = directory + "/missing/award.json"
		for tick in 420:
			if app.battle.get_snapshot().outcome != "running": break
			for actor_id: String in app.draft_roster: app.battle.try_summon(actor_id)
			app.battle.advance(0.5)
			await process_frame
		check(app.battle.get_snapshot().outcome == "victory", "UI battle victory " + id)
		if id == "stage_01":
			var pending: String = app.run_token
			app.show_home()
			check(app.run_token == pending and not pending.is_empty() and is_instance_valid(app.result_panel), "unclaimed victory blocks silent abandon")
			app._request_quit()
			check(not app.quitting and is_instance_valid(app.exit_panel) and text_exists("奖励尚未保存"), "window close requires explicit handling of unsaved victory")
			app._dismiss_exit()
			check(app.run_token == pending and not app.quitting, "dismissing close warning keeps exact award retryable")
			profile.save_path = path
			check(profile.win(pending), "pending victory can retry exact award")
			app.run_token = ""
		check(profile.data.cleared.has(id) and is_instance_valid(app.result_panel), "victory saved and rendered " + id)
	check(profile.owns("star_hammer") and text_exists("新契约"), "second-stage victory grants and displays new hero")
	await capture("08_unlock_result")
	app._select_hero("star_hammer")
	check(not text_exists("后契约"), "unlocked hero can train")
	profile.load_profile()
	check(profile.owns("star_hammer"), "collection survives reload")
	app.show_home()
	check(not is_instance_valid(app.battle) and app.view_x == 0, "return stops battle and resets view")
	# Stop before graceful exit releases audio and may close the window.
	observe_host = false
	check(host_observed_frames > 0 and host_normal_window_frames == host_observed_frames, "flow stays visible and non-minimized in every observed frame")
	check(host_focused_frames == host_observed_frames, "flow stays focused in every observed frame")
	await app._request_quit()
	check(app.quitting and bool(root.get_node("GameAudio").shutdown_clean), "normal Main window close waits for actual audio playback release")
	var result := {"program_version":str(ProjectSettings.get_setting("application/config/version", "unknown")), "passed": failures.is_empty(), "checks": checks, "failures": failures, "screenshots": screenshots, "real_spine": true, "isolation": directory, "world_width": 2560, "stages_sha256": FileAccess.get_sha256("res://resources/stages.json"), "units_sha256": FileAccess.get_sha256("res://resources/units.json"), "normal_window_close": app.quitting, "audio_shutdown_clean": bool(root.get_node("GameAudio").shutdown_clean)}
	result.host_observed_frames = host_observed_frames
	result.host_normal_window_frames = host_normal_window_frames
	result.host_focused_frames = host_focused_frames
	result.capture_states = capture_states
	result.engine_input_dispatch_verified = true
	result.os_input_verified = false
	var f := FileAccess.open("res://reports/main_flow.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("MAIN_FLOW " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
