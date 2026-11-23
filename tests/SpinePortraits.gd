extends SceneTree

const QA_CONTEXT = preload("res://scripts/core/QAStartupContext.gd")
const HOST = preload("res://scripts/core/QABackgroundHost.gd")
var background_host := HOST.new()

class PortraitActor extends SpineActor:
	func _draw() -> void:
		pass # Native body only; the UI supplies its own backdrop and pedestal.

const CANVAS := Vector2i(2048,2048)
const MAX_OUTPUT := Vector2(1024,1280)
const MARGIN := 0.05
const DIRECTORY := "res://assets/portraits"
var failures: Array = []
var entries: Array = []
var viewport: SubViewport
var background_first_invalid_sample: Dictionary = {}
var background_started_usec := 0
var background_host_valid_captures := 0
var background_captures := 0
var background_monitor_started := false
var background_frame_samples := 0

func _initialize() -> void:
	background_started_usec = Time.get_ticks_usec()
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if background_monitor_started:
		background_frame_samples += 1
		_record_background_sample("process_frame", background_frame_samples)
	return false

func _run() -> void:
	if not QA_CONTEXT.enabled() or not QA_CONTEXT.valid(): failures.append("native portraits require a valid isolated QA startup")
	# This is an offscreen artifact renderer, never a foreground/FPS test.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if not await background_host.initialize(self):
		failures.append("background portrait host initialization was not confirmed")
		await _finish()
		return
	background_started_usec = int(background_host.snapshot().monitor_start_ticks_usec)
	background_monitor_started = true
	_record_background_sample("sampling_start", 0)
	viewport = SubViewport.new()
	viewport.size = CANVAS
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for unit_id: String in Catalog.playable_roster():
		var unit: Dictionary = Catalog.unit(unit_id)
		var visual_id := str(unit.get("visual_id",""))
		var actor := PortraitActor.new()
		viewport.add_child(actor)
		actor.configure(visual_id,1)
		actor.set_process(false)
		if not actor.using_spine() or actor.spine_sprite()==null or actor.spine_sprite().get_class()!="SpineSprite":
			failures.append("native portrait unavailable: "+unit_id+"/"+visual_id)
			actor.queue_free()
			await process_frame
			continue
		var natural := maxf(float(actor.spec.get("durations",{}).get("idle",1.0)),0.1)
		var pose_time := natural*0.25
		actor.spine_sprite().call("update_skeleton",pose_time)
		actor.refresh_native_meshes()
		actor.scale = Vector2(4,4)
		actor.position = Vector2(1024,1700)
		var initial := await _capture()
		var used := initial.get_used_rect()
		if not _valid_bounds(used,unit_id,"initial"):
			actor.queue_free()
			await process_frame
			continue
		var padded := Vector2(used.size)*(1.0+MARGIN*2.0)
		var fit := minf(MAX_OUTPUT.x/padded.x,MAX_OUTPUT.y/padded.y)
		var offset := Vector2(used.get_center())-actor.position
		actor.scale = Vector2.ONE*4.0*fit
		actor.position = Vector2(CANVAS)*0.5-offset*fit
		# Changing CanvasItem transforms preserves the same frozen native pose.
		var final_image := await _capture()
		used = final_image.get_used_rect()
		if not _valid_bounds(used,unit_id,"final"):
			actor.queue_free()
			await process_frame
			continue
		var margin := Vector2i(maxi(4,roundi(used.size.x*MARGIN)),maxi(4,roundi(used.size.y*MARGIN)))
		var crop := Rect2i(used.position-margin,used.size+margin*2)
		if crop.position.x<0 or crop.position.y<0 or crop.end.x>CANVAS.x or crop.end.y>CANVAS.y:
			failures.append("portrait margin cropped: "+unit_id)
		else:
			var portrait := final_image.get_region(crop)
			portrait.convert(Image.FORMAT_RGBA8)
			var png := unit_id+".png"
			var path := DIRECTORY+"/"+png
			if portrait.save_png(path)!=OK:
				failures.append("portrait save failed: "+unit_id)
			else:
				entries.append({"unit_id":unit_id,"visual_id":visual_id,"png":png,"sha256":FileAccess.get_sha256(path),"width":portrait.get_width(),"height":portrait.get_height(),"native":true,"nonempty":portrait.get_used_rect().size.x>0,"recipe":{"state":"idle","animation":str(actor.spec.get("animations",{}).get("idle","")),"pose_fraction":0.25,"pose_time":pose_time,"facing":1,"skin":str(actor.spec.get("skin","default")),"tint":str(actor.spec.get("tint","ffffff")),"native_facing":int(actor.spec.get("native_facing",-1)),"foot":float(actor.spec.get("foot",0.0)),"source_visual_scale":float(actor.spec.get("scale",0.5)),"root_motion_bones":actor.spec.get("root_motion_bones",[]),"root_motion_scale":float(actor.spec.get("root_motion_scale",0.0)),"render_scale_multiplier":4.0*fit,"alpha_margin_fraction":MARGIN,"native_raster_passes":2},"alpha_crop":{"x":crop.position.x,"y":crop.position.y,"width":crop.size.x,"height":crop.size.y}})
				print("PORTRAIT_SAVED ",unit_id," ",portrait.get_width(),"x",portrait.get_height())
		actor.queue_free()
		await process_frame
	await _finish()

func _finish() -> void:
	# Publish only after deferred actor/audio cleanup. Monitoring remains active
	# through these awaits so a late restoration cannot leave a stale PASS.
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	var audio_shutdown_clean := true
	if root.has_node("GameAudio"):
		var audio = root.get_node("GameAudio")
		await audio.shutdown()
		audio_shutdown_clean = bool(audio.shutdown_clean)
		if not audio_shutdown_clean: failures.append("audio cleanup did not finish before portrait manifest publication")
	var monitor_stopped_ticks_usec := 0
	if background_monitor_started:
		_record_background_sample("cleanup_complete", background_frame_samples + 1)
		background_monitor_started = false
		monitor_stopped_ticks_usec = Time.get_ticks_usec()
	var adapter := RenderingServer.get_video_adapter_name()
	if adapter.is_empty(): failures.append("real offscreen renderer required")
	if entries.size()!=12: failures.append("expected twelve native portraits, got "+str(entries.size()))
	var report := {"program_version":str(ProjectSettings.get_setting("application/config/version","unknown")),"passed":failures.is_empty(),"visuals_sha256":FileAccess.get_sha256("res://resources/visuals.json"),"rendering_adapter":adapter,"actual_rendering_method":str(RenderingServer.call("get_current_rendering_method")) if RenderingServer.has_method("get_current_rendering_method") else "unknown","offscreen_only":true,"entries":entries,"failures":failures}
	report.qa_startup = QA_CONTEXT.snapshot()
	report.background_host_setup = background_host.snapshot()
	report.background_first_invalid_sample = background_first_invalid_sample
	report.background_captures = background_captures
	report.background_host_valid_captures = background_host_valid_captures
	report.background_window_frame_samples = background_frame_samples
	report.background_monitor_stopped_ticks_usec = monitor_stopped_ticks_usec
	report.background_monitor_complete = monitor_stopped_ticks_usec > 0
	report.root_window_mode = root.mode
	report.display_window_mode = DisplayServer.window_get_mode()
	report.audio_shutdown_clean = audio_shutdown_clean
	var file := FileAccess.open(DIRECTORY+"/manifest.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	else:
		report.passed = false
		report.failures.append("could not write portrait manifest")
	print("SPINE_PORTRAITS_COMPLETE ",JSON.stringify(report))
	quit(0 if report.passed else 1)

func _capture() -> Image:
	await process_frame
	await process_frame # Flush queued CanvasItem draws without presenting a window.
	RenderingServer.force_draw(false)
	background_captures += 1
	if root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		background_host_valid_captures += 1
	else: _record_background_sample("portrait_capture", background_captures)
	return viewport.get_texture().get_image()

func _record_background_sample(stage: String, sample: int) -> void:
	if root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: return
	if background_first_invalid_sample.is_empty():
		background_first_invalid_sample = {"stage": stage, "sample": sample,
			"ticks_usec": Time.get_ticks_usec(), "elapsed_usec": Time.get_ticks_usec() - background_started_usec,
			"window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode(), "cause": "unknown"}
	if not failures.has("background portrait host was restored"):
		failures.append("background portrait host was restored")

func _valid_bounds(bounds: Rect2i,unit_id: String,phase: String) -> bool:
	if bounds.size.x<=0 or bounds.size.y<=0:
		failures.append("empty native silhouette: "+unit_id+"/"+phase)
		return false
	if bounds.position.x<=0 or bounds.position.y<=0 or bounds.end.x>=CANVAS.x or bounds.end.y>=CANVAS.y:
		failures.append("native silhouette touches capture edge: "+unit_id+"/"+phase)
		return false
	return true
