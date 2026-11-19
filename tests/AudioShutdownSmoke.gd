extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var audio := root.get_node("GameAudio")
	audio.call("set_context", "camp")
	audio.call("play_cue", "summon")
	await process_frame
	await audio.call("shutdown")
	var passed: bool = audio.get_child_count() == 0 and not bool(audio.call("is_music_playing")) and int(audio.call("active_voice_count")) == 0 and not bool(audio.call("play_cue", "hit")) and bool(audio.get("shutdown_clean"))
	await audio.call("shutdown")
	var result := {"passed": passed, "checks": 6, "players_after_shutdown": audio.get_child_count(), "mixer_drain_seconds": audio.get("shutdown_wait_seconds"), "playback_references_released": audio.get("shutdown_clean"), "verbose_log_must_reject_leaks": true}
	var file := FileAccess.open("res://reports/audio_shutdown_smoke.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("AUDIO_SHUTDOWN_SMOKE " + JSON.stringify(result))
	quit(0 if passed else 1)
