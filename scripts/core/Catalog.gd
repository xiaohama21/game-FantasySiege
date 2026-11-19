class_name Catalog
extends RefCounted

static var _units: Dictionary = {}
static var _stages: Array = []
static var _studies: Dictionary = {}
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

static func studies() -> Dictionary:
	if _studies.is_empty(): _studies = _read("res://resources/studies.json", {})
	return _studies.duplicate(true)

static func study(id: String) -> Dictionary:
	var config := studies()
	var entry: Variant = config.get("units", {}).get(id, {})
	if not playable_roster().has(id) or not entry is Dictionary or entry.is_empty(): return {}
	var result: Dictionary = entry.duplicate(true)
	for key: String in ["unlock_stage", "min_level", "unlock_cost"]:
		result[key] = config.get(key, {"unlock_stage": "stage_04", "min_level": 3, "unlock_cost": 180}[key])
	return result

static func study_routes(id: String) -> Array:
	var value: Variant = study(id).get("routes", [])
	return value.duplicate(true) if value is Array else []

static func study_route(id: String, route_id: String) -> Dictionary:
	if study(id).is_empty(): return {}
	if route_id == "base":
		return {"id": "base", "name": "基础路线", "description": "保留基础属性与技能，不应用研修修饰器。", "modifiers": {}}
	for route: Variant in study_routes(id):
		if route is Dictionary and str(route.get("id", "")) == route_id:
			return route.duplicate(true)
	return {}

static func study_modifiers(id: String, route_id: String) -> Dictionary:
	var value: Variant = study_route(id, route_id).get("modifiers", {})
	return value.duplicate(true) if value is Dictionary else {}

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

static func enemy_roster() -> Array:
	var result: Array = []
	for id: String in units():
		if not playable_roster().has(id): result.append(id)
	return result

static func appearances(id: String) -> Array:
	var result: Array = []
	for entry: Dictionary in stages():
		for wave: Dictionary in entry.get("waves", []):
			if str(wave.get("unit_id", "")) == id:
				result.append(str(entry.get("name", entry.id)))
				break
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
