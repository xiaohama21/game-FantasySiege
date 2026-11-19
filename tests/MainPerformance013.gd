extends SceneTree

var app
var failures: Array = []
var manual_gate := false
var gate_wait_ms := 0
var gate_path := ""
var ready_path := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "main64"
	manual_gate = args.has("manual_gate")
	var count := 24 if mode.contains("24") else 64
	var production_managed := bool(ProjectSettings.get_setting("fantasy_siege/visuals/managed_mesh_redraw",false))
	var expected_managed := production_managed
	if mode.contains("unmanaged"): expected_managed = false
	elif mode.contains("managed"): expected_managed = true
	var expected_groups := int(ProjectSettings.get_setting("fantasy_siege/visuals/frame_group_count",2))
	var critical_limit := int(ProjectSettings.get_setting("fantasy_siege/visuals/critical_instance_limit",12))
	var production_renderer := str(ProjectSettings.get_setting("rendering/renderer/rendering_method","unknown"))
	var project_thread_model := int(ProjectSettings.get_setting("rendering/driver/threads/thread_model",1))
	var version := str(ProjectSettings.get_setting("application/config/version","unknown"))
	var series := version.get_slice(".",0)+"."+version.get_slice(".",1)+"."+version.get_slice(".",2)
	var folder := "res://reports/performance_"+series
	var isolation := "res://tests/.user/"+mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolation))
	gate_path = isolation+"/measure.ready"
	ready_path = isolation+"/performance_ready.json"
	for stale_path: String in [gate_path,ready_path]:
		if FileAccess.file_exists(stale_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(stale_path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/runtime"))
	root.size = Vector2i(1280,720)
	root.mode = Window.MODE_WINDOWED
	root.visible = true
	root.grab_focus()
	var profile := root.get_node("ProfileStore")
	var prefs := root.get_node("UserPrefs")
	for name: String in ["profile.json","preferences.json"]:
		for suffix: String in ["",".bak",".tmp"]:
			var path := isolation+"/"+name+suffix
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	profile.configure_path(isolation+"/profile.json")
	profile.load_profile()
	prefs.configure_path(isolation+"/preferences.json")
	# Skip the once-only teaching modal; retain the normal audio, damage-number,
	# edge-scroll and window defaults in this isolated preferences file.
	prefs.set_value("tutorial_seen",true)
	prefs.flush()
	var memory_before := OS.get_static_memory_usage()
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	root.warp_mouse(Vector2(640,360))
	app.start_stage("stage_01")
	if not is_instance_valid(app.battle):
		failures.append("actual Main did not start the unlocked first stage")
		await _finish(folder,mode,{"passed":false,"failures":failures,"program_version":version})
		return
	if not app.battle.seed_performance_units(count): failures.append("high HP performance fixture failed")
	if mode.contains("2x"): app._toggle_speed()
	var actors: Array = []
	for unit: Dictionary in app.battle.units: actors.append(unit.visual)
	if expected_managed!=production_managed:
		for actor: SpineActor in actors: actor.set_managed_mesh_redraw(expected_managed)
	# Let the normal 12-second narrative panel expire before sampling. This
	# also warms the actual Main, shaders, audio loops, HUD and combat effects.
	await create_timer(12.3).timeout
	for warmup in 30: await process_frame
	root.always_on_top = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.visible = true
	var gpu_before := "not queried: manual gate waits without auxiliary processes"
	if manual_gate:
		var gate_received: bool = await _wait_measure_gate(mode,version)
		if not gate_received:
			if gate_wait_ms>=120000: failures.append("manual measure gate timed out after 120 seconds")
			await _finish(folder,mode,{"passed":false,"failures":failures,"program_version":version,"mode":mode,"manual_gate":true,"gate_path":ProjectSettings.globalize_path(gate_path),"ready_path":ProjectSettings.globalize_path(ready_path),"gate_wait_ms":gate_wait_ms})
			return
	else:
		root.grab_focus()
		gpu_before = _gpu_status()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		root.grab_focus()
	for settling in 30: await process_frame
	if app.paused or is_instance_valid(app.settings_panel) or is_instance_valid(app.guide_panel): failures.append("unexpected pause/modal in Main measurement")
	if app.intro_time>0: failures.append("narrative warmup did not expire")
	for actor: SpineActor in actors:
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
	var hud_frames := 0
	var maximum_live_motes := 0
	var focused_frames := 0
	var normal_window_frames := 0
	var full_resolution_frames := 0
	var budget_valid_frames := 0
	var native_min := count
	var native_max := 0
	var managed_min := count
	var managed_max := 0
	var key_min := count
	var key_max := 0
	var low_min := count
	var low_max := 0
	var group_counts_min := {"2":count,"3":count,"4":count}
	var group_counts_max := {"2":0,"3":0,"4":0}
	var previous := Time.get_ticks_usec()
	for frame in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
		process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		if root.has_focus(): focused_frames += 1
		if root.mode==Window.MODE_WINDOWED and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED and root.visible:
			normal_window_frames += 1
		if root.size==Vector2i(1280,720) and DisplayServer.window_get_size()==Vector2i(1280,720):
			full_resolution_frames += 1
		var budget := _visual_budget(actors,count,expected_managed,expected_groups,critical_limit)
		visible_min=mini(visible_min,int(budget.visible))
		visible_max=maxi(visible_max,int(budget.visible))
		native_min=mini(native_min,int(budget.native))
		native_max=maxi(native_max,int(budget.native))
		managed_min=mini(managed_min,int(budget.managed))
		managed_max=maxi(managed_max,int(budget.managed))
		key_min=mini(key_min,int(budget.critical))
		key_max=maxi(key_max,int(budget.critical))
		low_min=mini(low_min,int(budget.low))
		low_max=maxi(low_max,int(budget.low))
		for group: String in group_counts_min:
			group_counts_min[group]=mini(int(group_counts_min[group]),int(budget.groups[group]))
			group_counts_max[group]=maxi(int(group_counts_max[group]),int(budget.groups[group]))
		var alive: int = app.battle.active_count()
		alive_min=mini(alive_min,alive)
		alive_max=maxi(alive_max,alive)
		if bool(budget.valid) and alive==count: budget_valid_frames += 1
		if is_instance_valid(app.energy_label) and app.energy_label.is_visible_in_tree() and is_instance_valid(app.player_hp) and is_instance_valid(app.enemy_hp): hud_frames += 1
		var live_motes := 0
		for mote: Dictionary in app.motes:
			if float(mote.life)>0 and is_instance_valid(mote.node) and mote.node.visible: live_motes += 1
		maximum_live_motes=maxi(maximum_live_motes,live_motes)
	samples.sort()
	process_samples.sort()
	var mean := 0.0
	for value: float in samples: mean += value
	mean /= samples.size()
	var p95: float = samples[int(samples.size()*0.95)]
	var native_count := 0
	var managed_count := 0
	var key_count := 0
	var native_calls := 0
	var native_usec := 0
	var pose_calls := 0
	var pose_usec := 0
	var groups := {"2":0,"3":0,"4":0}
	for actor: SpineActor in actors:
		if not is_instance_valid(actor): continue
		if actor.using_spine(): native_count += 1
		if actor.get_managed_mesh_redraw(): managed_count += 1
		if actor._update_rate>30: key_count += 1
		else: groups[str(actor.get_frame_group_count())] += 1
		native_calls += actor.native_update_count
		native_usec += actor.native_update_usec
		pose_calls += actor.native_pose_update_count
		pose_usec += actor.native_pose_update_usec
	var adapter := RenderingServer.get_video_adapter_name()
	if adapter.is_empty() or DisplayServer.get_name()=="headless": failures.append("real display and graphics adapter required")
	if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_WINDOWED or not root.visible: failures.append("normal visible window required; minimized results do not satisfy delivery")
	if focused_frames!=samples.size(): failures.append("focused foreground window required for every measured frame")
	if normal_window_frames!=samples.size(): failures.append("normal visible root and display window required for every measured frame")
	if full_resolution_frames!=samples.size(): failures.append("full 1280x720 root and display window required for every measured frame")
	if _rendering_driver()!="vulkan": failures.append("actual Vulkan rendering driver required for production performance")
	if expected_groups<2 or expected_groups>4 or critical_limit<1: failures.append("invalid production animation budget")
	if budget_valid_frames!=samples.size(): failures.append("native population, managed redraw or animation budget differed during measurement")
	if _render_thread_model()!="safe": failures.append("Safe render thread required; experimental Separate cannot satisfy production gate")
	if native_count!=count or alive_min!=count or visible_min!=count: failures.append("full native alive visible population was not preserved")
	if hud_frames!=samples.size() or not is_instance_valid(app.world) or not app.world.is_visible_in_tree(): failures.append("actual Main HUD/background missing")
	if not bool(prefs.get_value("damage_numbers",false)): failures.append("damage numbers were disabled")
	if maximum_live_motes==0: failures.append("no actual combat floating numbers observed")
	if p95>=33.334 or (count==24 and 1000.0/mean<55.0): failures.append("original frame-time/FPS gate failed")
	await RenderingServer.frame_post_draw
	var screenshot_path := "res://reports/runtime/"+mode+".png"
	if root.get_texture().get_image().save_png(screenshot_path)!=OK: failures.append("Main screenshot could not be saved")
	var report := {"program_version":version,"mode":mode,"passed":failures.is_empty(),"failures":failures,"scope":"Actual Main.tscn first-stage combat + native animations + complete HUD/health bars + WorldBackdrop + normal audio and floating damage numbers; high HP fixture preserves population; one-time tutorial skipped in isolated preferences","coordinated_exclusive":args.has("exclusive"),"cpu_name":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"rendering_adapter":adapter,"real_renderer":not adapter.is_empty(),"total_instances":count,"native_instances":native_count,"managed_mesh_instances":managed_count,"visible_min":visible_min,"visible_max":visible_max,"alive_min":alive_min,"alive_max":alive_max,"key_instances_60hz":key_count,"low_priority_frame_groups":groups,"sample_frames":samples.size(),"mean_frame_ms":mean,"p95_frame_ms":p95,"max_frame_ms":samples.back(),"fps_average":1000.0/mean,"process_p95_ms":process_samples[int(process_samples.size()*0.95)],"native_update_calls":native_calls,"native_update_mean_ms_per_frame":float(native_usec)/1000.0/samples.size(),"native_pose_update_calls":pose_calls,"native_pose_update_mean_ms_per_frame":float(pose_usec)/1000.0/samples.size(),"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"rendered_objects_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"rendered_primitives_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"static_memory_increase_bytes":OS.get_static_memory_usage()-memory_before,"hud_visible_frames":hud_frames,"maximum_live_floating_numbers":maximum_live_motes,"preferences":{"master_volume":prefs.get_value("master_volume"),"music_volume":prefs.get_value("music_volume"),"sfx_volume":prefs.get_value("sfx_volume"),"damage_numbers":prefs.get_value("damage_numbers"),"edge_scroll":prefs.get_value("edge_scroll"),"tutorial_seen":prefs.get_value("tutorial_seen")},"screenshot":screenshot_path}
	report.process_id = OS.get_process_id()
	report.command_line = OS.get_cmdline_args()
	report.vsync_mode = DisplayServer.window_get_vsync_mode()
	report.display_window_size = str(DisplayServer.window_get_size())
	report.viewport_size = str(root.size)
	report.window_mode = DisplayServer.window_get_mode()
	report.window_visible = root.visible
	report.temporary_always_on_top = root.always_on_top
	report.engine_max_fps = Engine.max_fps
	report.playback_multiplier = app.speed
	report.actual_rendering_method = _rendering_method()
	report.actual_rendering_driver = _rendering_driver()
	report.production_renderer = production_renderer
	report.project_render_thread_model = project_thread_model
	report.render_thread_model = _render_thread_model()
	report.production_managed_mesh_redraw = production_managed
	report.production_frame_group_count = expected_groups
	report.critical_instance_limit = critical_limit
	report.production_policy_override = expected_managed!=production_managed
	report.native_instances_min = native_min
	report.native_instances_max = native_max
	report.managed_instances_min = managed_min
	report.managed_instances_max = managed_max
	report.key_instances_60hz_min = key_min
	report.key_instances_60hz_max = key_max
	report.low_priority_instances_min = low_min
	report.low_priority_instances_max = low_max
	report.low_priority_update_hz = 30
	report.frame_group_counts_min = group_counts_min
	report.frame_group_counts_max = group_counts_max
	report.budget_valid_frames = budget_valid_frames
	report.focused_frames = focused_frames
	report.normal_window_frames = normal_window_frames
	report.full_resolution_frames = full_resolution_frames
	report.gpu_status_before_measurement = gpu_before
	report.gpu_status_after_measurement = "not queried: manual measurement has no auxiliary processes" if manual_gate else _gpu_status()
	report.manual_gate = manual_gate
	report.gate_path = ProjectSettings.globalize_path(gate_path)
	report.ready_path = ProjectSettings.globalize_path(ready_path)
	report.gate_wait_ms = gate_wait_ms
	await _finish(folder,mode,report)

func _visual_budget(actors: Array,count: int,managed_policy: bool,groups_policy: int,critical_limit: int) -> Dictionary:
	var result := {"native":0,"visible":0,"managed":0,"critical":0,"low":0,"groups":{"2":0,"3":0,"4":0},"valid":true}
	for actor: SpineActor in actors:
		if not is_instance_valid(actor):
			result.valid = false
			continue
		if actor.using_spine(): result.native += 1
		if actor.is_visible_in_tree() and actor.global_position.x>=-80 and actor.global_position.x<=1360: result.visible += 1
		if actor.get_managed_mesh_redraw(): result.managed += 1
		if actor.get_managed_mesh_redraw()!=managed_policy or actor.get_frame_group_count()!=groups_policy: result.valid = false
		if is_equal_approx(actor._update_rate,60.0): result.critical += 1
		elif is_equal_approx(actor._update_rate,30.0):
			result.low += 1
			var group := str(actor.get_frame_group_count())
			if result.groups.has(group): result.groups[group] += 1
			else: result.valid = false
		else: result.valid = false
	# The battle's declared priority and the native Actor's effective rate must
	# agree. Checking every sample prevents a brief policy switch being hidden
	# by the final frame's population summary.
	for unit: Dictionary in app.battle.units:
		if not bool(unit.alive): continue
		if not is_instance_valid(unit.visual) or not is_equal_approx(float(unit.visual_update_rate),float(unit.visual._update_rate)): result.valid = false
	var required_critical := mini(critical_limit,count)
	var required_managed := count if managed_policy else 0
	result.valid = bool(result.valid) and int(result.native)==count and int(result.visible)==count and int(result.managed)==required_managed and int(result.critical)==required_critical and int(result.low)==count-required_critical
	return result

func _wait_measure_gate(mode: String,version: String) -> bool:
	var ready := {"program_version":version,"mode":mode,"phase":"ready","manual_gate":true,"process_id":OS.get_process_id(),"godot_window_id":root.get_window_id(),"window_title":root.title,"window_mode":DisplayServer.window_get_mode(),"window_visible":root.visible,"actual_rendering_method":_rendering_method(),"actual_rendering_driver":_rendering_driver(),"gate_path":ProjectSettings.globalize_path(gate_path),"ready_path":ProjectSettings.globalize_path(ready_path),"timeout_seconds":120}
	var file := FileAccess.open(ready_path,FileAccess.WRITE)
	if file==null:
		failures.append("could not write manual-gate readiness report")
		return false
	file.store_string(JSON.stringify(ready,"\t"))
	file.close()
	print("MAIN_PERFORMANCE_READY ",JSON.stringify(ready))
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<120000:
		if FileAccess.file_exists(gate_path):
			gate_wait_ms = Time.get_ticks_msec()-started
			return true
		# Yield while the actual Main continues animating, drawing and playing
		# audio. Only the human/computer-use focus handoff writes this signal.
		await create_timer(0.1).timeout
	gate_wait_ms = Time.get_ticks_msec()-started
	return false

func _gpu_status() -> String:
	if not OS.get_cmdline_user_args().has("gpu_diag"): return "not queried: no auxiliary process in stable benchmark"
	var path := "C:/Windows/System32/nvidia-smi.exe"
	if not FileAccess.file_exists(path): return "nvidia-smi unavailable"
	var output: Array = []
	OS.execute(path,["--query-gpu=name,temperature.gpu,utilization.gpu,clocks.gr,clocks.mem,pstate","--format=csv,noheader"],output,true)
	return "\n".join(output)

func _rendering_method() -> String:
	if RenderingServer.has_method("get_current_rendering_method"):
		return str(RenderingServer.call("get_current_rendering_method"))
	for method: String in ["gl_compatibility","mobile","forward_plus"]:
		if OS.has_feature(method): return method
	return "unknown; inspect captured graphics initialization and CLI environment"

func _render_thread_model() -> String:
	var command_line := OS.get_cmdline_args()
	for index: int in command_line.size():
		if command_line[index]=="--render-thread" and index+1<command_line.size(): return str(command_line[index+1])
	var model := int(ProjectSettings.get_setting("rendering/driver/threads/thread_model",1))
	return {0:"unsafe",1:"safe",2:"separate"}.get(model,"unknown")

func _rendering_driver() -> String:
	if RenderingServer.has_method("get_current_rendering_driver_name"): return str(RenderingServer.call("get_current_rendering_driver_name")).to_lower()
	return "unknown"

func _finish(folder: String,mode: String,report: Dictionary) -> void:
	root.always_on_top = false
	if is_instance_valid(app):
		app._stop_battle()
		app.queue_free()
		await process_frame
	await root.get_node("GameAudio").shutdown()
	var file := FileAccess.open(folder+"/"+mode+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("MAIN_PERFORMANCE_COMPLETE ",JSON.stringify(report))
	quit(0 if report.passed else 1)
