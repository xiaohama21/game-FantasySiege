class_name UnitStats
extends RefCounted

const ATTRIBUTES := ["strength", "agility", "intelligence"]

static func primary_label(primary: String) -> String:
	return str({"strength": "力量", "agility": "敏捷", "intelligence": "智力"}.get(primary, "力量"))

static func calculate(unit: Dictionary, level: int = 1) -> Dictionary:
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
	return {"stats": stats, "primary": primary, "level": actual_level,
		"hp": maxf(1.0, float(unit.get("hp", 100.0))) * (1.0 + 0.06 * (actual_level - 1)) * (1.0 + 0.015 * strength),
		"damage": maxf(0.0, float(unit.get("damage", 10.0))) * (1.0 + 0.05 * (actual_level - 1)) * (1.0 + 0.012 * float(stats[primary])),
		"attack_interval": maxf(0.1, float(unit.get("attack_interval", 1.0))) / (1.0 + 0.004 * agility),
		"speed": maxf(0.0, float(unit.get("speed", 60.0))) * (1.0 + 0.003 * agility),
		"magic_armor": maxf(0.0, float(unit.get("armor", 0.0))) * 0.5 + intelligence * 0.6,
		"heal_multiplier": 1.0 + intelligence * 0.01}
