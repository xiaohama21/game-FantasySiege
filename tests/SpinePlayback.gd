extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actors: Array = []
	var visual_ids: Array = Catalog.visuals().keys()
	for visual_id: String in visual_ids:
		var number := visual_id.trim_prefix("d69_")
		var actor := Actor.new()
		root.add_child(actor)
		actor.position = Vector2(640,510)
		actor.configure("d69_" + number,1)
		if not actor.using_spine(): failures.append("native unavailable " + number)
		actors.append(actor)
		if number == "097" and OS.get_cmdline_user_args().has("inspect"):
			print("TRACK_CLASS ",actor._current_track.get_class())
			for method: Dictionary in actor._current_track.get_method_list():
				if str(method.name).contains("time"): print("TRACK_API ",method.name)
		actor.set_process(false)
		for rate: float in [30.0,60.0]:
			actor.set_update_rate(rate)
			for speed: float in [0.0,1.0,2.0]:
				actor.set_playback_speed(speed)
				if not is_instance_valid(actor._current_track): failures.append("missing track " + number)
				elif actor._current_track.has_method("get_time_scale") and actor._current_track.has_method("get_track_time"):
					if not is_equal_approx(float(actor._current_track.call("get_time_scale")),speed): failures.append("wrong track speed " + number)
					var track_before := float(actor._current_track.call("get_track_time"))
					for step in 4:
						actor._process(1.0/60.0)
						await process_frame
					actor._flush_sample()
					var observed := float(actor._current_track.call("get_track_time")) - track_before
					var expected := (4.0/60.0) * speed
					if absf(observed-expected) > 0.0001: failures.append("native track progression differs at %sx/%sHz for %s" % [speed,rate,number])
					if speed == 0 and absf(observed) > 0.0001: failures.append("paused native track progressed " + number)
				else: failures.append("required native timing getters unavailable " + number)
		actor.set_process(true)
		actor.play_state("attack",0.6)
		actor.set_playback_speed(0.0)
		await create_timer(0.05).timeout
		if actor._state != "attack": failures.append("paused action advanced " + number)
		actor.set_playback_speed(2.0)
		await create_timer(0.36).timeout
		if actor._state != "idle": failures.append("double-speed action did not complete " + number)
		actor.configure("d69_" + number,-1)
		actor.set_playback_speed(1.0)
		actor.play_state("move")
		actor.set_playback_speed(0.0)
		actor.set_playback_speed(1.0)
		actor.set_playback_speed(2.0)
	for actor: Node in actors: actor.queue_free()
	await process_frame
	var report := {"passed":failures.is_empty(),"failures":failures,"native_visuals":visual_ids.size(),"tested_speeds":[0,1,2],"tested_sample_rates":[30,60],"speed_clock":"deterministic 4x1/60 input delta with real native skeleton update","action_pause_resume":"real engine frame timers","reconfigure_and_free":true}
	var file := FileAccess.open("res://reports/spine_playback.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("SPINE_PLAYBACK_COMPLETE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
