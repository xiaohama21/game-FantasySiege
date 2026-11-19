class_name BattleBriefing
extends RefCounted

const CONFIG_PATH := "res://resources/briefings.json"

static func _configuration() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH)) if FileAccess.file_exists(CONFIG_PATH) else {}
	return parsed.duplicate(true) if parsed is Dictionary else {}

static func summarize(stage_id: String) -> Dictionary:
	var stage := Catalog.stage(stage_id)
	if stage.is_empty(): return {}
	var timeline: Array[Dictionary] = []
	var sequence := 0
	# Preserve the original wave recipe and Battle's stable planned order.
	for wave: Dictionary in stage.get("waves", []):
		for index: int in maxi(0, int(wave.get("count", 1))):
			var item := wave.duplicate(true)
			item.time = maxf(0.0, float(wave.get("time", 0.0)) + index * maxf(0.0, float(wave.get("interval", 1.0))))
			item.sequence = sequence
			timeline.append(item)
			sequence += 1
	timeline.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.time) == float(b.time): return int(a.sequence) < int(b.sequence)
		return float(a.time) < float(b.time))
	var enemies: Array[Dictionary] = []
	var enemy_indexes: Dictionary = {}
	for wave: Dictionary in timeline:
		var id := str(wave.get("unit_id", ""))
		var definition := Catalog.unit(id)
		if not enemy_indexes.has(id):
			enemy_indexes[id] = enemies.size()
			enemies.append({"id": id, "name": str(definition.get("name", "未知敌军")), "role": str(definition.get("role_name", definition.get("role", "未登记职责"))), "count": 0, "first_time": float(wave.time), "last_time": float(wave.time), "variants": []})
		var enemy: Dictionary = enemies[int(enemy_indexes[id])]
		enemy.count = int(enemy.count) + 1
		enemy.last_time = float(wave.time)
		# These are the same enemy-only multiplier boundaries used by _spawn.
		var hp_mult := maxf(0.01, UnitStats.modifier_value(wave, "hp_mult"))
		var damage_mult := maxf(0.0, UnitStats.modifier_value(wave, "damage_mult"))
		var variant_index := -1
		for index: int in enemy.variants.size():
			var existing: Dictionary = enemy.variants[index]
			if float(existing.hp_mult) == hp_mult and float(existing.damage_mult) == damage_mult:
				variant_index = index
				break
		if variant_index < 0:
			var stats := UnitStats.calculate(definition, 1, {"hp_mult": hp_mult, "damage_mult": damage_mult}) if not definition.is_empty() else {}
			enemy.variants.append({"count": 1, "hp_mult": hp_mult, "damage_mult": damage_mult, "stats": stats})
		else:
			enemy.variants[variant_index].count = int(enemy.variants[variant_index].count) + 1
	var last_time := float(timeline.back().time) if not timeline.is_empty() else 0.0
	return {"stage_id": stage_id, "stage": stage, "enemies": enemies, "total_count": timeline.size(), "timeline": timeline, "last_time": last_time}.duplicate(true)

static func readiness(stage_id: String, roster: Array, levels: Dictionary, study_modifiers: Dictionary, owned: Array) -> Dictionary:
	var config := _configuration()
	var capability_config: Dictionary = config.get("capabilities", {})
	var capabilities: Dictionary = {}
	for capability: String in capability_config: capabilities[capability] = []
	var members: Array[Dictionary] = []
	var member_ids: Array[String] = []
	var playable := Catalog.playable_roster()
	for value: Variant in roster:
		if members.size() >= 8: break
		if not value is String or not playable.has(value) or not owned.has(value) or member_ids.has(value): continue
		var member := _member(value, levels, study_modifiers, config)
		members.append(member)
		member_ids.append(value)
		for capability: String in member.capabilities: capabilities[capability].append(value)
	var alternatives: Array[Dictionary] = []
	var alternative_ids: Array[String] = []
	for value: Variant in owned:
		if not value is String or not playable.has(value) or member_ids.has(value) or alternative_ids.has(value): continue
		alternatives.append(_member(value, levels, study_modifiers, config))
		alternative_ids.append(value)
	var recommendations: Array[Dictionary] = []
	var stage_config: Dictionary = config.get("stages", {}).get(stage_id, {}) if not Catalog.stage(stage_id).is_empty() else {}
	for suggestion: Dictionary in stage_config.get("recommendations", []):
		var capability := str(suggestion.get("capability", ""))
		if not capability_config.has(capability): continue
		var label := str(capability_config[capability].get("label", capability))
		var present: Array = capabilities[capability].duplicate()
		var available: Array[String] = []
		if present.is_empty():
			for member: Dictionary in alternatives:
				if member.capabilities.has(capability): available.append(str(member.id))
		var reason := str(suggestion.get("reason", ""))
		var message: String
		if not present.is_empty():
			message = "%s · 当前队员：%s。%s" % [label, _member_names(present), reason]
		elif not available.is_empty():
			message = "当前阵容缺少%s；已契约可调整：%s。%s" % [label, _member_names(available), reason]
		else:
			message = "当前阵容暂缺%s，暂无已契约替补；可先训练现有队员、预留能量并调整召唤节奏。%s" % [label, reason]
		recommendations.append({"capability": capability, "label": label, "present": present, "alternatives": available, "reason": reason, "message": message})
	return {"members": members, "capabilities": capabilities, "recommendations": recommendations}.duplicate(true)

static func _member(id: String, levels: Dictionary, study_modifiers: Dictionary, config: Dictionary) -> Dictionary:
	var definition := Catalog.unit(id)
	var raw_modifiers: Variant = study_modifiers.get(id, {})
	var modifiers: Dictionary = raw_modifiers.duplicate(true) if raw_modifiers is Dictionary else {}
	var stats := UnitStats.calculate(definition, int(levels.get(id, 1)), modifiers)
	return {"id": id, "name": str(definition.get("name", "未知英魂")), "level": int(stats.level), "stats": stats, "capabilities": _capabilities(id, definition, stats, config)}

static func _capabilities(id: String, definition: Dictionary, stats: Dictionary, config: Dictionary) -> Array[String]:
	var special: Dictionary = stats.special
	var special_type := str(special.get("type", ""))
	var healing := special_type == "heal" and float(special.get("amount", 0.0)) > 0.0
	var is_healer := special_type == "heal"
	var damaging := not is_healer and float(stats.damage) > 0.0
	var identity: Dictionary = config.get("units", {}).get(id, {})
	var predicates := {
		"frontline": bool(identity.get("frontline", false)) and not is_healer,
		"low_cost": damaging and float(definition.get("cost", 0.0)) <= float(config.get("low_cost_max", 90.0)) and float(stats.range) <= float(config.get("low_cost_range_max", 100.0)),
		"aoe": float(stats.aoe_radius) > 0.0,
		"magic": damaging and str(stats.damage_type) == "magic",
		"true_damage": damaging and str(stats.damage_type) == "true",
		"healing": healing,
		"slow": special_type == "slow" and float(special.get("ratio", 1.0)) < 1.0 and float(special.get("duration", 0.0)) > 0.0,
		"siege": damaging and float(special.get("base_damage_multiplier", 1.0)) > 1.0,
	}
	var result: Array[String] = []
	for capability: String in config.get("capabilities", {}):
		if bool(predicates.get(capability, false)): result.append(capability)
	return result

static func _member_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for id: String in ids: names.append(str(Catalog.unit(id).get("name", "未知英魂")))
	return "、".join(names)
