extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")
var report: Dictionary = {"passed": false, "animations": [], "errors": []}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "d69_097"
	var report_path := args[1] if args.size() > 1 else "res://reports/spine_probe.json"
	report.visual_id = id
	var actor := Actor.new()
	root.add_child(actor)
	actor.position = Vector2(640, 510)
	actor.configure(id, 1)
	await process_frame
	if not actor.using_spine():
		report.errors.append("native sprite not loaded")
		_finish(report_path, 1)
		return
	var sprite := actor.spine_sprite()
	actor.set_process(false)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(actor.spec.data).replace("actor-data.tres", "actor.spine-json")))
	for animation: String in raw.get("animations", {}):
		var state: Object = sprite.call("get_animation_state")
		state.call("set_animation", animation, false, 0)
		var visible_samples := 0
		for step in range(36):
			sprite.call("update_skeleton", 1.0 / 30.0)
			await process_frame
			var sample: Rect2 = sprite.call("get_skeleton").call("get_bounds")
			if sample.size.is_finite() and sample.position.is_finite() and sample.size.x > 0 and sample.size.y > 0: visible_samples += 1
		var bounds: Variant = sprite.call("get_skeleton").call("get_bounds")
		report.animations.append({"name": animation, "bounds": str(bounds), "visible_samples": visible_samples})
		if visible_samples == 0: report.errors.append("empty skeleton for animation " + animation)
	actor.play_state("move")
	await create_timer(0.08).timeout
	report.passed = report.errors.is_empty()
	report.native = actor.using_spine()
	_finish(report_path, 0 if report.passed else 1)

func _finish(path: String, code: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("SPINE_PROBE_COMPLETE ", JSON.stringify(report))
	quit(code)
