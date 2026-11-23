extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")
const QA_CONTEXT = preload("res://scripts/core/QAStartupContext.gd")
var failures: Array = []
var background := false
var background_host_valid_resources := 0
var background_first_invalid_sample: Dictionary = {}
var background_started_usec := 0
var background_monitor_started := false
var background_frame_sample := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	background = args.has("background") or args.has("--background")
	background_started_usec = Time.get_ticks_usec()
	if background: root.mode = Window.MODE_MINIMIZED
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if background and background_monitor_started:
		background_frame_sample += 1
		_record_background_sample("process_frame", background_frame_sample)
	return false

func _record_background_sample(stage: String, sample: int, visual_id: String = "") -> void:
	if not background or (root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED): return
	if background_first_invalid_sample.is_empty():
		background_first_invalid_sample = {"stage": stage, "sample": sample, "visual_id": visual_id,
			"ticks_usec": Time.get_ticks_usec(), "elapsed_usec": Time.get_ticks_usec() - background_started_usec,
			"window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode(),
			"cause": "unknown"}
	if not failures.has("background playback host was restored"):
		failures.append("background playback host was restored")

func _run() -> void:
	if not QA_CONTEXT.enabled() or not QA_CONTEXT.valid(): failures.append("native playback requires a valid isolated QA startup")
	background_monitor_started = background
	_record_background_sample("run_start", 0)
	var visual_ids: Array = Catalog.visuals().keys()
	var args := OS.get_cmdline_user_args()
	var production_managed := bool(ProjectSettings.get_setting("fantasy_siege/visuals/managed_mesh_redraw",false))
	var managed := production_managed
	var policy := "production"
	var report_path := "res://reports/spine_playback.json"
	if args.has("unmanaged"):
		managed = false
		policy = "unmanaged_control"
		report_path = "res://reports/performance_0.1.3/playback_unmanaged.json"
	elif args.has("managed"):
		managed = true
		policy = "managed_candidate"
		report_path = "res://reports/performance_0.1.3/playback_managed.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	for visual_id: String in visual_ids:
		var number := visual_id.trim_prefix("d69_")
		var actor := Actor.new()
		if policy=="production":
			if actor.get_managed_mesh_redraw()!=production_managed: failures.append("Actor default differs from production policy " + number)
		else: actor.set_managed_mesh_redraw(managed)
		root.add_child(actor)
		actor.position = Vector2(640,510)
		actor.configure("d69_" + number,1)
		if not actor.using_spine(): failures.append("native unavailable " + number)
		if number == "097" and OS.get_cmdline_user_args().has("inspect"):
			print("TRACK_CLASS ",actor._current_track.get_class())
			for method: Dictionary in actor._current_track.get_method_list():
				if str(method.name).contains("time"): print("TRACK_API ",method.name)
		actor.set_process(false)
		actor.profile_native_updates = true
		for groups: int in [2,3,4]:
			actor.set_frame_group_count(groups)
			for rate: float in [30.0,60.0]:
				actor.set_update_rate(rate)
				for speed: float in [0.0,1.0,2.0]:
					actor.set_playback_speed(speed)
					for input_delta: float in [1.0/60.0,0.05]:
						if not is_instance_valid(actor._current_track): failures.append("missing track " + number)
						elif actor._current_track.has_method("get_time_scale") and actor._current_track.has_method("get_track_time"):
							if not is_equal_approx(float(actor._current_track.call("get_time_scale")),speed): failures.append("wrong track speed " + number)
							var track_before := float(actor._current_track.call("get_track_time"))
							var updates_before: int = actor.native_update_count
							for step in 4:
								actor._process(input_delta)
								await process_frame
							var scheduled_calls: int = actor.native_update_count - updates_before
							if rate <= 30 and input_delta == 0.05 and scheduled_calls > ceili(4.0/groups): failures.append("slow frames bypass groups %s for %s" % [groups,number])
							actor._flush_sample()
							var observed := float(actor._current_track.call("get_track_time")) - track_before
							var expected := 4.0 * input_delta * speed
							if absf(observed-expected) > 0.0001: failures.append("native track differs at %sx/%sHz/%s groups/%ss delta for %s" % [speed,rate,groups,input_delta,number])
							if speed == 0 and absf(observed) > 0.0001: failures.append("paused native track progressed " + number)
						else: failures.append("required native timing getters unavailable " + number)
		actor.set_playback_speed(1.0)
		actor.set_update_rate(30.0)
		actor.set_frame_group_count(4)
		for step in 8:
			if actor._sample_elapsed > 0: break
			actor._process(1.0/60.0)
			await process_frame
		var pending: float = actor._sample_elapsed
		var before_switch := float(actor._current_track.call("get_track_time"))
		actor.set_frame_group_count(3)
		if pending<=0 or not is_equal_approx(actor._sample_elapsed,pending): failures.append("group switch dropped pending time " + number)
		actor._flush_sample()
		if absf(float(actor._current_track.call("get_track_time"))-before_switch-pending)>0.0001: failures.append("group switch changed native clock " + number)
		actor.profile_native_updates = false
		actor.set_process(true)
		actor.play_state("attack",0.6)
		actor.set_playback_speed(0.0)
		await create_timer(0.05).timeout
		if actor._state != "attack": failures.append("paused action advanced " + number)
		actor.set_playback_speed(2.0)
		await create_timer(0.36).timeout
		if actor._state != "idle": failures.append("double-speed action did not complete " + number)
		actor.configure("d69_" + number,-1)
		if actor.get_frame_group_count()!=3: failures.append("reconfigure lost group setting " + number)
		if actor.get_managed_mesh_redraw()!=managed: failures.append("reconfigure lost redraw setting " + number)
		for mesh: CanvasItem in actor._native_meshes:
			if mesh.is_processing_internal()==managed: failures.append("incorrect native mesh process " + number)
		actor.set_playback_speed(1.0)
		actor.play_state("move")
		actor.set_playback_speed(0.0)
		actor.set_playback_speed(1.0)
		actor.set_playback_speed(2.0)
		actor.queue_free()
		await process_frame
		if background:
			if root.mode==Window.MODE_MINIMIZED and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED:
				background_host_valid_resources += 1
			else: _record_background_sample("native_resource", visual_ids.find(visual_id) + 1, visual_id)
	var adapter := RenderingServer.get_video_adapter_name()
	if visual_ids.size()!=21: failures.append("all 21 native resources required")
	if adapter.is_empty() or DisplayServer.get_name()=="headless" or _rendering_method()=="unknown": failures.append("real renderer and actual backend required")
	if background and _rendering_driver()!="vulkan": failures.append("background playback requires an actual Vulkan rendering driver")
	if background and (background_host_valid_resources!=visual_ids.size() or root.mode!=Window.MODE_MINIMIZED or DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED): failures.append("background host must stay minimized for every native resource")
	var report := {"program_version":str(ProjectSettings.get_setting("application/config/version","unknown")),"passed":failures.is_empty(),"failures":failures,"native_visuals":visual_ids.size(),"native_visual_ids":visual_ids,"playback_policy":policy,"production_managed_mesh_redraw":production_managed,"production_policy_override":managed!=production_managed,"managed_mesh_redraw":managed,"rendering_adapter":adapter,"real_renderer":not adapter.is_empty() and DisplayServer.get_name()!="headless","actual_rendering_method":_rendering_method(),"production_renderer":str(ProjectSettings.get_setting("rendering/renderer/rendering_method","unknown")),"render_thread_model":_render_thread_model(),"tested_speeds":[0,1,2],"tested_sample_rates":[30,60],"tested_frame_groups":[2,3,4],"tested_input_deltas":[1.0/60.0,0.05],"speed_clock":"deterministic four input deltas with real native skeleton update","action_pause_resume":"real engine frame timers","group_switch_keeps_pending_delta":true,"reconfigure_and_free":true}
	report.background = background
	report.actual_rendering_driver = _rendering_driver()
	report.performance_measured = false
	report.background_host_valid_resources = background_host_valid_resources
	report.background_first_invalid_sample = background_first_invalid_sample
	report.background_window_frame_samples = background_frame_sample
	report.qa_startup = QA_CONTEXT.snapshot()
	report.root_window_mode = root.mode
	report.display_window_mode = DisplayServer.window_get_mode()
	report.root_visible = root.visible
	report.root_focused = root.has_focus()
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("SPINE_PLAYBACK_COMPLETE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _rendering_method() -> String:
	if RenderingServer.has_method("get_current_rendering_method"): return str(RenderingServer.call("get_current_rendering_method"))
	for method: String in ["gl_compatibility","mobile","forward_plus"]:
		if OS.has_feature(method): return method
	return "unknown"

func _render_thread_model() -> String:
	var command_line := OS.get_cmdline_args()
	for index: int in command_line.size():
		if command_line[index]=="--render-thread" and index+1<command_line.size(): return str(command_line[index+1])
	return {0:"unsafe",1:"safe",2:"separate"}.get(int(ProjectSettings.get_setting("rendering/driver/threads/thread_model",1)),"unknown")

func _rendering_driver() -> String:
	if RenderingServer.has_method("get_current_rendering_driver_name"): return str(RenderingServer.call("get_current_rendering_driver_name")).to_lower()
	return "unknown"
