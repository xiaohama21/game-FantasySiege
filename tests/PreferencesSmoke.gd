extends SceneTree

const PREFS = preload("res://scripts/core/UserPrefs.gd")
const AUDIO = preload("res://scripts/audio/GameAudio.gd")
const SETTINGS = preload("res://scripts/ui/SettingsPanel.gd")
const DIRECTORY := "res://tests/.user/preferences_smoke"

var failures: Array[String] = []
var checks := 0
var _changes := 0
var _closes := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()

func _initialize() -> void:
	call_deferred("run")

func _count_change() -> void:
	_changes += 1

func _count_close() -> void:
	_closes += 1

func _new_prefs(path: String) -> Node:
	var prefs := PREFS.new()
	prefs.configure_path(path)
	root.add_child(prefs)
	return prefs

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var path := DIRECTORY + "/preferences.json"
	for filename in ["preferences.json", "partial.json", "corrupt.json", "future.json", "external_future.json"]:
		for suffix in ["", ".bak", ".tmp"]:
			var target: String = DIRECTORY + "/" + filename + suffix
			if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	var profile_path := DIRECTORY + "/profile.json"
	write_json(profile_path, {"schema": 2, "credits": 987, "owned": ["character-sentinel"]})
	var profile_bytes := FileAccess.get_file_as_string(profile_path)
	var prefs := _new_prefs(path)
	prefs.connect("changed", _count_change)
	for key: String in PREFS.DEFAULTS:
		check(prefs.call("get_value", key) == PREFS.DEFAULTS[key], "new preference default: " + key)
	check(not FileAccess.file_exists(path), "reading defaults does not create a save")
	check(prefs.call("get_value", "unknown", "fallback") == "fallback", "unknown read fallback")
	check(not bool(prefs.call("set_value", "unknown", true)), "unknown setting rejected")
	check(not bool(prefs.call("set_value", "fullscreen", 1)), "boolean setting rejects numeric input")
	check(not bool(prefs.call("set_value", "music_volume", "loud")), "volume rejects text input")
	check(not bool(prefs.call("set_value", "music_volume", NAN)), "volume rejects nonfinite input")
	check(bool(prefs.call("set_value", "master_volume", -0.5)) and float(prefs.call("get_value", "master_volume")) == 0.0, "volume clamps lower bound")
	check(bool(prefs.call("set_value", "master_volume", 1.5)) and float(prefs.call("get_value", "master_volume")) == 1.0, "volume clamps upper bound")
	check(bool(prefs.call("set_value", "music_volume", 0.3333333333333333)), "volume accepts full float precision")
	check(bool(prefs.call("set_value", "damage_numbers", false)), "boolean change applies immediately")
	check(bool(prefs.call("set_value", "tutorial_seen", true)), "tutorial flag applies independently")
	check(_changes == 5 and bool(prefs.get("dirty")), "accepted changes emit and mark unsaved")
	check(not FileAccess.file_exists(path), "preview changes wait for explicit flush")
	check(bool(prefs.call("flush")) and not bool(prefs.get("dirty")), "first atomic commit succeeds")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(int(stored.get("schema", 0)) == 1 and stored.size() == PREFS.DEFAULTS.size() + 1, "schema1 stores only preference fields")
	check(not FileAccess.file_exists(path + ".tmp"), "successful commit consumes temp file")
	var restored := _new_prefs(path)
	check(float(restored.call("get_value", "music_volume")) == 0.3333333333333333, "full precision survives disk readback")
	check(bool(restored.call("get_value", "tutorial_seen")) and not bool(restored.call("get_value", "damage_numbers")), "flags survive restart")
	check(bool(restored.call("set_value", "sfx_volume", 0.41)) and bool(restored.call("flush")), "atomic replacement of existing Windows file succeeds")
	check(FileAccess.file_exists(path + ".bak"), "previous valid commit has backup")
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
	write_json(path, "broken-primary")
	var recovered := _new_prefs(path)
	check(float(recovered.call("get_value", "sfx_volume")) == float(backup.sfx_volume), "corrupt primary restores valid backup")
	check(not str(recovered.get("error_message")).is_empty(), "backup recovery is visible")
	check(bool(recovered.call("flush")), "recovered preferences can be committed")
	check(JSON.parse_string(FileAccess.get_file_as_string(path + ".bak")) is Dictionary, "recovery keeps a valid backup")
	write_json(DIRECTORY + "/partial.json", {"schema": 1, "fullscreen": true})
	var partial := _new_prefs(DIRECTORY + "/partial.json")
	check(bool(partial.call("get_value", "fullscreen")) and float(partial.call("get_value", "sfx_volume")) == 0.7, "missing known fields use defaults")
	write_json(DIRECTORY + "/corrupt.json", {"schema": 1, "damage_numbers": "invalid"})
	var corrupt := _new_prefs(DIRECTORY + "/corrupt.json")
	check(bool(corrupt.call("get_value", "damage_numbers")) and not str(corrupt.get("error_message")).is_empty(), "bad field type falls back with notice")
	check(bool(corrupt.call("flush")), "default recovery can repair invalid preferences")
	var future_path := DIRECTORY + "/future.json"
	write_json(future_path, {"schema": 2, "new_preferences": ["preserve-me"]})
	var future_bytes := FileAccess.get_file_as_string(future_path)
	var future := _new_prefs(future_path)
	check(not bool(future.call("can_save")), "future preferences are protected")
	check(not bool(future.call("set_value", "master_volume", 0.1)) and not bool(future.call("flush")), "future preferences reject write")
	check(FileAccess.get_file_as_string(future_path) == future_bytes, "future preference bytes remain unchanged")
	var external_path := DIRECTORY + "/external_future.json"
	var external := _new_prefs(external_path)
	write_json(external_path, {"schema": 9, "sentinel": "other-running-version"})
	var external_bytes := FileAccess.get_file_as_string(external_path)
	check(not bool(external.call("flush")) and FileAccess.get_file_as_string(external_path) == external_bytes, "flush rechecks externally written future schema")
	var failed := _new_prefs(DIRECTORY + "/missing_parent/preferences.json")
	check(bool(failed.call("set_value", "damage_numbers", false)) and not bool(failed.call("flush")), "unwritable path fails explicit flush")
	check(not bool(failed.call("get_value", "damage_numbers")) and bool(failed.get("dirty")), "failed save retains runtime preview for retry")
	check(not str(failed.get("error_message")).is_empty(), "write failure explains unsaved runtime settings")
	check(FileAccess.get_file_as_string(profile_path) == profile_bytes, "preference operations never touch character save")

	# The same generated WAV resources and player code used by the game are read
	# here through Godot's dummy headless audio driver; listening is a separate QA.
	var audio := AUDIO.new()
	audio.configure_preferences(recovered)
	root.add_child(audio)
	check(audio.error_message.is_empty() and audio._streams.size() == 9, "all nine original cues load without editor import")
	check(audio.get_child_count() == AUDIO.POOL_SIZE + 1, "fixed eight voices and single music player")
	var music: AudioStreamPlayer = audio.get_node("StarLanternAmbience")
	var ambient: AudioStreamWAV = music.stream
	check(ambient != null and is_equal_approx(ambient.get_length(), 24.0), "original ambient length is 24 seconds")
	check(ambient.loop_mode == AudioStreamWAV.LOOP_FORWARD and ambient.loop_end == 24 * 22050, "ambient loops full PCM sample range")
	check(not audio.play_cue("unknown"), "unknown audio cue safely ignored")
	check(audio.play_cue("hit"), "first hit plays")
	check(not audio.play_cue("hit"), "immediate repeated hit throttled")
	for cue: String in AUDIO.CUE_INTERVALS:
		if cue != "hit": check(audio.play_cue(cue), "named cue plays: " + cue)
	check(audio.active_voice_count() <= AUDIO.POOL_SIZE and audio.get_child_count() == AUDIO.POOL_SIZE + 1, "more cue requests reuse bounded pool")
	recovered.call("set_value", "master_volume", 0.5)
	recovered.call("set_value", "music_volume", 0.4)
	recovered.call("set_value", "sfx_volume", 0.6)
	check(is_equal_approx(db_to_linear(music.volume_db), 0.2), "master and music volumes multiply")
	check(is_equal_approx(db_to_linear(audio._pool[0].volume_db), 0.3), "master and effect volumes multiply")
	audio.set_context("camp")
	check(audio.current_context == "camp" and audio.is_music_playing(), "camp starts looping ambience")
	audio.set_context("unknown")
	check(audio.current_context == "camp", "unknown context does not change music")
	audio.set_context("battle")
	check(audio.current_context == "battle" and audio.is_music_playing(), "battle reuses single ambience player")
	recovered.call("set_value", "master_volume", 0.0)
	check(not audio.play_cue("summon") and audio._pool[0].volume_db <= -79.9, "zero master mutes pool and skips new cues")
	audio.stop()
	check(not audio.is_music_playing() and audio.active_voice_count() == 0, "stop stops all players")
	recovered.call("set_value", "master_volume", 0.5)
	check(audio.play_cue("hit"), "stop clears cue throttle for a new session")
	audio.stop()

	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var panel := SETTINGS.new()
	panel.configure(recovered, audio)
	panel.closed.connect(_count_close)
	host.add_child(panel)
	check(panel.volume_sliders.size() == 3 and panel.option_buttons.size() == 3, "settings exposes three volumes and display/input flags")
	panel.volume_sliders.music_volume.value = 25
	check(float(recovered.call("get_value", "music_volume")) == 0.25, "settings slider updates live preference")
	panel.option_buttons.edge_scroll.button_pressed = false
	check(not bool(recovered.call("get_value", "edge_scroll")), "settings checkbox updates live preference")
	check(panel.close() and _closes == 1, "successful panel close saves then emits closed")
	await process_frame
	check(not is_instance_valid(panel), "closed panel releases its nodes")
	var failed_panel := SETTINGS.new()
	failed_panel.configure(failed, audio)
	failed_panel.closed.connect(_count_close)
	host.add_child(failed_panel)
	check(not failed_panel.close() and _closes == 1 and failed_panel.visible, "save failure keeps modal open without closed signal")
	check(failed_panel.status_label.text.contains("保存失败") and failed_panel._leave_button.visible, "failure gives clear message and explicit temporary return")
	failed_panel.call("_leave_without_save")
	check(_closes == 2, "explicit temporary return closes after failed save")
	await process_frame
	check(FileAccess.get_file_as_string(profile_path) == profile_bytes, "settings panel also leaves character save isolated")
	await audio.shutdown()
	check(audio.shutdown_clean, "audio mixer releases all playback references before exit")
	for node in [prefs, restored, recovered, partial, corrupt, future, external, failed, audio, host]:
		if is_instance_valid(node): node.queue_free()
	await process_frame
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "isolated_path": DIRECTORY, "audio_driver": "headless dummy; real listening separate"}
	write_json("res://reports/preferences_smoke.json", result)
	print("PREFERENCES_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
