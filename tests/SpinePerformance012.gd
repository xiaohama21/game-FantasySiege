extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")
const Battle = preload("res://scripts/combat/SiegeBattle.gd")
const HEROES := ["097","312","314","072","163","084","018","168","110","023","147","069"]
const ENEMIES := ["253","254","046","285","271","057","059","036","094"]
const BASELINE_HEROES := ["097","312","314","072","163","084","018","168"]
const BASELINE_ENEMIES := ["253","254","046","285","271"]
class MeasuredBattle extends SiegeBattle:
	var measuring := false
	var health_draw_enabled := true
	var advance_samples: Array = []
	var draw_samples: Array = []
	var rate_samples: Array = []
	func advance(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super.advance(delta)
		if measuring: advance_samples.append((Time.get_ticks_usec()-started)/1000.0)
	func _draw() -> void:
		if not health_draw_enabled: return
		var started := Time.get_ticks_usec()
		super._draw()
		if measuring: draw_samples.append((Time.get_ticks_usec()-started)/1000.0)
	func _update_visual_rates() -> void:
		var started := Time.get_ticks_usec()
		super._update_visual_rates()
		if measuring: rate_samples.append((Time.get_ticks_usec()-started)/1000.0)
var actors: Array = []
var battle: MeasuredBattle
var camera_origin := 640.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "mixed64"
	var count := 24 if mode.ends_with("24") else (48 if mode.ends_with("48") else 64)
	var is_battle := mode.begins_with("battle")
	var host := Node2D.new()
	host.position.x = -camera_origin
	root.add_child(host)
	var memory_before := OS.get_static_memory_usage()
	if is_battle:
		battle = MeasuredBattle.new()
		battle.health_draw_enabled = not mode.contains("nodraw")
		host.add_child(battle)
		battle.start("stage_03",Catalog.initial_roster(),{})
		battle.seed_performance_units(count)
		for unit: Dictionary in battle.units: actors.append(unit.visual)
	else:
		for index in count:
			var actor := Actor.new()
			host.add_child(actor)
			actor.position = Vector2(760 + (index % 16)*67, 270 + (index / 16)*88)
			if mode == "offscreen64": actor.position = Vector2(100 + (index % 32)*74, 380 + (index / 32)*150)
			var all_heroes := mode.begins_with("heroes") or count == 24
			var id: String = HEROES[index % HEROES.size()] if index < 12 or all_heroes else ENEMIES[index % ENEMIES.size()]
			if mode == "baseline64": id = BASELINE_HEROES[index % BASELINE_HEROES.size()] if index < 12 else BASELINE_ENEMIES[index % BASELINE_ENEMIES.size()]
			actor.configure("d69_"+id,1 if index%2==0 else -1)
			actor.set_update_rate(60 if index<12 else 30)
			actor.play_state("move")
			actors.append(actor)
	for warmup in 60: await process_frame
	if is_battle: battle.measuring = true
	for actor: Node2D in actors:
		actor.profile_native_updates = true
		actor.native_update_count = 0
		actor.native_update_usec = 0
		actor.native_pose_update_count = 0
		actor.native_pose_update_usec = 0
	var samples: Array = []
	var process_samples: Array = []
	var visible_min := count
	var visible_max := 0
	var alive_min := count
	var alive_max := 0
	var previous := Time.get_ticks_usec()
	for sample in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
		process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		var visible := 0
		for actor: Node2D in actors:
			if not is_instance_valid(actor): continue
			var x := actor.global_position.x
			if x>=-80 and x<=1360: visible += 1
		visible_min=mini(visible_min,visible)
		visible_max=maxi(visible_max,visible)
		var alive := battle.active_count() if is_battle else count
		alive_min=mini(alive_min,alive)
		alive_max=maxi(alive_max,alive)
	samples.sort()
	process_samples.sort()
	var mean := 0.0
	for value: float in samples: mean += value
	mean /= samples.size()
	var native_count := 0
	var high_rate_count := 0
	var native_update_count := 0
	var native_update_usec := 0
	var native_pose_update_count := 0
	var native_pose_update_usec := 0
	for actor: Node2D in actors:
		if is_instance_valid(actor) and actor.using_spine(): native_count += 1
		if is_instance_valid(actor) and actor._update_rate>30: high_rate_count += 1
		if is_instance_valid(actor):
			native_update_count += actor.native_update_count
			native_update_usec += actor.native_update_usec
			native_pose_update_count += actor.native_pose_update_count
			native_pose_update_usec += actor.native_pose_update_usec
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://reports/spine_performance_baseline_0.1.1.json"))
	var p95: float = samples[int(samples.size()*0.95)]
	var rendering_adapter := RenderingServer.get_video_adapter_name()
	var report := {
		"program_version":"0.1.2.0","mode":mode,"total_instances":count,"native_instances":native_count,
		"key_instances_60hz":high_rate_count,"other_instances_30hz":count-high_rate_count,
		"visible_min":visible_min,"visible_max":visible_max,"alive_min":alive_min,"alive_max":alive_max,
		"world_width":2560,"viewport_width":1280,"camera_origin":camera_origin,
		"sample_frames":samples.size(),"mean_frame_ms":mean,"p95_frame_ms":p95,"max_frame_ms":samples.back(),
		"fps_average":1000.0/mean,"process_p95_ms":process_samples[int(process_samples.size()*0.95)],
		"native_update_calls":native_update_count,"native_update_mean_ms_per_frame":float(native_update_usec)/1000.0/samples.size(),
		"native_pose_update_calls":native_pose_update_count,"native_pose_update_mean_ms_per_frame":float(native_pose_update_usec)/1000.0/samples.size(),
		"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_objects_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"rendered_primitives_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"static_memory_increase_bytes":OS.get_static_memory_usage()-memory_before,
		"rendering_adapter":rendering_adapter,"real_renderer":not rendering_adapter.is_empty(),"baseline":baseline,
		"scope":"Real SiegeBattle logic + native animation + health rendering; seeded high HP to preserve population" if is_battle else "Independent real native animation workload; combat excluded",
		"passed":not rendering_adapter.is_empty() and native_count==count and alive_min==count and p95<33.334 and (count!=24 or 1000.0/mean>=55.0),
	}
	if is_battle:
		for key: String in ["advance","draw","rate"]:
			var measured: Array = battle.get(key+"_samples")
			measured.sort()
			var total := 0.0
			for value: float in measured: total += value
			report[key+"_calls"] = measured.size()
			report[key+"_mean_ms"] = total/measured.size() if not measured.is_empty() else 0.0
			report[key+"_p95_ms"] = measured[int(measured.size()*0.95)] if not measured.is_empty() else 0.0
			report[key+"_max_ms"] = measured.back() if not measured.is_empty() else 0.0
		if mode.contains("nodraw"): report.scope = "Diagnostic: SiegeBattle logic + native animation, health drawing suppressed; cannot substitute battle64"
	var folder := "res://reports/performance_0.1.2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder+"/"+mode+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("SPINE_PERFORMANCE_COMPLETE ",JSON.stringify(report))
	quit(0 if report.passed else 1)
