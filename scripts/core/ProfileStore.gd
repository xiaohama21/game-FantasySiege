class_name SiegeProfile
extends Node

const QA = preload("res://scripts/core/QAStartupContext.gd")
const QA_ERROR := "验收启动路径无效，已禁止存档读写。"

signal changed
const SCHEMA := 3
var data: Dictionary = {}
var last_award: Dictionary = {}
var save_path := "user://profile.json"
var error_message := ""
var _runs: Dictionary = {}
var _blocked := false
var _path_explicitly_configured := false

func _ready() -> void:
	load_profile()

func _fresh() -> Dictionary:
	var levels: Dictionary = {}
	for id: String in Catalog.initial_roster(): levels[id] = 1
	return {"schema": SCHEMA, "credits": 300, "levels": levels, "cleared": [], "roster": Catalog.initial_roster(), "owned": Catalog.initial_roster(), "transactions": [], "study_routes": {}}

func configure_path(path: String) -> void:
	save_path = path
	_path_explicitly_configured = true
	data = {}
	_runs.clear()
	last_award.clear()
	_blocked = false
	if QA.enabled():
		save_path = QA.resolve_save_path("profile", save_path, "user://profile.json", true)
		if not QA.valid():
			_blocked = true
			error_message = QA_ERROR

func _read(path: String) -> Dictionary:
	if not QA.validate_path(path, "profile", "read"):
		_blocked = true
		error_message = QA_ERROR
		return {}
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return {}
	if not parsed.get("levels") is Dictionary or not parsed.get("cleared") is Array: return {}
	if not parsed.get("transactions", []) is Array or not parsed.get("roster") is Array: return {}
	if not (parsed.get("credits") is int or parsed.get("credits") is float): return {}
	if float(parsed.credits) != int(parsed.credits) or int(parsed.credits) < 0: return {}
	if not (parsed.get("schema") is int or parsed.get("schema") is float): return {}
	if int(parsed.schema) in [2, SCHEMA] and not parsed.get("owned") is Array: return {}
	if int(parsed.schema) == SCHEMA:
		if not parsed.get("study_routes") is Dictionary: return {}
		for id: Variant in parsed.study_routes:
			if not id is String or Catalog.study(id).is_empty() or not parsed.study_routes[id] is String: return {}
	for id: Variant in parsed.get("owned", []):
		if not id is String or not Catalog.playable_roster().has(id): return {}
	for id: Variant in parsed.roster:
		if not id is String or not Catalog.playable_roster().has(id): return {}
	if parsed.roster.is_empty() or parsed.roster.size() > 8: return {}
	for id: Variant in parsed.cleared:
		if not id is String or Catalog.stage(id).is_empty(): return {}
	for token: Variant in parsed.get("transactions", []):
		if not token is String: return {}
	for id: Variant in parsed.levels:
		if not (parsed.levels[id] is int or parsed.levels[id] is float): return {}
		if not Catalog.playable_roster().has(id) or float(parsed.levels[id]) != int(parsed.levels[id]) or int(parsed.levels[id]) < 1 or int(parsed.levels[id]) > 20: return {}
	return parsed

func _future_schema(path: String) -> bool:
	if not QA.validate_path(path, "profile", "read_future_schema"):
		_blocked = true
		error_message = QA_ERROR
		return false
	if not FileAccess.file_exists(path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed is Dictionary and (parsed.get("schema") is int or parsed.get("schema") is float) and float(parsed.schema) > SCHEMA

func _sync_owned(candidate: Dictionary) -> void:
	var owned: Array = Catalog.initial_roster()
	for id: Variant in candidate.get("owned", []):
		if Catalog.playable_roster().has(id) and not owned.has(id): owned.append(id)
	for stage_id: Variant in candidate.get("cleared", []):
		for id: String in Catalog.reward_units(str(stage_id)):
			if not owned.has(id): owned.append(id)
	candidate.owned = owned
	for id: String in owned:
		if not candidate.levels.has(id): candidate.levels[id] = 1
	var roster: Array = []
	for id: Variant in candidate.get("roster", []):
		if owned.has(id) and not roster.has(id): roster.append(id)
	candidate.roster = roster if not roster.is_empty() else Catalog.initial_roster()
	var routes: Dictionary = candidate.get("study_routes", {}) if int(candidate.get("schema", 0)) == SCHEMA else {}
	for id: String in routes:
		if Catalog.study_route(id, str(routes[id])).is_empty(): routes[id] = "base"
	candidate.study_routes = routes
	candidate.schema = SCHEMA

func load_profile() -> void:
	_blocked = false
	save_path = QA.resolve_save_path("profile", save_path, "user://profile.json", _path_explicitly_configured)
	if QA.enabled() and not QA.valid():
		_blocked = true
		data = _fresh()
		error_message = QA_ERROR
		_record_qa_load()
		return
	var primary := _read(save_path)
	if QA.enabled() and not QA.valid():
		data = _fresh()
		_record_qa_load()
		return
	if _future_schema(save_path) or (primary.is_empty() and _future_schema(save_path + ".bak")):
		_blocked = true
		data = _fresh()
		error_message = "存档版本较新，当前版本仅可浏览"
		_record_qa_load()
		return
	if QA.enabled() and not QA.valid():
		data = _fresh()
		_record_qa_load()
		return
	data = primary if int(primary.get("schema", 0)) in [1, 2, SCHEMA] else _read(save_path + ".bak")
	if QA.enabled() and not QA.valid():
		data = _fresh()
		_record_qa_load()
		return
	if data.is_empty() or not (int(data.get("schema", 0)) in [1, 2, SCHEMA]): data = _fresh()
	_sync_owned(data)
	error_message = ""
	_record_qa_load()
	changed.emit()

func _record_qa_load() -> void:
	var summary := {"blocked": _blocked, "error_message": error_message}
	for key: String in ["credits", "levels", "roster", "owned", "cleared", "study_routes"]:
		summary[key] = data.get(key)
	QA.record_load("profile", save_path, summary)

func _commit(candidate: Dictionary) -> bool:
	if _blocked: return false
	if not QA.validate_path(save_path, "profile", "check") or not QA.validate_path(save_path + ".tmp", "profile", "check") or not QA.validate_path(save_path + ".bak", "profile", "check"):
		_blocked = true
		error_message = QA_ERROR
		return false
	_sync_owned(candidate)
	var temp := save_path + ".tmp"
	if not QA.validate_path(temp, "profile", "write"):
		_blocked = true
		error_message = QA_ERROR
		return false
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		error_message = "保存失败，资源未扣除"
		return false
	file.store_string(JSON.stringify(candidate, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or _read(temp).is_empty():
		error_message = "保存校验失败"
		return false
	var primary := ProjectSettings.globalize_path(save_path)
	var backup := primary + ".bak"
	var tmp_abs := ProjectSettings.globalize_path(temp)
	if FileAccess.file_exists(save_path):
		if not _read(save_path).is_empty():
			if not QA.validate_path(primary, "profile", "copy_source") or not QA.validate_path(backup, "profile", "copy_destination"):
				_blocked = true
				error_message = QA_ERROR
				return false
			if DirAccess.dir_exists_absolute(backup) or DirAccess.copy_absolute(primary, backup) != OK:
				error_message = "备份失败，资源未扣除"
				return false
		if not QA.validate_path(primary, "profile", "remove"):
			_blocked = true
			error_message = QA_ERROR
			return false
		if DirAccess.remove_absolute(primary) != OK:
			error_message = "保存替换失败"
			return false
	if not QA.validate_path(tmp_abs, "profile", "rename_source") or not QA.validate_path(primary, "profile", "rename_destination"):
		_blocked = true
		error_message = QA_ERROR
		return false
	if DirAccess.rename_absolute(tmp_abs, primary) != OK:
		if FileAccess.file_exists(save_path + ".bak") and QA.validate_path(backup, "profile", "copy_source") and QA.validate_path(primary, "profile", "copy_destination"): DirAccess.copy_absolute(backup, primary)
		error_message = "写盘失败，资源未扣除"
		return false
	data = candidate
	error_message = ""
	changed.emit()
	return true

func credits() -> int:
	return int(data.get("credits", 0))

func can_modify() -> bool:
	return not _blocked and QA.valid()

func level(id: String) -> int:
	return int(data.get("levels", {}).get(id, 1))

func owns(id: String) -> bool:
	return Catalog.playable_roster().has(id) and data.get("owned", Catalog.initial_roster()).has(id)

func stage_unlocked(id: String) -> bool:
	var stages := Catalog.stages()
	for i in stages.size():
		if str(stages[i].id) == id:
			var required := str(stages[i].get("required_stage", str(stages[i - 1].id) if i > 0 else ""))
			return required.is_empty() or data.get("cleared", []).has(required)
	return false

func reward_preview(id: String) -> Dictionary:
	var reward: Variant = Catalog.stage(id).get("rewards", 0)
	var base := int(reward.get("credits", 0)) if reward is Dictionary else int(reward)
	var first: bool = not data.get("cleared", []).has(id)
	var bonus := int(reward.get("first_clear_credits", 0)) if reward is Dictionary and first else 0
	var unlocks: Array = []
	for unit_id: String in Catalog.reward_units(id):
		if not owns(unit_id): unlocks.append(unit_id)
	return {"stage_id": id, "credits": base + bonus, "base_credits": base, "bonus_credits": bonus, "first_clear": first, "unlock_units": unlocks}

func training_cost(id: String) -> int:
	return 40 + level(id) * 20

func study_unlock_cost() -> int:
	return int(Catalog.studies().get("unlock_cost", 180))

func study_unlocked(id: String) -> bool:
	return owns(id) and not Catalog.study(id).is_empty() and data.get("study_routes", {}).has(id)

func study_route(id: String) -> String:
	if not study_unlocked(id): return "base"
	var route := str(data.get("study_routes", {}).get(id, "base"))
	return route if not Catalog.study_route(id, route).is_empty() else "base"

func unlock_study(id: String) -> bool:
	var definition := Catalog.study(id)
	if not can_modify() or not owns(id) or definition.is_empty() or study_unlocked(id): return false
	if level(id) < int(definition.get("min_level", 3)) or not data.get("cleared", []).has(str(definition.get("unlock_stage", "stage_04"))): return false
	var cost := int(definition.get("unlock_cost", study_unlock_cost()))
	if credits() < cost: return false
	var candidate := data.duplicate(true)
	candidate.credits = credits() - cost
	candidate.study_routes[id] = "base"
	return _commit(candidate)

func set_study_route(id: String, route_id: String) -> bool:
	if not can_modify() or not study_unlocked(id) or Catalog.study_route(id, route_id).is_empty(): return false
	if study_route(id) == route_id: return true
	var candidate := data.duplicate(true)
	candidate.study_routes[id] = route_id
	return _commit(candidate)

func study_modifiers_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for id: Variant in data.get("study_routes", {}):
		if not id is String or not study_unlocked(id) or study_route(id) == "base": continue
		result[id] = Catalog.study_modifiers(id, study_route(id))
	return result.duplicate(true)

func upgrade(id: String) -> bool:
	if not owns(id) or level(id) >= 20 or credits() < training_cost(id): return false
	var candidate := data.duplicate(true)
	candidate.credits = credits() - training_cost(id)
	candidate.levels[id] = level(id) + 1
	return _commit(candidate)

func set_roster(roster: Array) -> bool:
	var valid: Array = []
	for id: Variant in roster:
		if not id is String or not owns(id): return false
		if not valid.has(id): valid.append(id)
	if valid.is_empty() or valid.size() > 8: return false
	var candidate := data.duplicate(true)
	candidate.roster = valid
	return _commit(candidate)

func begin_run(stage_id: String) -> String:
	if _blocked or not QA.valid(): return ""
	if not stage_unlocked(stage_id): return ""
	last_award.clear()
	var token := "%s-%d-%d" % [stage_id, Time.get_ticks_usec(), randi()]
	_runs[token] = stage_id
	return token

func win(token: String) -> bool:
	if not _runs.has(token) or data.get("transactions", []).has(token): return false
	var id: String = _runs[token]
	var stage := Catalog.stage(id)
	var candidate := data.duplicate(true)
	var preview := reward_preview(id)
	candidate.credits = credits() + int(preview.credits)
	if not candidate.cleared.has(id): candidate.cleared.append(id)
	candidate.transactions.append(token)
	while candidate.transactions.size() > 32: candidate.transactions.pop_front()
	if not _commit(candidate): return false
	last_award = preview
	_runs.erase(token)
	return true

func abandon(token: String) -> void:
	_runs.erase(token)
