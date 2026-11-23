class_name QABackgroundHost
extends RefCounted

const QA_CONTEXT = preload("res://scripts/core/QAStartupContext.gd")
const HELPER_PATH := "res://scripts/core/QABackgroundHost.gd"
const CONFIRMATION_FRAMES := 3

var _state: Dictionary = {
	"initialized": false,
	"initialize_calls": 0,
	"request_count": 0,
	"helper_sha256": "",
	"errors": [],
	"trace": [],
	"confirmed_frame": 0,
	"monitor_start_ticks_usec": 0,
	"policy": "one minimized-mode request after root ready; confirmation before sampling; no retries",
}

func _record(tree: SceneTree, stage: String, frame: int = 0) -> void:
	var host := tree.root
	_state["trace"].append({"stage": stage, "frame": frame,
		"ticks_usec": Time.get_ticks_usec(), "root_ready": host.is_node_ready(),
		"window_mode": host.mode, "display_window_mode": DisplayServer.window_get_mode(),
		"window_visible": host.visible, "focused": host.has_focus()})

func initialize(tree: SceneTree) -> bool:
	_state["initialize_calls"] += 1
	_state["helper_sha256"] = FileAccess.get_sha256(HELPER_PATH)
	if int(_state.initialize_calls) != 1:
		_state["errors"].append("background initialization may only be called once")
		return false
	_record(tree, "deferred_entry")
	if not QA_CONTEXT.enabled() or not QA_CONTEXT.valid():
		_state["errors"].append("background window setup requires a valid isolated QA startup")
		return false
	if DisplayServer.get_name() == "headless":
		_state["errors"].append("background window setup requires a native display server")
		return false
	if not tree.root.is_node_ready():
		await tree.root.ready
	_record(tree, "root_ready")
	# _initialize runs before the root's native window setup is complete. Wait
	# one actual process frame after ready before making the sole request.
	await tree.process_frame
	_record(tree, "ready_frame", 1)
	if not tree.root.is_node_ready():
		_state["errors"].append("root window was not ready before the mode request")
		return false
	_record(tree, "request_before", 1)
	_state["request_count"] += 1
	tree.root.mode = Window.MODE_MINIMIZED
	_record(tree, "request_after", 1)
	for frame: int in range(1, CONFIRMATION_FRAMES + 1):
		await tree.process_frame
		_record(tree, "confirmation_frame", frame)
		if tree.root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
			_state["initialized"] = true
			_state["confirmed_frame"] = frame
			_state["monitor_start_ticks_usec"] = Time.get_ticks_usec()
			_record(tree, "sampling_begin", frame)
			return true
	_state["errors"].append("the sole minimized-mode request was not confirmed by both window APIs")
	return false

func snapshot() -> Dictionary:
	return _state.duplicate(true)
