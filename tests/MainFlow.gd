extends SceneTree

var app
var failures: Array[String] = []
var directory := "res://tests/.user/main_flow"

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message); push_error(message)

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var pic := root.get_texture().get_image()
	check(pic.save_png("res://reports/runtime/" + name + ".png") == OK, "save screenshot " + name)

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
	await capture("01_campaign")
	check(app.tab == "远征", "campaign opens")
	app.show_home("英魂")
	await capture("02_attributes")
	var before: int = profile.level("guanyu")
	app._train("guanyu")
	check(profile.level("guanyu") == before + 1, "UI training writes profile")
	app.show_home("编队")
	await capture("03_squad")
	app.show_home("图鉴")
	await process_frame
	check(is_instance_valid(app.viewer) and app.viewer.using_spine(), "gallery shows true Spine")
	await capture("04_gallery")
	var stage_id := str(Catalog.stages()[0].id)
	app.start_stage(stage_id)
	check(is_instance_valid(app.battle), "battle created")
	app._toggle_pause()
	var elapsed: float = app.battle.get_snapshot().elapsed
	await process_frame
	check(is_equal_approx(app.battle.get_snapshot().elapsed, elapsed), "pause stops logic")
	app._toggle_pause()
	app._toggle_speed()
	check(app.speed == 2, "speed toggles")
	for i in 42:
		for id: String in app.draft_roster: app.battle.try_summon(id)
		app.battle.advance(0.8)
		await process_frame
	app._update_hud()
	await capture("05_battle")
	var old = app.battle
	app.start_stage(stage_id)
	check(old.units.is_empty(), "restart cleans old instances")
	app.show_home()
	check(not is_instance_valid(app.battle), "return stops battle")
	var result := {"passed": failures.is_empty(), "failures": failures, "screenshots": 5, "real_spine": true, "isolation": directory}
	var f := FileAccess.open("res://reports/main_flow.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("MAIN_FLOW " + JSON.stringify(result))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
