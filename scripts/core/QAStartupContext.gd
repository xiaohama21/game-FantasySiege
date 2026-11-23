class_name QAStartupContext
extends RefCounted

# One context per engine process. Parse before the first preference/profile I/O,
# rather than relying on a SceneTree fixture's deferred setup.
const SCRIPT_PATHS := [
	"scripts/core/QAStartupContext.gd",
	"scripts/core/UserPrefs.gd",
	"scripts/core/ProfileStore.gd",
]
static var _initialized := false
static var _state: Dictionary = {}
static var _report_safe := false
static var _report_write_failed := false

static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().trim_suffix("/")

static func _below(path: String, base: String, allow_equal := false) -> bool:
	var checked := path.to_lower() if OS.get_name() == "Windows" else path
	var anchor := base.to_lower() if OS.get_name() == "Windows" else base
	return (allow_equal and checked == anchor) or checked.begins_with(anchor + "/")

static func _plain_absolute(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://") or normalized.begins_with("//"): return false
	if OS.get_name() == "Windows":
		if normalized.length() < 4 or normalized[1] != ":" or normalized[2] != "/": return false
	else:
		if not normalized.begins_with("/"): return false
	for component: String in normalized.split("/", false):
		if component == "." or component == "..": return false
		if component.contains(":") and component != normalized.substr(0, 2): return false
		if component.ends_with(".") or component.ends_with(" "): return false
	return true

# Python also checks resolved paths, Windows reparse attributes and hard links
# immediately before launch. Godot rechecks existing components before I/O with
# its own link API. This is not an OS sandbox or an atomic TOCTOU guarantee.
static func _links_clear(path: String) -> bool:
	var anchor := str(_state.get("project_root", _absolute("res://")))
	if not _below(path, anchor, true): return false
	if path == anchor: return true
	var relative := path.substr(anchor.length() + 1)
	var cursor := anchor
	for component: String in relative.split("/", false):
		var directory := DirAccess.open(cursor)
		# Nonexistent parents cannot contain a current link. The real I/O still
		# reports its normal failure; a later operation rechecks the whole chain.
		if directory == null: break
		if directory.is_link(component): return false
		cursor = cursor.path_join(component)
	return true

static func _argument_path(path: String, base: String, allow_equal := false) -> bool:
	return _plain_absolute(path) and _below(_absolute(path), base, allow_equal) and _links_clear(_absolute(path))

static func _ensure_context() -> void:
	if _initialized: return
	_initialized = true
	var args := OS.get_cmdline_user_args()
	var enabled := false
	for argument: String in args:
		if argument.begins_with("--qa-save-root") or argument.begins_with("--qa-startup-report") or argument == "--qa-background": enabled = true
	_state = {
		"qa_enabled": enabled,
		"valid": true,
		"project_root": _absolute("res://"),
		"save_root": "",
		"report_path": "",
		"started_ticks_usec": Time.get_ticks_usec(),
		"started_unix_time": Time.get_unix_time_from_system(),
		"program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"first_loads": {},
		"operations": [],
		"refused_operations": [],
		"script_sha256": {},
		"background": args.has("--qa-background") or args.has("background") or args.has("--background") or DisplayServer.get_name() == "headless",
		"window_policy_skipped": false,
		"window_policy_reason": "",
		"runtime_path_check": "project containment and DirAccess.is_link for existing components; launcher resolved-path/reparse/hard-link preflight required",
		"atomic_filesystem_sandbox": false,
	}
	if not enabled: return
	var values := {"--qa-save-root": [], "--qa-startup-report": []}
	var malformed: Array = []
	for index in args.size():
		var argument: String = args[index]
		if values.has(argument):
			if index + 1 >= args.size() or str(args[index + 1]).begins_with("--"):
				malformed.append(argument + " missing value")
			else:
				values[argument].append(str(args[index + 1]))
		elif argument.begins_with("--qa-save-root") or argument.begins_with("--qa-startup-report"):
			malformed.append("malformed QA argument " + argument)
	for flag: String in values:
		if values[flag].size() != 1: malformed.append(flag + " must appear exactly once")
	var save_values: Array = values["--qa-save-root"]
	var report_values: Array = values["--qa-startup-report"]
	if report_values.size() == 1:
		var report_value := str(report_values[0])
		if _argument_path(report_value, _absolute("res://reports")):
			_state["report_path"] = _absolute(report_value)
			_report_safe = true
		else:
			malformed.append("startup report is not an unlinked absolute project reports path")
	if save_values.size() == 1:
		var save_value := str(save_values[0])
		if _argument_path(save_value, _absolute("res://tests/.user"), true):
			_state["save_root"] = _absolute(save_value)
		else:
			malformed.append("save root is not an unlinked absolute project tests/.user path")
	for relative: String in SCRIPT_PATHS:
		_state["script_sha256"][relative] = FileAccess.get_sha256("res://" + relative)
	for reason: String in malformed:
		_refuse("startup", "argument", "", reason)
	_write_report()

static func enabled() -> bool:
	_ensure_context()
	return bool(_state.qa_enabled)

static func valid() -> bool:
	_ensure_context()
	return bool(_state.valid)

static func _refuse(owner: String, action: String, path: String, reason: String) -> void:
	_state["valid"] = false
	_state["refused_operations"].append({"owner": owner, "action": action, "path": path, "reason": reason, "allowed": false, "ticks_usec": Time.get_ticks_usec()})
	print("QA_STARTUP_REJECTED ", reason)
	_write_report()

static func resolve_save_path(owner: String, path: String, default_path: String, explicitly_configured: bool) -> String:
	_ensure_context()
	if not bool(_state.qa_enabled): return path
	if not bool(_state.valid):
		_refuse(owner, "resolve", path, "invalid QA startup; default user data is unavailable")
		return ""
	var result := path
	if not explicitly_configured and path == default_path:
		result = str(_state.save_root).path_join(default_path.get_file())
	if not validate_path(result, owner, "resolve"): return ""
	return _absolute(result)

# Records authorized I/O attempts before the actual FileAccess/DirAccess call.
# Existence tests are part of a read, including missing files; refused attempts
# never enter operations and never reach the underlying filesystem call.
static func validate_path(path: String, owner: String, action: String) -> bool:
	_ensure_context()
	if not bool(_state.qa_enabled): return true
	if not bool(_state.valid):
		_refuse(owner, action, path, "QA context is invalid")
		return false
	var actual := _absolute(path)
	var raw := path.replace("\\", "/")
	var raw_components_plain := true
	for component: String in raw.split("/", false):
		if component == "." or component == "..": raw_components_plain = false
	if path.is_empty() or not raw_components_plain or not _plain_absolute(actual) or not _below(actual, _absolute("res://tests/.user")) or not _links_clear(actual):
		_refuse(owner, action, actual, "save I/O escaped project tests/.user or traversed a link")
		return false
	if action != "resolve":
		_state["operations"].append({"owner": owner, "action": action, "path": actual, "allowed": true, "ticks_usec": Time.get_ticks_usec()})
		_write_report()
	return true

static func record_load(owner: String, path: String, summary: Dictionary) -> void:
	_ensure_context()
	if not bool(_state.qa_enabled): return
	if not _state.first_loads.has(owner):
		_state["first_loads"][owner] = {"owner": owner, "path": path, "summary": summary.duplicate(true), "blocked": bool(summary.get("blocked", false)), "ticks_usec": Time.get_ticks_usec()}
	_write_report()

static func suppress_window_policy() -> bool:
	_ensure_context()
	if not bool(_state.qa_enabled): return false
	if not bool(_state.valid) or bool(_state.background):
		_state["window_policy_skipped"] = true
		_state["window_policy_reason"] = "invalid QA startup" if not bool(_state.valid) else "background QA must not apply fullscreen or restore the host window"
		_write_report()
		return true
	return false

static func snapshot() -> Dictionary:
	_ensure_context()
	_write_report()
	return _state.duplicate(true)

static func _write_report() -> void:
	if not _report_safe or _report_write_failed: return
	var path := str(_state.report_path)
	if not _argument_path(path, _absolute("res://reports")):
		_report_safe = false
		_state["valid"] = false
		_state["refused_operations"].append({"owner": "startup", "action": "report", "path": path, "reason": "startup report path changed to an unsafe path", "allowed": false, "ticks_usec": Time.get_ticks_usec()})
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_report_write_failed = true
		_state["valid"] = false
		_state["refused_operations"].append({"owner": "startup", "action": "report", "path": path, "reason": "cannot write startup report", "allowed": false, "ticks_usec": Time.get_ticks_usec()})
		print("QA_STARTUP_REJECTED cannot write startup report")
		return
	file.store_string(JSON.stringify(_state, "\t"))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		_report_write_failed = true
		_state["valid"] = false
		print("QA_STARTUP_REJECTED startup report write failed")
