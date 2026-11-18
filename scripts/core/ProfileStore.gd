class_name SiegeProfile
extends Node

signal changed
var data: Dictionary = {}
var save_path := "user://profile.json"
var error_message := ""
var _runs: Dictionary = {}
var _blocked := false

func _ready() -> void:
	load_profile()

func _fresh() -> Dictionary:
	var levels: Dictionary = {}
	for id: String in Catalog.initial_roster(): levels[id] = 1
	return {"schema": 1, "credits": 300, "levels": levels, "cleared": [], "roster": Catalog.initial_roster(), "transactions": []}

func configure_path(path: String) -> void:
	save_path = path
	data = {}
	_runs.clear()
	_blocked = false

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return {}
	if not parsed.get("levels") is Dictionary or not parsed.get("cleared") is Array: return {}
	if not parsed.get("transactions", []) is Array or not parsed.get("roster") is Array: return {}
	if not (parsed.get("credits") is int or parsed.get("credits") is float): return {}
	if float(parsed.credits) != int(parsed.credits) or int(parsed.credits) < 0: return {}
	if not (parsed.get("schema") is int or parsed.get("schema") is float): return {}
	for id: Variant in parsed.roster:
		if not id is String or not Catalog.initial_roster().has(id): return {}
	if parsed.roster.is_empty() or parsed.roster.size() > 8: return {}
	for id: Variant in parsed.cleared:
		if not id is String or Catalog.stage(id).is_empty(): return {}
	for token: Variant in parsed.get("transactions", []):
		if not token is String: return {}
	for id: Variant in parsed.levels:
		if not (parsed.levels[id] is int or parsed.levels[id] is float): return {}
		if not Catalog.initial_roster().has(id) or float(parsed.levels[id]) != int(parsed.levels[id]) or int(parsed.levels[id]) < 1 or int(parsed.levels[id]) > 20: return {}
	return parsed

func _future_schema(path: String) -> bool:
	if not FileAccess.file_exists(path): return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed is Dictionary and (parsed.get("schema") is int or parsed.get("schema") is float) and float(parsed.schema) > 1

func load_profile() -> void:
	_blocked = false
	var primary := _read(save_path)
	if _future_schema(save_path) or (primary.is_empty() and _future_schema(save_path + ".bak")):
		_blocked = true
		data = _fresh()
		error_message = "存档版本较新，当前版本仅可浏览"
		return
	data = primary if int(primary.get("schema", 0)) == 1 else _read(save_path + ".bak")
	if data.is_empty() or int(data.get("schema", 0)) != 1: data = _fresh()
	for id: String in Catalog.initial_roster():
		if not data.levels.has(id): data.levels[id] = 1
	error_message = ""
	changed.emit()

func _commit(candidate: Dictionary) -> bool:
	if _blocked: return false
	var temp := save_path + ".tmp"
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
		if not _read(save_path).is_empty() and DirAccess.copy_absolute(primary, backup) != OK:
			error_message = "备份失败，资源未扣除"
			return false
		if DirAccess.remove_absolute(primary) != OK:
			error_message = "保存替换失败"
			return false
	if DirAccess.rename_absolute(tmp_abs, primary) != OK:
		if FileAccess.file_exists(save_path + ".bak"): DirAccess.copy_absolute(backup, primary)
		error_message = "写盘失败，资源未扣除"
		return false
	data = candidate
	error_message = ""
	changed.emit()
	return true

func credits() -> int:
	return int(data.get("credits", 0))

func level(id: String) -> int:
	return int(data.get("levels", {}).get(id, 1))

func training_cost(id: String) -> int:
	return 40 + level(id) * 20

func upgrade(id: String) -> bool:
	if not Catalog.initial_roster().has(id) or level(id) >= 20 or credits() < training_cost(id): return false
	var candidate := data.duplicate(true)
	candidate.credits = credits() - training_cost(id)
	candidate.levels[id] = level(id) + 1
	return _commit(candidate)

func set_roster(roster: Array) -> bool:
	var valid: Array = []
	for id: Variant in roster:
		if Catalog.initial_roster().has(id) and not valid.has(id): valid.append(id)
	if valid.is_empty() or valid.size() > 8: return false
	var candidate := data.duplicate(true)
	candidate.roster = valid
	return _commit(candidate)

func begin_run(stage_id: String) -> String:
	if Catalog.stage(stage_id).is_empty(): return ""
	var token := "%s-%d-%d" % [stage_id, Time.get_ticks_usec(), randi()]
	_runs[token] = stage_id
	return token

func win(token: String) -> bool:
	if not _runs.has(token) or data.get("transactions", []).has(token): return false
	var id: String = _runs[token]
	var stage := Catalog.stage(id)
	var candidate := data.duplicate(true)
	var reward: Variant = stage.get("rewards", 80)
	var earned := int(reward.get("credits", 80)) if reward is Dictionary else int(reward)
	candidate.credits = credits() + earned
	if not candidate.cleared.has(id): candidate.cleared.append(id)
	candidate.transactions.append(token)
	while candidate.transactions.size() > 32: candidate.transactions.pop_front()
	if not _commit(candidate): return false
	_runs.erase(token)
	return true

func abandon(token: String) -> void:
	_runs.erase(token)
