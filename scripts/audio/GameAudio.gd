class_name SiegeAudio
extends Node

signal shutdown_completed

const AUDIO_DIRECTORY := "res://assets/audio/"
const POOL_SIZE := 8
const CUE_INTERVALS := {
	"click": 0.065,
	"summon": 0.09,
	"hit": 0.12,
	"heal": 0.22,
	"pulse": 0.6,
	"warning": 0.4,
	"victory": 1.0,
	"defeat": 1.0,
	"train": 0.2,
}

var current_context := ""
var error_message := ""
var _prefs: Node
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _last_cue_ms: Dictionary = {}
var _next_voice := 0
var _shutting_down := false
var _shutdown_done := false
var _playback_refs: Array[WeakRef] = []
var shutdown_clean := false
var shutdown_wait_seconds := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cue: String in CUE_INTERVALS:
		var stream := _load_wav(AUDIO_DIRECTORY + cue + ".wav")
		if stream != null: _streams[cue] = stream
	for index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "CueVoice%d" % index
		player.max_polyphony = 1
		add_child(player)
		_pool.append(player)
	_music = AudioStreamPlayer.new()
	_music.name = "StarLanternAmbience"
	_music.max_polyphony = 1
	add_child(_music)
	var ambient := _load_wav(AUDIO_DIRECTORY + "ambient.wav")
	if ambient != null:
		ambient.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ambient.loop_begin = 0
		ambient.loop_end = int(round(ambient.get_length() * ambient.mix_rate))
		_music.stream = ambient
	if _prefs == null: configure_preferences(get_node_or_null("/root/UserPrefs"))
	else: _apply_volumes()

func _load_wav(path: String) -> AudioStreamWAV:
	# Imported projects and PCK exports use the normal Godot resource mapping.
	# A raw WAV fallback also supports a freshly copied local learning project
	# without launching an editor import pass merely to play original audio.
	var stream: AudioStreamWAV
	if (FileAccess.file_exists(path + ".import") or not FileAccess.file_exists(path)) and ResourceLoader.exists(path):
		stream = load(path) as AudioStreamWAV
	if stream == null and FileAccess.file_exists(path): stream = AudioStreamWAV.load_from_file(path)
	if stream == null: error_message = "声音文件缺失：" + path.get_file()
	return stream

func configure_preferences(prefs: Node) -> void:
	if is_instance_valid(_prefs) and _prefs.has_signal("changed") and _prefs.is_connected("changed", _apply_volumes):
		_prefs.disconnect("changed", _apply_volumes)
	_prefs = prefs
	if is_instance_valid(_prefs) and _prefs.has_signal("changed"):
		_prefs.connect("changed", _apply_volumes)
	_apply_volumes()

func _volume(key: String, fallback: float) -> float:
	return float(_prefs.call("get_value", key, fallback)) if is_instance_valid(_prefs) else fallback

func _apply_volumes() -> void:
	var master := _volume("master_volume", 0.8)
	var sfx_db := linear_to_db(maxf(master * _volume("sfx_volume", 0.7), 0.0001))
	for player: AudioStreamPlayer in _pool: player.volume_db = sfx_db
	if is_instance_valid(_music):
		_music.volume_db = linear_to_db(maxf(master * _volume("music_volume", 0.45), 0.0001))

func play_cue(cue: String) -> bool:
	if _shutting_down: return false
	if not _streams.has(cue) or _pool.is_empty(): return false
	if _volume("master_volume", 0.8) * _volume("sfx_volume", 0.7) <= 0: return false
	var now := Time.get_ticks_msec()
	if _last_cue_ms.has(cue) and now - int(_last_cue_ms[cue]) < int(ceil(float(CUE_INTERVALS[cue]) * 1000)):
		return false
	_last_cue_ms[cue] = now
	var chosen := _next_voice
	for offset in POOL_SIZE:
		var index := (_next_voice + offset) % POOL_SIZE
		if not _pool[index].playing:
			chosen = index
			break
	var player := _pool[chosen]
	player.stop()
	player.stream = _streams[cue]
	player.play()
	_track_playback(player)
	_next_voice = (chosen + 1) % POOL_SIZE
	return true

func set_context(context: String) -> void:
	if _shutting_down: return
	if context not in ["camp", "battle"]: return
	current_context = context
	if not is_instance_valid(_music) or _music.stream == null: return
	_music.pitch_scale = 0.96 if context == "camp" else 1.0
	if not _music.playing:
		_music.play()
		_track_playback(_music)

func _track_playback(player: AudioStreamPlayer) -> void:
	for index in range(_playback_refs.size() - 1, -1, -1):
		if _playback_refs[index].get_ref() == null: _playback_refs.remove_at(index)
	var playback := player.get_stream_playback()
	if playback != null: _playback_refs.append(weakref(playback))

func _has_pending_playback() -> bool:
	for reference: WeakRef in _playback_refs:
		if reference.get_ref() != null: return true
	return false

func stop() -> void:
	current_context = ""
	if is_instance_valid(_music): _music.stop()
	for player: AudioStreamPlayer in _pool: player.stop()
	_last_cue_ms.clear()

func _exit_tree() -> void:
	# Synchronous fallback. Normal window closure awaits shutdown() while the
	# SceneTree/audio mixer still runs; finalization alone is too late to drain.
	_release_audio(false)

func _release_audio(release_players: bool) -> void:
	stop()
	for player: AudioStreamPlayer in _pool:
		player.stream = null
		if release_players: player.queue_free()
	_pool.clear()
	if is_instance_valid(_music):
		_music.stream = null
		if release_players: _music.queue_free()
	_music = null
	_streams.clear()
	if is_instance_valid(_prefs) and _prefs.has_signal("changed") and _prefs.is_connected("changed", _apply_volumes):
		_prefs.disconnect("changed", _apply_volumes)
	_prefs = null

# Call before SceneTree.quit(), and await this method. AudioStreamPlayer owns
# an internal playback reference in addition to its stream. Dispose of the
# player while the mixer is alive, then wait for actual playback weak references
# to expire. A bounded asynchronous drain runs only during application shutdown.
func shutdown() -> void:
	if _shutdown_done: return
	if _shutting_down:
		await shutdown_completed
		return
	_shutting_down = true
	var started := Time.get_ticks_msec()
	_release_audio(true)
	if is_inside_tree():
		await get_tree().process_frame
		while _has_pending_playback() and Time.get_ticks_msec() - started < 1000:
			await get_tree().create_timer(0.02, true, false, true).timeout
	shutdown_clean = not _has_pending_playback()
	shutdown_wait_seconds = (Time.get_ticks_msec() - started) / 1000.0
	if not shutdown_clean: error_message = "声音结束清理超时。"
	_playback_refs.clear()
	_shutdown_done = true
	shutdown_completed.emit()

func active_voice_count() -> int:
	var result := 0
	for player: AudioStreamPlayer in _pool:
		if player.playing: result += 1
	return result

func is_music_playing() -> bool:
	return is_instance_valid(_music) and _music.playing
