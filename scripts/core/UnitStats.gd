class_name UnitStats
extends RefCounted

const ATTRIBUTES := ["strength", "agility", "intelligence"]
const MODIFIER_KEYS := ["hp_mult", "damage_mult", "armor_add", "speed_mult", "range_mult", "attack_interval_mult", "hit_delay_mult", "aoe_radius_mult", "heal_amount_mult", "slow_ratio", "slow_duration_mult", "base_damage_multiplier"]

static func primary_label(primary: String) -> String:
	return str({"strength": "力量", "agility": "敏捷", "intelligence": "智力"}.get(primary, "力量"))

static func calculate(unit: Dictionary, level: int = 1, modifiers: Dictionary = {}) -> Dictionary:
	var actual_level := clampi(level, 1, 20)
	var primary := str(unit.get("primary_attribute", "strength"))
	if not ATTRIBUTES.has(primary):
		primary = "strength"
	var attributes: Dictionary = unit.get("attributes", {})
	var growth: Dictionary = unit.get("attribute_growth", {})
	var stats: Dictionary = {}
	for key: String in ATTRIBUTES:
		var base := maxf(0.0, float(attributes.get(key, 0.0)))
		var increment := maxf(0.0, float(growth.get(key, 2.0 if key == primary else 1.0)))
		stats[key] = base + (actual_level - 1) * increment
	var strength := float(stats.strength)
	var agility := float(stats.agility)
	var intelligence := float(stats.intelligence)
	var hp := maxf(1.0, float(unit.get("hp", 100.0))) * (1.0 + 0.06 * (actual_level - 1)) * (1.0 + 0.015 * strength)
	var damage := maxf(0.0, float(unit.get("damage", 10.0))) * (1.0 + 0.05 * (actual_level - 1)) * (1.0 + 0.012 * float(stats[primary]))
	var attack_interval := maxf(0.1, float(unit.get("attack_interval", 1.0))) / (1.0 + 0.004 * agility)
	var speed := maxf(0.0, float(unit.get("speed", 60.0))) * (1.0 + 0.003 * agility)
	# Research applies after the existing level and attribute formulas. Only
	# these explicit numeric keys participate; arbitrary behavior stays in data.
	hp = maxf(1.0, hp * maxf(0.01, _modifier(modifiers, "hp_mult", 1.0)))
	damage *= maxf(0.0, _modifier(modifiers, "damage_mult", 1.0))
	attack_interval *= maxf(0.01, _modifier(modifiers, "attack_interval_mult", 1.0))
	speed *= maxf(0.0, _modifier(modifiers, "speed_mult", 1.0))
	var armor := maxf(0.0, maxf(0.0, float(unit.get("armor", 0.0))) + _modifier(modifiers, "armor_add", 0.0))
	var attack_range := maxf(16.0, maxf(16.0, float(unit.get("range", 40.0))) * maxf(0.0, _modifier(modifiers, "range_mult", 1.0)))
	var hit_delay := maxf(0.0, float(unit.get("hit_delay", 0.25))) * maxf(0.0, _modifier(modifiers, "hit_delay_mult", 1.0))
	hit_delay = minf(hit_delay, maxf(0.0, attack_interval - 0.0001))
	var aoe_radius := maxf(0.0, float(unit.get("aoe_radius", 0.0))) * maxf(0.0, _modifier(modifiers, "aoe_radius_mult", 1.0))
	var damage_type := str(unit.get("damage_type", "physical"))
	if not DamageTypes.is_valid(StringName(damage_type)): damage_type = "physical"
	var special: Dictionary = {}
	var raw_special: Variant = unit.get("special", "")
	if raw_special is Dictionary: special = raw_special.duplicate(true)
	else: special.type = str(raw_special)
	var intelligence_multiplier := 1.0 + intelligence * 0.01
	if str(special.get("type", "")) == "heal":
		special.amount = maxf(0.0, float(special.get("amount", damage))) * intelligence_multiplier * maxf(0.0, _modifier(modifiers, "heal_amount_mult", 1.0))
	elif str(special.get("type", "")) == "slow":
		special.ratio = clampf(_modifier(modifiers, "slow_ratio", float(special.get("ratio", 0.65))), 0.1, 1.0)
		special.duration = maxf(0.0, float(special.get("duration", 2.0))) * intelligence_multiplier * maxf(0.0, _modifier(modifiers, "slow_duration_mult", 1.0))
	if _valid_modifier(modifiers, "base_damage_multiplier") or special.has("base_damage_multiplier"):
		special.base_damage_multiplier = maxf(0.0, _modifier(modifiers, "base_damage_multiplier", float(special.get("base_damage_multiplier", 1.0))))
	return {"stats": stats, "primary": primary, "level": actual_level,
		"hp": hp, "damage": damage, "armor": armor, "range": attack_range,
		"attack_interval": attack_interval, "speed": speed, "hit_delay": hit_delay,
		"aoe_radius": aoe_radius, "damage_type": damage_type, "special": special,
		"magic_armor": armor * 0.5 + intelligence * 0.6,
		"heal_multiplier": intelligence_multiplier}

static func _modifier(modifiers: Dictionary, key: String, fallback: float) -> float:
	return modifier_value(modifiers, key, fallback)

static func modifier_value(modifiers: Dictionary, key: String, fallback: float = 1.0) -> float:
	return float(modifiers[key]) if _valid_modifier(modifiers, key) else fallback

static func _valid_modifier(modifiers: Dictionary, key: String) -> bool:
	if not MODIFIER_KEYS.has(key) or not modifiers.has(key): return false
	var value: Variant = modifiers[key]
	return (value is int or value is float) and is_finite(float(value))
