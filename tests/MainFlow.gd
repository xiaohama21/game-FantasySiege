extends SceneTree

var app
var failures: Array[String] = []
var checks := 0
var screenshots := 0
var directory := "res://tests/.user/main_flow"

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error(message)

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var pic := root.get_texture().get_image()
	check(pic.save_png("res://reports/runtime/" + name + ".png") == OK, "save screenshot " + name)
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/runtime"))
	var path := directory + "/profile.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var profile = root.get_node("ProfileStore")
	profile.configure_path(path)
	profile.load_profile()
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	root.warp_mouse(Vector2(640, 400))
	await capture("01_campaign")
	check(app.tab == "远征", "campaign opens")
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
	check(text_exists("未契约"), "squad includes locked collection")
	app.show_home("图鉴")
	await process_frame
	check(is_instance_valid(app.viewer) and app.viewer.using_spine(), "gallery shows true Spine")
	check(Catalog.visuals().size() == 21, "twenty-one source visuals available")
	await capture("04_gallery")
	var selection: String = app.selected_actor
	app.show_home("英魂")
	check(app.selected_actor == selection, "gallery selection does not overwrite hero selection")
	var stage_id := "stage_01"
	app.start_stage(stage_id)
	check(is_instance_valid(app.battle), "battle created")
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
	app._toggle_pause()
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
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "screenshots": screenshots, "real_spine": true, "isolation": directory, "world_width": 2560, "stages_sha256": FileAccess.get_sha256("res://resources/stages.json")}
	var f := FileAccess.open("res://reports/main_flow.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("MAIN_FLOW " + JSON.stringify(result))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
