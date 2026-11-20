extends SceneTree

const PREFS = preload("res://scripts/core/UserPrefs.gd")
const AUDIO = preload("res://scripts/audio/GameAudio.gd")
const SETTINGS = preload("res://scripts/ui/SettingsPanel.gd")
const DIRECTORY := "res://tests/.user/preferences_smoke"

var failures: Array[String] = []
var checks := 0
var _changes := 0
var _closes := 0
var temporary_return_verified := false
var cold_reloaded_previous_settings := false
var retry_saved_after_failure := false

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
	var conflict_directory := ProjectSettings.globalize_path(DIRECTORY + "/temporary.json.tmp")
	if DirAccess.dir_exists_absolute(conflict_directory):
		check(DirAccess.remove_absolute(conflict_directory) == OK, "remove only the isolated empty temp-conflict directory from an interrupted run")
	for filename in ["preferences.json", "partial.json", "corrupt.json", "future.json", "external_future.json", "temporary.json"]:
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
	check(not panel.unsaved_consequence.visible and not panel._leave_button.visible, "normal settings do not offer the failed-save temporary return")
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
	check(failed_panel.unsaved_consequence.visible and failed_panel.unsaved_consequence.name == "UnsavedConsequence", "failure consequence is a visible stable control")
	check(failed_panel.unsaved_consequence.text.contains("立即生效") and failed_panel.unsaved_consequence.text.contains("若之后仍未保存"), "failure explains live values and conditional restart consequence without hover")
	check(failed_panel._leave_button.name == "LeaveWithoutSave" and failed_panel._leave_button.text == "暂不保存并返回", "temporary return names its unsaved action")
	failed_panel.call("_leave_without_save")
	check(_closes == 2, "explicit temporary return closes after failed save")
	await process_frame

	# Use a valid previous file and an isolated empty .tmp directory to reject the
	# write before any disk commit. Both live values and cold readback are observed.
	var temporary_path := DIRECTORY + "/temporary.json"
	var temporary := _new_prefs(temporary_path)
	check(bool(temporary.call("set_value", "master_volume", 0.62)) and bool(temporary.call("set_value", "music_volume", 0.31)) and bool(temporary.call("flush")), "commit the temporary-return baseline")
	var previous_values: Dictionary = temporary.get("_values").duplicate(true)
	var previous_bytes := FileAccess.get_file_as_string(temporary_path)
	var temporary_panel := SETTINGS.new()
	temporary_panel.configure(temporary, audio)
	temporary_panel.closed.connect(_count_close)
	host.add_child(temporary_panel)
	temporary_panel.call("_leave_without_save")
	check(temporary_panel.visible and _closes == 2 and not bool(temporary.get("dirty")), "temporary return is unavailable before a save failure")
	temporary_panel.volume_sliders.music_volume.value = 83
	temporary_panel.option_buttons.edge_scroll.button_pressed = false
	check(float(temporary.call("get_value", "music_volume")) == 0.83 and not bool(temporary.call("get_value", "edge_scroll")) and bool(temporary.get("dirty")), "panel changes remain live pending an explicit save")
	check(DirAccess.make_dir_absolute(conflict_directory) == OK, "create isolated temp-write conflict")
	check(not temporary_panel.close() and temporary_panel.visible and _closes == 2, "write conflict keeps the settings modal open")
	check(temporary_panel.status_label.text.contains("保存失败") and temporary_panel.unsaved_consequence.visible, "write failure separates visible error and consequence")
	check(temporary_panel.unsaved_consequence.text.contains("若之后仍未保存") and temporary_panel.unsaved_consequence.text.contains("上次已保存"), "restart statement permits a later successful save")
	check(FileAccess.get_file_as_string(temporary_path) == previous_bytes, "failed settings save preserves the original disk bytes")
	temporary_panel.volume_sliders.music_volume.value = 47
	check(float(temporary.call("get_value", "music_volume")) == 0.47 and temporary_panel.unsaved_consequence.visible and temporary_panel.unsaved_consequence.text.contains("尚未保存"), "adjusting after failure keeps consequence visible and live value current")
	check(FileAccess.get_file_as_string(temporary_path) == previous_bytes and bool(temporary.get("dirty")), "continued adjustment does not silently write or clear dirty")
	temporary_panel._leave_button.pressed.emit()
	await process_frame
	temporary_return_verified = _closes == 3 and not is_instance_valid(temporary_panel) and bool(temporary.get("dirty")) and float(temporary.call("get_value", "music_volume")) == 0.47 and not bool(temporary.call("get_value", "edge_scroll")) and FileAccess.get_file_as_string(temporary_path) == previous_bytes
	check(temporary_return_verified, "explicit temporary return keeps live values and unsaved state without an extra flush")
	var cold := _new_prefs(temporary_path)
	cold_reloaded_previous_settings = cold.get("_values") == previous_values and not bool(cold.get("dirty")) and FileAccess.get_file_as_string(temporary_path) == previous_bytes
	check(cold_reloaded_previous_settings, "a new preference instance reads the previous saved settings after temporary return")
	check(DirAccess.remove_absolute(conflict_directory) == OK, "remove the isolated empty write conflict")
	var retry_panel := SETTINGS.new()
	retry_panel.configure(temporary, audio)
	retry_panel.closed.connect(_count_close)
	host.add_child(retry_panel)
	check(retry_panel.close() and _closes == 4 and not bool(temporary.get("dirty")), "a later save can persist changes that were temporarily kept live")
	await process_frame
	var cold_after_retry := _new_prefs(temporary_path)
	retry_saved_after_failure = cold_after_retry.get("_values") == temporary.get("_values") and float(cold_after_retry.call("get_value", "music_volume")) == 0.47 and not bool(cold_after_retry.call("get_value", "edge_scroll")) and FileAccess.get_file_as_string(temporary_path) != previous_bytes
	check(retry_saved_after_failure, "conditional restart explanation matches a later successful save and cold read")
	check(cold.get("_values") == previous_values, "the first cold-read instance retains its own observed baseline")

	var future_panel := SETTINGS.new()
	future_panel.configure(future, audio)
	future_panel.closed.connect(_count_close)
	host.add_child(future_panel)
	check(not future_panel.volume_sliders.music_volume.editable and future_panel.option_buttons.edge_scroll.disabled, "future settings remain read-only in the panel")
	check(not future_panel.close() and _closes == 4 and future_panel.unsaved_consequence.visible, "future-schema save failure explains explicit return")
	check(future_panel.unsaved_consequence.text.contains("不会改写原文件") and not future_panel.unsaved_consequence.text.contains("立即生效"), "read-only consequence does not promise editable previews")
	future_panel._leave_button.pressed.emit()
	await process_frame
	check(_closes == 5 and FileAccess.get_file_as_string(future_path) == future_bytes and not bool(future.get("dirty")), "temporary return leaves future settings untouched")
	var service_panel := SETTINGS.new()
	service_panel.configure(future, audio)
	service_panel.closed.connect(_count_close)
	host.add_child(service_panel)
	service_panel.configure(null)
	check(not service_panel.volume_sliders.music_volume.editable and service_panel.option_buttons.edge_scroll.disabled, "missing preferences service disables adjustment")
	check(not service_panel.close() and service_panel.unsaved_consequence.visible and service_panel.unsaved_consequence.text.contains("不会写入设置文件"), "missing service gives an accurate non-writing return consequence")
	service_panel._leave_button.pressed.emit()
	await process_frame
	check(_closes == 6 and FileAccess.get_file_as_string(future_path) == future_bytes, "missing service temporary return performs no disk change")
	check(FileAccess.get_file_as_string(profile_path) == profile_bytes, "settings panel also leaves character save isolated")
	await audio.shutdown()
	check(audio.shutdown_clean, "audio mixer releases all playback references before exit")
	for node in [prefs, restored, recovered, partial, corrupt, future, external, failed, temporary, cold, cold_after_retry, audio, host]:
		if is_instance_valid(node): node.queue_free()
	await process_frame
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "isolated_path": DIRECTORY, "audio_driver": "headless dummy; real listening separate", "program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")), "settings_panel_sha256": FileAccess.get_sha256("res://scripts/ui/SettingsPanel.gd"), "user_prefs_sha256": FileAccess.get_sha256("res://scripts/core/UserPrefs.gd"), "temporary_return_verified": temporary_return_verified, "cold_reloaded_previous_settings": cold_reloaded_previous_settings, "retry_saved_after_failure": retry_saved_after_failure}
	write_json("res://reports/preferences_smoke.json", result)
	print("PREFERENCES_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
