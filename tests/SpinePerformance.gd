extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")
const HEROES := ["097", "312", "314", "072", "163", "084", "018", "168"]
const ENEMIES := ["253", "254", "046", "285", "271"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var native_count := 0
	var memory_before := OS.get_static_memory_usage()
	for index in 64:
		var actor := Actor.new()
		root.add_child(actor)
		actor.position = Vector2(105 + (index % 16)*67, 305 + (index / 16)*88)
		var id: String = HEROES[index % HEROES.size()] if index < 12 else ENEMIES[index % ENEMIES.size()]
		actor.configure("d69_" + id, 1 if index % 2 == 0 else -1)
		actor.play_state("move")
		if actor.using_spine(): native_count += 1
	for warmup in 60: await process_frame
	var samples: Array = []
	var previous := Time.get_ticks_usec()
	for sample in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
	samples.sort()
	var mean := 0.0
	for value: float in samples: mean += value
	mean /= samples.size()
	var report := {
		"native_instances":native_count,"full_hero_instances":12,"total_instances":64,
		"sample_frames":samples.size(),"mean_frame_ms":mean,"p95_frame_ms":samples[int(samples.size()*0.95)],
		"max_frame_ms":samples.back(),"fps_average":1000.0/mean,
		"static_memory_increase_bytes":OS.get_static_memory_usage()-memory_before,
		"rendering_adapter":RenderingServer.get_video_adapter_name(),
		"scope":"64 independent real Spine animation instances; rendered visual workload, combat excluded",
		"passed":native_count==64 and samples[int(samples.size()*0.95)]<33.334,
	}
	var file := FileAccess.open("res://reports/spine_performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("SPINE_PERFORMANCE_COMPLETE ", JSON.stringify(report))
	quit(0 if report.passed else 1)
