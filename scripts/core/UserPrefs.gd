class_name SiegeUserPrefs
extends Node

const QA = preload("res://scripts/core/QAStartupContext.gd")
const QA_ERROR := "验收启动路径无效，已禁止存档读写。"

signal changed

const SCHEMA := 1
const DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.45,
	"sfx_volume": 0.7,
	"fullscreen": false,
	"damage_numbers": true,
	"edge_scroll": true,
	"tutorial_seen": false,
}
const VOLUME_KEYS := ["master_volume", "music_volume", "sfx_volume"]

var save_path := "user://preferences.json"
var error_message := ""
var dirty := false
var _values: Dictionary = DEFAULTS.duplicate()
var _loaded := false
var _blocked := false
var _path_explicitly_configured := false

func _ready() -> void:
	_ensure_loaded()
	apply_fullscreen()

# Tests configure an isolated path before adding this node to the tree.
# This never reads, writes, or migrates the character profile.
func configure_path(path: String) -> void:
	save_path = path
	_path_explicitly_configured = true
	_values = DEFAULTS.duplicate()
	error_message = ""
	dirty = false
	_loaded = false
	_blocked = false
	if is_inside_tree():
		_ensure_loaded()
		apply_fullscreen()

func get_value(key: String, fallback: Variant = null) -> Variant:
	_ensure_loaded()
	return _values.get(key, fallback)

# Changes are applied in memory immediately. flush() is the explicit disk boundary,
# so dragging an audio slider does not issue a write on every mouse motion.
func set_value(key: String, value: Variant) -> bool:
	_ensure_loaded()
	if _blocked or not QA.valid():
		error_message = QA_ERROR if not QA.valid() else "设置版本较新，当前版本无法保存。"
		return false
	if not DEFAULTS.has(key): return false
	var normalized: Variant = _normalize_value(key, value)
	if normalized == null: return false
	if _values[key] == normalized: return true
	_values[key] = normalized
	dirty = true
	if key == "fullscreen" and is_inside_tree(): apply_fullscreen()
	changed.emit()
	return true

func apply_fullscreen() -> void:
	if QA.suppress_window_policy(): return
	if DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(get_value("fullscreen")) else DisplayServer.WINDOW_MODE_WINDOWED)

func can_save() -> bool:
	_ensure_loaded()
	return not _blocked and QA.valid()

func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	_values = DEFAULTS.duplicate()
	save_path = QA.resolve_save_path("preferences", save_path, "user://preferences.json", _path_explicitly_configured)
	if QA.enabled() and not QA.valid():
		_blocked = true
		error_message = QA_ERROR
		_record_qa_load()
		return
	var primary := _read(save_path)
	if bool(primary.get("qa_denied", false)):
		_record_qa_load()
		return
	var backup := _read(save_path + ".bak")
	if bool(backup.get("qa_denied", false)):
		_record_qa_load()
		return
	if bool(primary.get("future", false)) or (not bool(primary.get("valid", false)) and bool(backup.get("future", false))):
		_blocked = true
		error_message = "设置版本较新，当前版本无法保存。"
	elif bool(primary.get("valid", false)):
		_values = primary["values"]
	elif bool(backup.get("valid", false)):
		_values = backup["values"]
		dirty = true
		error_message = "设置文件异常，已恢复上次备份；返回时将重新保存。"
	elif FileAccess.file_exists(save_path):
		error_message = "设置文件无法读取，已使用默认设置；返回时可重新保存。"
		dirty = true
	_record_qa_load()
	changed.emit()

func _record_qa_load() -> void:
	QA.record_load("preferences", save_path, {"values": _values, "dirty": dirty, "blocked": _blocked, "error_message": error_message})

func _normalize_value(key: String, value: Variant) -> Variant:
	if key in VOLUME_KEYS:
		if not (value is int or value is float): return null
		var number := float(value)
		if not is_finite(number): return null
		return clampf(number, 0.0, 1.0)
	return value if value is bool else null

func _read(path: String) -> Dictionary:
	if not QA.validate_path(path, "preferences", "read"):
		_blocked = true
		error_message = QA_ERROR
		return {"valid": false, "qa_denied": true}
	if not FileAccess.file_exists(path): return {"valid": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"valid": false}
	var bytes := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(bytes)
	if not parsed is Dictionary: return {"valid": false}
	var schema: Variant = parsed.get("schema")
	if not (schema is int or schema is float) or not is_finite(float(schema)): return {"valid": false}
	if float(schema) > SCHEMA: return {"valid": false, "future": true}
	if float(schema) != SCHEMA: return {"valid": false}
	var result := DEFAULTS.duplicate()
	for key: String in DEFAULTS:
		if not parsed.has(key): continue
		var value: Variant = _normalize_value(key, parsed[key])
		if value == null: return {"valid": false}
		result[key] = value
	return {"valid": true, "values": result}

func _fail(message: String) -> bool:
	error_message = message
	return false

func flush() -> bool:
	_ensure_loaded()
	if _blocked: return _fail(QA_ERROR if not QA.valid() else "设置版本较新，当前版本无法保存。")
	if not QA.validate_path(save_path, "preferences", "check") or not QA.validate_path(save_path + ".tmp", "preferences", "check") or not QA.validate_path(save_path + ".bak", "preferences", "check"):
		_blocked = true
		return _fail(QA_ERROR)
	# Re-check disk as well: another running instance must not downgrade future data.
	if bool(_read(save_path).get("future", false)):
		_blocked = true
		return _fail("设置版本较新，当前版本无法保存。")
	var candidate := _values.duplicate()
	candidate.schema = SCHEMA
	var temp := save_path + ".tmp"
	if not QA.validate_path(temp, "preferences", "write"): return _fail(QA_ERROR)
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return _fail("设置保存失败：无法写入文件。调整仅在本次运行生效，请重试保存。")
	file.store_string(JSON.stringify(candidate, "\t", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	var verified := _read(temp)
	if write_error != OK or not bool(verified.get("valid", false)) or verified["values"] != _values:
		return _fail("设置保存失败：写入校验未通过。调整仅在本次运行生效，请重试保存。")
	var primary := ProjectSettings.globalize_path(save_path)
	var backup := primary + ".bak"
	# Preserve a valid previous commit before the single rename replacement. Do not
	# delete the live file first; rename_absolute overwrites the target atomically.
	if bool(_read(save_path).get("valid", false)):
		if not QA.validate_path(primary, "preferences", "copy_source") or not QA.validate_path(backup, "preferences", "copy_destination"): return _fail(QA_ERROR)
		if DirAccess.copy_absolute(primary, backup) != OK:
			return _fail("设置保存失败：无法保留上次备份。调整仅在本次运行生效，请重试保存。")
	if not QA.validate_path(temp, "preferences", "rename_source") or not QA.validate_path(primary, "preferences", "rename_destination"): return _fail(QA_ERROR)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), primary) != OK:
		return _fail("设置保存失败：无法替换文件。调整仅在本次运行生效，请重试保存。")
	dirty = false
	error_message = ""
	return true
