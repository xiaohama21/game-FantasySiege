class_name Catalog
extends RefCounted

static var _units: Dictionary = {}
static var _stages: Array = []
const INITIAL_ROSTER := ["guanyu", "zhaoyun", "zhugeliang", "diaochan", "lubu", "iron_guard", "ember_archer", "rune_medic"]

static func _read(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path): return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else fallback

static func units() -> Dictionary:
	if _units.is_empty(): _units = _read("res://resources/units.json", {})
	return _units

static func unit(id: String) -> Dictionary:
	return units().get(id, {}).duplicate(true)

static func stages() -> Array:
	if _stages.is_empty(): _stages = _read("res://resources/stages.json", [])
	return _stages

static func stage(id: String) -> Dictionary:
	for item: Dictionary in stages():
		if str(item.get("id", "")) == id: return item.duplicate(true)
	return {}

static func initial_roster() -> Array:
	return INITIAL_ROSTER.duplicate()

static func visuals() -> Dictionary:
	return _read("res://resources/visuals.json", {})
