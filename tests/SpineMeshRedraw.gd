extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")
const QA_CONTEXT = preload("res://scripts/core/QAStartupContext.gd")
const HOST = preload("res://scripts/core/QABackgroundHost.gd")
var background_host := HOST.new()
const SIZE := Vector2i(1000,760)
var failures: Array = []
var records: Array = []
var comparisons := 0
var unique_actions := 0
var empty_recipe_frames := 0
var max_pixel_difference := 0
var viewports: Array[SubViewport] = []
var actors: Array[SpineActor] = []
var folder := "res://reports/performance_0.1.3"
var background := false
var background_host_valid_captures := 0
var background_first_invalid_sample: Dictionary = {}
var background_started_usec := 0
var background_monitor_started := false
var background_frame_sample := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	background = args.has("background") or args.has("--background")
	background_started_usec = Time.get_ticks_usec()
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if background and background_monitor_started:
		background_frame_sample += 1
		_record_background_sample("process_frame", background_frame_sample)
	return false

func _record_background_sample(stage: String, sample: int, label: String = "") -> void:
	if not background or (root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED): return
	if background_first_invalid_sample.is_empty():
		background_first_invalid_sample = {"stage": stage, "sample": sample, "capture_label": label,
			"ticks_usec": Time.get_ticks_usec(), "elapsed_usec": Time.get_ticks_usec() - background_started_usec,
			"window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode(),
			"cause": "unknown"}
	if not failures.has("background host window was restored during capture"):
		failures.append("background host window was restored during capture")

func _run() -> void:
	if not QA_CONTEXT.enabled() or not QA_CONTEXT.valid(): failures.append("native mesh comparison requires a valid isolated QA startup")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/spine_visuals/mesh_redraw"))
	root.size = Vector2i(1280,720)
	if background:
		if not await background_host.initialize(self):
			failures.append("background comparison host initialization was not confirmed")
			await _complete({"program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
				"passed": false, "failures": failures, "background": true, "performance_measured": false,
				"resource_count": 0, "raw_animation_count": 0, "comparisons": 0, "background_host_valid_captures": 0,
				"scope": "No RGBA sampling started because host initialization failed"})
			return
		background_started_usec = int(background_host.snapshot().monitor_start_ticks_usec)
		background_monitor_started = true
		_record_background_sample("sampling_start", 0)
		if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty() or _rendering_driver()!="vulkan":
			failures.append("background pixel comparison requires a real Vulkan renderer")
			await _complete({"program_version":str(ProjectSettings.get_setting("application/config/version","unknown")),"passed":false,"failures":failures,"background":true,"performance_measured":false,"actual_rendering_method":_rendering_method(),"actual_rendering_driver":_rendering_driver(),"rendering_adapter":RenderingServer.get_video_adapter_name(),"resource_count":0,"raw_animation_count":0,"comparisons":0,"background_host_valid_captures":0,"scope":"Background Vulkan offscreen pixel verification could not start; no performance measured"})
			return
	else:
		root.mode = Window.MODE_WINDOWED
		root.visible = true
	for managed: bool in [false,true]:
		var viewport := SubViewport.new()
		viewport.size = SIZE
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewports.append(viewport)
		var actor := Actor.new()
		actor.set_managed_mesh_redraw(managed)
		actor.set_process(false)
		viewport.add_child(actor)
		actor.set_process(false)
		actors.append(actor)
	for visual_id: String in Catalog.visuals():
		var spec: Dictionary = Catalog.visuals()[visual_id]
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(spec.data).replace("actor-data.tres","actor.spine-json")))
		unique_actions += raw.animations.size()
		var model_record := {"id":visual_id,"raw_actions":raw.animations.size(),"raw_action_names":raw.animations.keys(),"skins":[],"comparisons":0,"meshes":0}
		for direction: int in [1,-1]:
			for actor: SpineActor in actors:
				actor.configure(visual_id,direction)
				actor.set_process(false)
				actor.position = Vector2(500,560)
				actor.modulate = Color.WHITE if direction==1 else Color(0.78,0.64,0.95,0.63)
				if not actor.using_spine(): failures.append("missing native " + visual_id)
				if actor._native_meshes.is_empty(): failures.append("no native meshes " + visual_id)
				for mesh: CanvasItem in actor._native_meshes:
					if mesh.is_processing_internal() == actor.get_managed_mesh_redraw(): failures.append("wrong internal processing " + visual_id)
			model_record.meshes = actors[1]._native_meshes.size()
			for skin: Dictionary in raw.skins:
				var skin_name := str(skin.name)
				if direction==1: model_record.skins.append(skin_name)
				for actor: SpineActor in actors:
					var skeleton: Object = actor.spine_sprite().call("get_skeleton")
					skeleton.call("set_skin_by_name",skin_name)
				for animation: String in raw.animations:
					var duration := maxf(_last_time(raw.animations[animation]),0.1)
					var tracks: Array = []
					for actor: SpineActor in actors:
						var sprite := actor.spine_sprite()
						var skeleton: Object = sprite.call("get_skeleton")
						skeleton.call("set_to_setup_pose")
						var state: Object = sprite.call("get_animation_state")
						if state.has_method("clear_tracks"): state.call("clear_tracks")
						else: failures.append("clear_tracks missing")
						var track: Object = state.call("set_animation",animation,false,0)
						track.call("set_time_scale",1.0)
						tracks.append(track)
					var previous := 0.0
					for fraction: float in [0.0,0.25,0.6,1.0]:
						var target := duration*fraction
						for actor: SpineActor in actors:
							actor.spine_sprite().call("update_skeleton",target-previous)
							actor.refresh_native_meshes()
						previous = target
						if absf(float(tracks[0].call("get_track_time"))-float(tracks[1].call("get_track_time")))>0.00001: failures.append("track mismatch " + visual_id + "/" + animation)
						await _compare(visual_id,skin_name,animation,direction,fraction,skin_name==str(spec.skin))
						model_record.comparisons += 1
					# Changing parent transforms/alpha without evaluating a skeleton must
					# also leave the original and cached native meshes equivalent.
					for actor: SpineActor in actors:
						actor.position += Vector2(11,3)
						actor.modulate.a *= 0.8
					await _compare(visual_id,skin_name,animation,direction,1.1,skin_name==str(spec.skin))
					model_record.comparisons += 1
					for actor: SpineActor in actors:
						actor.position = Vector2(500,560)
						actor.modulate = Color.WHITE if direction==1 else Color(0.78,0.64,0.95,0.63)
		records.append(model_record)
		print("MESH_REDRAW_ASSET ",visual_id," ",JSON.stringify(model_record))
	# Reconfigure while enabled, disable, re-enable, and freeze at one pose.
	for managed: bool in [false,true,false,true]:
		actors[1].set_managed_mesh_redraw(managed)
		for actor: SpineActor in actors:
			actor.configure("d69_097",1)
			actor.modulate = Color.WHITE
			actor.position = Vector2(500,560)
			actor.play_state("attack")
			actor.set_playback_speed(0.0)
		await _compare("d69_097","default","toggle_pause",1,0.0,true)
		if actors[1].get_managed_mesh_redraw()!=managed: failures.append("reconfigure changed policy")
	var adapter := RenderingServer.get_video_adapter_name()
	if adapter.is_empty() or DisplayServer.get_name()=="headless": failures.append("real renderer required")
	if records.size()!=21 or unique_actions!=220: failures.append("all 21 native resources and 220 raw animations required")
	var covered_ids: Array = []
	var expected_comparisons := 4
	for record: Dictionary in records:
		if covered_ids.has(record.id): failures.append("duplicate native resource " + str(record.id))
		covered_ids.append(record.id)
		var expected_model_comparisons: int = int(record.raw_actions)*int(record.skins.size())*2*5
		if record.raw_action_names.size()!=int(record.raw_actions) or int(record.comparisons)!=expected_model_comparisons: failures.append("incomplete raw action/skin comparison " + str(record.id))
		expected_comparisons += expected_model_comparisons
	if comparisons!=expected_comparisons: failures.append("incomplete RGBA comparison coverage")
	if _rendering_method()=="unknown": failures.append("actual rendering method unavailable")
	if background and (background_host_valid_captures!=comparisons or root.mode!=Window.MODE_MINIMIZED or DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED): failures.append("background host window did not stay minimized for every capture")
	var report := {"program_version":str(ProjectSettings.get_setting("application/config/version","unknown")),"passed":failures.is_empty(),"failures":failures,"rendering_adapter":adapter,"real_renderer":not adapter.is_empty() and DisplayServer.get_name()!="headless","actual_rendering_method":_rendering_method(),"production_renderer":str(ProjectSettings.get_setting("rendering/renderer/rendering_method","unknown")),"render_thread_model":_render_thread_model(),"native_visuals":records.size(),"resource_count":records.size(),"native_visual_ids":covered_ids,"unique_raw_animations":unique_actions,"raw_animation_count":unique_actions,"comparisons":comparisons,"expected_comparisons":expected_comparisons,"max_pixel_difference":max_pixel_difference,"allowed_empty_alternate_skin_frames":empty_recipe_frames,"viewport_size":[SIZE.x,SIZE.y],"scope":"Exact RGBA comparison of native and managed redraw at matching raw track poses; all skins, both facings, tint/alpha, parent transform without native evaluation, first/end frames, reconfigure/toggle/pause","models":records}
	report.background = background
	report.performance_measured = false
	report.background_host_valid_captures = background_host_valid_captures
	report.actual_rendering_driver = _rendering_driver()
	report.root_window_mode = root.mode
	report.display_window_mode = DisplayServer.window_get_mode()
	report.root_visible = root.visible
	report.root_focused = root.has_focus()
	report.capture_method = "two process frames then force_draw(false); offscreen SubViewport images" if background else "process frame then frame_post_draw; SubViewport images"
	report.viewports = []
	for viewport: SubViewport in viewports:
		report.viewports.append({"size":[viewport.size.x,viewport.size.y],"transparent_bg":viewport.transparent_bg,"disable_3d":viewport.disable_3d,"update_mode":viewport.render_target_update_mode})
	await _complete(report)

func _complete(report: Dictionary) -> void:
	report.qa_startup = QA_CONTEXT.snapshot()
	report.background_host_setup = background_host.snapshot()
	report.background_first_invalid_sample = background_first_invalid_sample
	report.background_window_frame_samples = background_frame_sample
	var file := FileAccess.open(folder+"/mesh_redraw.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	for viewport: SubViewport in viewports: viewport.queue_free()
	await process_frame
	print("SPINE_MESH_REDRAW_COMPLETE ",JSON.stringify(report))
	quit(0 if report.passed else 1)

func _rendering_method() -> String:
	if RenderingServer.has_method("get_current_rendering_method"): return str(RenderingServer.call("get_current_rendering_method"))
	for method: String in ["gl_compatibility","mobile","forward_plus"]:
		if OS.has_feature(method): return method
	return "unknown"

func _rendering_driver() -> String:
	if RenderingServer.has_method("get_current_rendering_driver_name"): return str(RenderingServer.call("get_current_rendering_driver_name")).to_lower()
	return "unknown"

func _render_thread_model() -> String:
	var command_line := OS.get_cmdline_args()
	for index: int in command_line.size():
		if command_line[index]=="--render-thread" and index+1<command_line.size(): return str(command_line[index+1])
	return {0:"unsafe",1:"safe",2:"separate"}.get(int(ProjectSettings.get_setting("rendering/driver/threads/thread_model",1)),"unknown")

func _last_time(value: Variant) -> float:
	var latest := 0.0
	if value is Dictionary:
		if value.has("time"): latest = float(value.time)
		for child: Variant in value.values(): latest = maxf(latest,_last_time(child))
	elif value is Array:
		for child: Variant in value: latest = maxf(latest,_last_time(child))
	return latest

func _compare(id: String,skin: String,animation: String,direction: int,fraction: float,required_body: bool) -> void:
	await process_frame
	if background:
		await process_frame # Flush both CanvasItem queues without presenting a host window.
		RenderingServer.force_draw(false)
		if root.mode==Window.MODE_MINIMIZED and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_MINIMIZED:
			background_host_valid_captures += 1
		else: _record_background_sample("rgba_capture", comparisons + 1, "%s/%s/%s/%s/%s" % [id,skin,animation,direction,fraction])
	else:
		await RenderingServer.frame_post_draw
	var original := viewports[0].get_texture().get_image()
	var managed := viewports[1].get_texture().get_image()
	var label := "%s/%s/%s/%s/%s" % [id,skin,animation,direction,fraction]
	comparisons += 1
	var bytes_original := original.get_data()
	var bytes_managed := managed.get_data()
	var differences := 0
	if bytes_original != bytes_managed:
		for index in bytes_original.size():
			if bytes_original[index]!=bytes_managed[index]: differences += 1
		max_pixel_difference = maxi(max_pixel_difference,differences)
		failures.append("RGBA mismatch %s: %s bytes" % [label,differences])
		if failures.size()<=6:
			var path := "res://reports/spine_visuals/mesh_redraw/failure_%s" % comparisons
			original.save_png(path+"_original.png")
			managed.save_png(path+"_managed.png")
	var original_bounds: Rect2 = actors[0].spine_sprite().call("get_skeleton").call("get_bounds")
	var managed_bounds: Rect2 = actors[1].spine_sprite().call("get_skeleton").call("get_bounds")
	var finite_original := original_bounds.position.is_finite() and original_bounds.size.is_finite()
	var finite_managed := managed_bounds.position.is_finite() and managed_bounds.size.is_finite()
	if finite_original!=finite_managed or (finite_original and not original_bounds.is_equal_approx(managed_bounds)): failures.append("bounds mismatch " + label)
	# Spine returns inf/-inf bounds for a skin that intentionally has no body
	# attachment. Pixels must still match and old skin triangles must disappear.
	if not finite_original or original_bounds.size.x<=0 or original_bounds.size.y<=0:
		if required_body: failures.append("empty configured body " + label)
		else: empty_recipe_frames += 1
	var used := original.get_used_rect()
	if used.position.x<=0 or used.position.y<=0 or used.end.x>=SIZE.x or used.end.y>=SIZE.y: failures.append("cropped image " + label)
	if direction==1 and fraction==0.6 and skin==str(actors[0].spec.skin) and ((id=="d69_163" and animation=="Active_A") or (id=="d69_084" and animation=="Attack_A") or (id=="d69_254" and animation=="Attack_A")):
		var path := "res://reports/spine_visuals/mesh_redraw/"+id+"_"+animation
		original.save_png(path+"_original.png")
		managed.save_png(path+"_managed.png")
