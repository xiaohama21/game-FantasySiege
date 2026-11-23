extends SceneTree

const QA_CONTEXT = preload("res://scripts/core/QAStartupContext.gd")
const HOST = preload("res://scripts/core/QABackgroundHost.gd")
const REPORT_PATH := "res://reports/background_host_smoke_local.json"

var setup := HOST.new()
var checks := 0
var failures: Array[String] = []
var legacy_initialize_trace: Array = []
var legacy_run_start_state: Dictionary = {}
var monitored_frames: Array = []
var monitoring := false
var first_invalid_sample: Dictionary = {}

func _window_state(stage: String) -> Dictionary:
	return {"stage": stage, "ticks_usec": Time.get_ticks_usec(), "root_ready": root.is_node_ready(),
		"window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode(),
		"window_visible": root.visible, "focused": root.has_focus()}

func _initialize() -> void:
	# Reproduce the old early request only in this diagnostic fixture. Production
	# renderers use the shared ready-stage helper and make no early request.
	legacy_initialize_trace.append(_window_state("legacy_initialize_before"))
	root.mode = Window.MODE_MINIMIZED
	legacy_initialize_trace.append(_window_state("legacy_initialize_after"))
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if monitoring:
		var sample := _window_state("monitored_frame")
		sample["sample"] = monitored_frames.size() + 1
		monitored_frames.append(sample)
		if root.mode != Window.MODE_MINIMIZED or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED:
			if first_invalid_sample.is_empty(): first_invalid_sample = sample.duplicate(true)
	return false

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	legacy_run_start_state = _window_state("legacy_run_start")
	_check(QA_CONTEXT.enabled() and QA_CONTEXT.valid(), "isolated startup context is active")
	_check(DisplayServer.get_name() != "headless" and not RenderingServer.get_video_adapter_name().is_empty(), "native display and real renderer are active")
	var initialized: bool = await setup.initialize(self)
	_check(initialized, "ready-stage sole request was confirmed before sampling")
	if initialized:
		monitoring = true
		await process_frame
		await process_frame
		# The signal resumes this coroutine before SceneTree._process runs;
		# a third boundary guarantees two completed monitored process frames.
		await process_frame
		monitoring = false
	var state := setup.snapshot()
	_check(int(state.get("request_count", 0)) == 1 and int(state.get("initialize_calls", 0)) == 1, "helper made exactly one production request")
	_check(int(state.get("monitor_start_ticks_usec", 0)) > 0 and int(state.get("confirmed_frame", 0)) > 0, "sampling begins only after a confirmed frame")
	_check(state.get("errors", []).is_empty(), "shared setup has no errors")
	_check(monitored_frames.size() >= 2 and first_invalid_sample.is_empty(), "both monitored frames remained minimized")
	_check(root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED, "both window APIs still confirm minimized mode")
	var gdd := _gdd_metadata()
	_check(not gdd.is_empty(), "same-project design header and hash are present")
	if root.has_node("GameAudio"): await root.get_node("GameAudio").shutdown()
	var report := {"program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"background_host_setup": state, "qa_startup": QA_CONTEXT.snapshot(),
		"legacy_initialize_trace": legacy_initialize_trace, "legacy_run_start_state": legacy_run_start_state,
		"legacy_early_request_reset": int(legacy_run_start_state.window_mode) != Window.MODE_MINIMIZED or int(legacy_run_start_state.display_window_mode) != DisplayServer.WINDOW_MODE_MINIMIZED,
		"legacy_request_count": 1, "production_request_count": int(state.get("request_count", 0)),
		"monitored_frames": monitored_frames, "background_first_invalid_sample": first_invalid_sample,
		"root_window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode(),
		"rendering_adapter": RenderingServer.get_video_adapter_name(), "display_server": DisplayServer.get_name(),
		"actual_rendering_driver": str(RenderingServer.call("get_current_rendering_driver_name")).to_lower() if RenderingServer.has_method("get_current_rendering_driver_name") else "unknown",
		"scope": "Hidden native-window lifecycle diagnostic; legacy early request and one ready-stage production request, then at least two completed monitored frames",
		"performance_measured": false, "foreground_verified": false,
		"fixture_sha256": FileAccess.get_sha256("res://tests/BackgroundHostSmoke.gd")}
	report.merge(gdd)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write background host diagnostic report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BACKGROUND_HOST_SMOKE_COMPLETE ", JSON.stringify(report))
	quit(0 if report.passed else 1)

func _gdd_metadata() -> Dictionary:
	var path := "res://docs/GAME_DESIGN.md"
	var regex := RegEx.new()
	if regex.compile("(?m)^> 文档 v([^ ]+) ·[^\\r\\n]*") != OK: return {}
	var header := regex.search(FileAccess.get_file_as_string(path))
	var digest := FileAccess.get_sha256(path)
	if header == null or digest.length() != 64: return {}
	return {"gdd_version": header.get_string(1), "gdd_header": header.get_string(0), "gdd_sha256": digest}
