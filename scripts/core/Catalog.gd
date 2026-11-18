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

static func playable_roster() -> Array:
	var result: Array = []
	for id: String in units():
		if bool(units()[id].get("playable", INITIAL_ROSTER.has(id))): result.append(id)
	return result

static func reward_units(stage_id: String) -> Array:
	var reward: Variant = stage(stage_id).get("rewards", {})
	if not reward is Dictionary: return []
	var result: Array = []
	for id: Variant in reward.get("unlock_units", []):
		if id is String and playable_roster().has(id) and not result.has(id): result.append(id)
	return result

static func unlock_stage(id: String) -> String:
	for entry: Dictionary in stages():
		if reward_units(str(entry.id)).has(id): return str(entry.get("name", entry.id))
	return "初始契约"

static func visuals() -> Dictionary:
	return _read("res://resources/visuals.json", {})
