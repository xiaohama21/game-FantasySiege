class_name SpineActor
extends Node2D

## Visual playback only. Combat hit timing never depends on animation events.
static var _resources: Dictionary = {}
static var _catalog: Dictionary = {}
static var _checked_textures: Dictionary = {}
static var _next_sample_lane := 0
var visual_id := ""
var facing := 1
var spec: Dictionary = {}
var _sprite: Node2D
var _state := ""
var _remaining := 0.0
var _spine_ok := false
var _configured := false
var _playback_speed := 1.0
var _track_scale := 1.0
var _current_track: Object
var _update_rate := 60.0
var _sample_elapsed := 0.0
var _sample_until := 0.0
var _sample_lane := 0
var _sample_index := 0
var _frame_group_count := 2
var _root_motion_cache: Array = []
var _managed_mesh_redraw := false
var _native_meshes: Array[CanvasItem] = []
var profile_native_updates := false
var native_update_count := 0
var native_update_usec := 0
var native_pose_update_count := 0
var native_pose_update_usec := 0

func _init() -> void:
	_frame_group_count = clampi(int(ProjectSettings.get_setting("fantasy_siege/visuals/frame_group_count", 2)), 2, 4)
	_managed_mesh_redraw = bool(ProjectSettings.get_setting("fantasy_siege/visuals/managed_mesh_redraw", false))
	_sample_index = _next_sample_lane
	_sample_lane = _sample_index % _frame_group_count
	_next_sample_lane += 1

func _ready() -> void:
	if _configured: _build()

func configure(id: String, direction: int = 1) -> void:
	visual_id = id
	facing = 1 if direction >= 0 else -1
	if _catalog.is_empty() and FileAccess.file_exists("res://resources/visuals.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visuals.json"))
		if parsed is Dictionary: _catalog = parsed
	spec = _catalog.get(id, {}).duplicate(true)
	_configured = true
	if is_inside_tree(): _build()

func _build() -> void:
	_current_track = null
	_root_motion_cache.clear()
	_native_meshes.clear()
	_sample_elapsed = 0.0
	_sample_until = (float(get_instance_id() % 7) / 7.0) / _update_rate
	if is_instance_valid(_sprite):
		remove_child(_sprite)
		_sprite.queue_free()
	_sprite = null
	_spine_ok = false
	_state = ""
	var path := str(spec.get("data", ""))
	if not path.is_empty() and ClassDB.class_exists("SpineSprite") and ResourceLoader.exists(path) and _dependencies_ready(path):
		if not _resources.has(path): _resources[path] = load(path)
		var data: Resource = _resources.get(path)
		if data != null:
			_sprite = ClassDB.instantiate("SpineSprite") as Node2D
			_sprite.set("skeleton_data_res", data)
			add_child(_sprite)
			_sprite.call("set_update_mode", 2)
			var skeleton: Object = _sprite.call("get_skeleton")
			if skeleton != null:
				skeleton.call("set_skin_by_name", str(spec.get("skin", "default")))
				if skeleton.has_method("set_slots_to_setup_pose"): skeleton.call("set_slots_to_setup_pose")
				elif skeleton.has_method("set_to_setup_pose"): skeleton.call("set_to_setup_pose")
				_spine_ok = true
				_sprite.position.y = float(spec.get("foot", 0))
				var visual_scale := float(spec.get("scale", 0.5))
				_sprite.scale = Vector2(visual_scale * facing * int(spec.get("native_facing", -1)), visual_scale)
				_sprite.modulate = Color(str(spec.get("tint", "ffffff")))
				for name: Variant in spec.get("root_motion_bones", []):
					var bone: Object = skeleton.call("find_bone", str(name))
					if bone == null: continue
					var pose: Object = bone.call("get_pose")
					var setup: Object = bone.call("get_data").call("get_setup_pose")
					_root_motion_cache.append({"pose":pose,"x":float(setup.call("get_x")),"y":float(setup.call("get_y"))})
				if not _root_motion_cache.is_empty() and _sprite.has_signal("before_world_transforms_change"):
					_sprite.connect("before_world_transforms_change", _limit_root_motion)
				_cache_native_meshes(_sprite)
				_apply_mesh_redraw_policy()
	play_state("idle")
	queue_redraw()

func _dependencies_ready(data_path: String) -> bool:
	## The native atlas loader can crash on an unimported page. Check before
	## constructing native skeleton data; bootstrap imports textures first.
	var atlas_path := data_path.replace("actor-data.tres", "actor.atlas")
	if not FileAccess.file_exists(atlas_path): return false
	var previous_blank := true
	for raw: String in FileAccess.get_file_as_string(atlas_path).split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			previous_blank = true
			continue
		if previous_blank and not line.contains(":"):
			var page := atlas_path.get_base_dir().path_join(line)
			if not _checked_textures.has(page):
				if not ResourceLoader.exists(page): return false
				var texture: Resource = ResourceLoader.load(page, "Texture2D")
				if texture == null: return false
				_checked_textures[page] = texture
		previous_blank = false
	return true

func using_spine() -> bool:
	return _spine_ok

func spine_sprite() -> Node2D:
	return _sprite

func _limit_root_motion(actor: Node2D) -> void:
	var factor := float(spec.get("root_motion_scale", 0.0))
	for cached: Dictionary in _root_motion_cache:
		var pose: Object = cached.pose
		pose.call("set_x", cached.x + (float(pose.call("get_x")) - cached.x) * factor)
		pose.call("set_y", cached.y + (float(pose.call("get_y")) - cached.y) * factor)

func play_state(state: String, duration: float = 0.0) -> void:
	if state == _state: return
	_flush_sample()
	_state = state
	_remaining = 0.0
	if not _spine_ok: return
	var animation := str(spec.get("animations", {}).get(state, ""))
	if animation.is_empty(): return
	var loop := state in ["idle", "move"]
	var animation_state: Object = _sprite.call("get_animation_state")
	var track: Object = animation_state.call("set_animation", animation, loop, 0)
	if track == null: return
	_current_track = track
	var natural := float(spec.get("durations", {}).get(state, 0.5))
	_track_scale = natural / duration if duration > 0 and natural > 0 else 1.0
	track.call("set_time_scale", _track_scale * _playback_speed)
	if not loop and state != "death": _remaining = duration if duration > 0 else maxf(natural, 0.1)
	var started := Time.get_ticks_usec() if profile_native_updates else 0
	_sprite.call("update_skeleton", 0.0)
	refresh_native_meshes()
	if profile_native_updates:
		native_pose_update_count += 1
		native_pose_update_usec += Time.get_ticks_usec() - started

func _process(delta: float) -> void:
	if _spine_ok and _playback_speed > 0:
		_sample_elapsed += delta
		_sample_until -= delta
		var eligible_frame := _update_rate > 30.0 or Engine.get_process_frames() % _frame_group_count == _sample_lane
		if _sample_until <= 0 and eligible_frame:
			_flush_sample()
			_sample_until += 1.0 / _update_rate
			if _sample_until <= 0: _sample_until = 1.0 / _update_rate
	if _remaining > 0:
		_remaining -= delta * _playback_speed
		if _remaining <= 0: play_state("idle")

func set_playback_speed(multiplier: float) -> void:
	_flush_sample()
	_playback_speed = maxf(multiplier, 0.0)
	if _spine_ok and is_instance_valid(_current_track):
		_current_track.call("set_time_scale", _track_scale * _playback_speed)

func set_update_rate(hz: float) -> void:
	var previous_rate := _update_rate
	_update_rate = clampf(hz, 1.0, 60.0)
	_sample_until = clampf(_sample_until * previous_rate / _update_rate, 0.0, 1.0 / _update_rate)

func set_frame_group_count(groups: int) -> void:
	_frame_group_count = clampi(groups, 2, 4)
	_sample_lane = _sample_index % _frame_group_count

func get_frame_group_count() -> int:
	return _frame_group_count

func set_managed_mesh_redraw(enabled: bool) -> void:
	_managed_mesh_redraw = enabled
	_apply_mesh_redraw_policy()

func get_managed_mesh_redraw() -> bool:
	return _managed_mesh_redraw

func _cache_native_meshes(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child.get_class() == "SpineMesh2D" and child is CanvasItem:
			_native_meshes.append(child)
		_cache_native_meshes(child)

func _apply_mesh_redraw_policy() -> void:
	for mesh: CanvasItem in _native_meshes:
		if not is_instance_valid(mesh): continue
		mesh.set_process_internal(not _managed_mesh_redraw)
		mesh.queue_redraw()

func refresh_native_meshes() -> void:
	## Refresh every slot, including now-empty ones, so old triangles disappear.
	## CanvasItem transforms remain independent of native geometry refreshes.
	if not _managed_mesh_redraw: return
	for mesh: CanvasItem in _native_meshes:
		if is_instance_valid(mesh): mesh.queue_redraw()

func _flush_sample() -> void:
	if _spine_ok and _sample_elapsed > 0:
		var started := Time.get_ticks_usec() if profile_native_updates else 0
		_sprite.call("update_skeleton", _sample_elapsed)
		refresh_native_meshes()
		if profile_native_updates:
			native_update_count += 1
			native_update_usec += Time.get_ticks_usec() - started
	_sample_elapsed = 0.0

func _draw() -> void:
	var ring := Color(str(spec.get("ring", "68cdd0")))
	var radius := float(spec.get("ring_radius", 24))
	draw_set_transform(Vector2(0, 1), 0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, radius, Color(0.025, 0.04, 0.08, 0.42))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(ring, 0.55), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	if not _spine_ok:
		draw_circle(Vector2(0, -55), 18, ring)
		draw_style_box(_fallback_style(ring), Rect2(-17, -40, 34, 37))
		draw_line(Vector2(-9, -4), Vector2(-15, 0), ring, 5)
		draw_line(Vector2(9, -4), Vector2(15, 0), ring, 5)

func _fallback_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.3)
	box.corner_radius_top_left = 9
	box.corner_radius_top_right = 9
	return box
