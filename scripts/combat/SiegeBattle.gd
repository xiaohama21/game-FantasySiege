class_name SiegeBattle
extends Node2D

signal battle_finished(victory: bool)
signal combat_event(kind: String, position: Vector2, amount: float, team: int)

const FIXED_STEP := 1.0 / 60.0
const PLAYER_X := 100.0
const ENEMY_X := 1180.0
const GROUND_Y := 510.0
const SPACING := 16.0
const MAX_UNITS := 64
const CORPSE_DURATION := 0.8

var auto_step := true
var render_visuals := true
var units: Array = []
var _stage: Dictionary = {}
var _roster: Array = []
var _levels: Dictionary = {}
var _waves: Array = []
var _hits: Array = []
var _cooldowns: Dictionary = {}
var _elapsed := 0.0
var _energy := 0.0
var _capacity := 400.0
var _income := 18.0
var _player_hp := 1.0
var _enemy_hp := 1.0
var _player_max_hp := 1.0
var _enemy_max_hp := 1.0
var _outcome := "idle"
var _accumulator := 0.0
var _next_uid := 1
var _actor_script: Script
var _visual_playback_multiplier := 1.0
var _unit_lookup: Dictionary = {}
var _line_units: Dictionary = {1: [], -1: []}
var _friendly_ahead: Dictionary = {}
var _lines_valid := false

func _process(delta: float) -> void:
	if auto_step:
		advance(delta)
	elif _outcome != "running":
		_decay_corpses(delta * _visual_playback_multiplier)

func set_visual_playback(multiplier: float) -> void:
	_visual_playback_multiplier = clampf(multiplier, 0.0, 4.0) if is_finite(multiplier) else 0.0
	for actor: Dictionary in units:
		var visual: Variant = actor.visual
		if is_instance_valid(visual) and visual.has_method("set_playback_speed"):
			visual.call("set_playback_speed", _visual_playback_multiplier)

func start(stage_id: String, roster: Array, levels: Dictionary = {}) -> void:
	stop()
	_stage = Catalog.stage(stage_id)
	if _stage.is_empty():
		return
	for id: Variant in roster:
		if Catalog.initial_roster().has(id) and not _roster.has(id) and not Catalog.unit(str(id)).is_empty():
			_roster.append(str(id))
	_levels = levels.duplicate(true)
	_capacity = maxf(1.0, float(_stage.get("capacity", 400.0)))
	_energy = clampf(float(_stage.get("initial_energy", 160.0)), 0.0, _capacity)
	_income = maxf(0.0, float(_stage.get("income", 18.0)))
	_player_max_hp = maxf(1.0, float(_stage.get("player_base_hp", 2000.0)))
	_enemy_max_hp = maxf(1.0, float(_stage.get("enemy_base_hp", 2000.0)))
	_player_hp = _player_max_hp
	_enemy_hp = _enemy_max_hp
	for id: String in _roster:
		_cooldowns[id] = 0.0
	var sequence := 0
	for wave: Dictionary in _stage.get("waves", []):
		for index: int in maxi(0, int(wave.get("count", 1))):
			var item := wave.duplicate(true)
			item.time = maxf(0.0, float(wave.get("time", 0.0)) + index * maxf(0.0, float(wave.get("interval", 1.0))))
			item.sequence = sequence
			_waves.append(item)
			sequence += 1
	_waves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.time) == float(b.time):
			return int(a.sequence) < int(b.sequence)
		return float(a.time) < float(b.time))
	if render_visuals and ResourceLoader.exists("res://scripts/visuals/SpineActor.gd"):
		_actor_script = load("res://scripts/visuals/SpineActor.gd")
	_outcome = "running"
	queue_redraw()

func stop() -> void:
	for unit: Dictionary in units:
		var visual: Variant = unit.get("visual")
		if is_instance_valid(visual):
			visual.free()
	units.clear()
	_unit_lookup.clear()
	_line_units[1].clear()
	_line_units[-1].clear()
	_friendly_ahead.clear()
	_lines_valid = false
	_stage.clear()
	_roster.clear()
	_levels.clear()
	_waves.clear()
	_hits.clear()
	_cooldowns.clear()
	_elapsed = 0.0
	_accumulator = 0.0
	_energy = 0.0
	_next_uid = 1
	_outcome = "idle"
	queue_redraw()

func try_summon(id: String) -> bool:
	if _outcome != "running" or not _roster.has(id) or active_count() >= MAX_UNITS:
		return false
	var definition := Catalog.unit(id)
	if definition.is_empty() or float(_cooldowns.get(id, 0.0)) > 0.00001:
		return false
	var cost := maxf(0.0, float(definition.get("cost", 0.0)))
	if _energy + 0.00001 < cost:
		return false
	var spawned := _spawn(id, 1)
	if spawned.is_empty():
		return false
	_energy = maxf(0.0, _energy - cost)
	_cooldowns[id] = maxf(0.0, float(definition.get("cooldown", 1.0)))
	return true

func active_count() -> int:
	var total := 0
	for unit: Dictionary in units:
		if bool(unit.alive):
			total += 1
	return total

func get_snapshot() -> Dictionary:
	return {"stage_id": str(_stage.get("id", "")), "elapsed": _elapsed,
		"energy": _energy, "capacity": _capacity, "income": _income,
		"player_hp": _player_hp, "player_max_hp": _player_max_hp,
		"enemy_hp": _enemy_hp, "enemy_max_hp": _enemy_max_hp,
		"cooldowns": _cooldowns.duplicate(true), "active_count": active_count(),
		"wave_pending": _waves.size(), "outcome": _outcome}

func advance(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	if _outcome != "running":
		_decay_corpses(delta)
		return
	_accumulator += delta
	while _accumulator + 0.0000001 >= FIXED_STEP and _outcome == "running":
		_accumulator -= FIXED_STEP
		_step(FIXED_STEP)
	queue_redraw()

func _step(delta: float) -> void:
	_elapsed += delta
	_energy = minf(_capacity, _energy + _income * delta)
	for id: String in _cooldowns:
		_cooldowns[id] = maxf(0.0, float(_cooldowns[id]) - delta)
	_decay_corpses(delta)
	while not _waves.is_empty() and float(_waves[0].time) <= _elapsed + 0.00001 and active_count() < MAX_UNITS:
		var wave: Dictionary = _waves.pop_front()
		_spawn(str(wave.get("unit_id", "")), -1, wave)
	_rebuild_lines()
	var turn_order: Array = _line_units[1].duplicate()
	turn_order.append_array(_line_units[-1])
	for actor: Dictionary in turn_order:
		if _outcome != "running":
			break
		if not bool(actor.alive):
			continue
		actor.attack_timer = maxf(0.0, float(actor.attack_timer) - delta)
		actor.action_timer = maxf(0.0, float(actor.action_timer) - delta)
		actor.slow_timer = maxf(0.0, float(actor.slow_timer) - delta)
		if float(actor.slow_timer) <= 0.0:
			actor.slow_ratio = 1.0
		_check_phase(actor)
		var special: Dictionary = actor.special
		var healing_target: Dictionary = {}
		if str(special.get("type", "")) == "heal":
			healing_target = _healing_target(actor)
		if not healing_target.is_empty():
			if float(actor.attack_timer) <= 0.00001:
				_begin_attack(actor, healing_target, true)
			elif float(actor.action_timer) <= 0.0:
				_set_visual_state(actor, "idle")
			continue
		var target := _nearest_enemy(actor)
		var distance := (float(target.x) - float(actor.x)) * int(actor.team)
		if distance <= float(actor.range) + 0.00001:
			if float(actor.attack_timer) <= 0.00001:
				_begin_attack(actor, target, false)
			elif float(actor.action_timer) <= 0.0:
				_set_visual_state(actor, "idle")
		else:
			_move_actor(actor, distance, delta)
	_resolve_hits()

func _spawn(id: String, team: int, wave: Dictionary = {}) -> Dictionary:
	var definition := Catalog.unit(id)
	if definition.is_empty() or active_count() >= MAX_UNITS:
		return {}
	var level := clampi(int(_levels.get(id, 1)), 1, 20) if team == 1 else 1
	var calculated := UnitStats.calculate(definition, level)
	var hp := maxf(1.0, float(calculated.hp) * maxf(0.01, float(wave.get("hp_mult", 1.0))))
	var damage := maxf(0.0, float(calculated.damage) * maxf(0.0, float(wave.get("damage_mult", 1.0))))
	var spawn_x := PLAYER_X + 32.0 if team == 1 else ENEMY_X - 32.0
	for other: Dictionary in units:
		if bool(other.alive) and int(other.team) == team:
			if team == 1:
				spawn_x = minf(spawn_x, float(other.x) - SPACING)
			else:
				spawn_x = maxf(spawn_x, float(other.x) + SPACING)
	var special: Dictionary = {}
	var special_value: Variant = definition.get("special", "")
	if special_value is Dictionary:
		special = special_value.duplicate(true)
	else:
		special.type = str(special_value)
	var actor := {"uid": _next_uid, "id": id, "name": str(definition.get("name", id)), "team": team,
		"x": spawn_x, "hp": hp, "max_hp": hp, "damage": damage,
		"armor": maxf(0.0, float(definition.get("armor", 0.0))),
		"range": maxf(SPACING, float(definition.get("range", 40.0))),
		"speed": float(calculated.speed), "stats": calculated.stats,
		"magic_armor": float(calculated.magic_armor), "heal_multiplier": float(calculated.heal_multiplier),
		"attack_interval": float(calculated.attack_interval),
		"hit_delay": maxf(0.0, float(definition.get("hit_delay", 0.25))),
		"damage_type": str(definition.get("damage_type", "physical")),
		"aoe_radius": maxf(0.0, float(definition.get("aoe_radius", 0.0))),
		"special": special, "attack_timer": 0.0, "action_timer": 0.0,
		"slow_timer": 0.0, "slow_ratio": 1.0, "alive": true, "phase": false,
		"corpse_timer": CORPSE_DURATION, "visual": null, "state": "", "level": level,
		"color": Color(str(definition.get("color", "#6be2d0" if team == 1 else "#ed8274")))}
	_next_uid += 1
	units.append(actor)
	_unit_lookup[int(actor.uid)] = actor
	_lines_valid = false
	if render_visuals and _actor_script != null:
		var visual: Node2D = _actor_script.new()
		add_child(visual)
		visual.position = Vector2(spawn_x, GROUND_Y)
		visual.z_index = 10 + int(actor.uid) % 20
		visual.call("configure", str(definition.get("visual_id", id)), team)
		if visual.has_method("set_playback_speed"):
			visual.call("set_playback_speed", _visual_playback_multiplier)
		actor.visual = visual
		_set_visual_state(actor, "move")
	combat_event.emit("spawn", Vector2(spawn_x, GROUND_Y - 25.0), 0.0, team)
	return actor

func _nearest_enemy(actor: Dictionary) -> Dictionary:
	if not _lines_valid:
		_rebuild_lines()
	for other: Dictionary in _line_units[-int(actor.team)]:
		if bool(other.alive) and (float(other.x) - float(actor.x)) * int(actor.team) >= -0.00001:
			return other
	return {"base": true, "team": -int(actor.team), "x": ENEMY_X if int(actor.team) == 1 else PLAYER_X}

func _rebuild_lines() -> void:
	_line_units[1].clear()
	_line_units[-1].clear()
	_friendly_ahead.clear()
	for actor: Dictionary in units:
		if bool(actor.alive):
			_line_units[int(actor.team)].append(actor)
	_line_units[1].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) > float(b.x))
	_line_units[-1].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.x) < float(b.x))
	for team: int in [1, -1]:
		var previous: Dictionary = {}
		for actor: Dictionary in _line_units[team]:
			_friendly_ahead[int(actor.uid)] = previous
			previous = actor
	_lines_valid = true

func _healing_target(actor: Dictionary) -> Dictionary:
	var target: Dictionary = {}
	var greatest_missing := 0.0
	var candidates: Array = _line_units[int(actor.team)] if _lines_valid else units
	for other: Dictionary in candidates:
		if not bool(other.alive) or int(other.team) != int(actor.team):
			continue
		if absf(float(other.x) - float(actor.x)) > float(actor.range):
			continue
		var missing := (float(other.max_hp) - float(other.hp)) / float(other.max_hp)
		if missing > greatest_missing + 0.00001:
			greatest_missing = missing
			target = other
	return target

func _move_actor(actor: Dictionary, target_distance: float, delta: float) -> void:
	var distance := minf(maxf(0.0, target_distance - float(actor.range)), float(actor.speed) * float(actor.slow_ratio) * delta)
	var front: Dictionary = _friendly_ahead.get(int(actor.uid), {})
	if not front.is_empty() and bool(front.alive):
		var ahead := (float(front.x) - float(actor.x)) * int(actor.team)
		distance = minf(distance, maxf(0.0, ahead - SPACING))
	actor.x = float(actor.x) + distance * int(actor.team)
	if distance > 0.00001 and float(actor.action_timer) <= 0.0:
		_set_visual_state(actor, "move")
	elif float(actor.action_timer) <= 0.0:
		_set_visual_state(actor, "idle")
	var visual: Variant = actor.visual
	if is_instance_valid(visual):
		visual.position = Vector2(float(actor.x), GROUND_Y)

func _begin_attack(actor: Dictionary, target: Dictionary, heal: bool) -> void:
	actor.attack_timer = float(actor.attack_interval)
	actor.action_timer = maxf(0.25, float(actor.hit_delay))
	_set_visual_state(actor, "skill" if heal else "attack", float(actor.action_timer))
	_hits.append({"due": _elapsed + float(actor.hit_delay), "attacker": int(actor.uid),
		"target": int(target.get("uid", 0)), "base": bool(target.get("base", false)),
		"target_team": int(target.team), "heal": heal})
	combat_event.emit("cast" if heal else "attack", Vector2(float(target.x), GROUND_Y - 45.0), float(actor.hit_delay), int(actor.team))

func _resolve_hits() -> void:
	var future: Array = []
	var due: Array = []
	for hit: Dictionary in _hits:
		if float(hit.due) <= _elapsed + 0.00001:
			due.append(hit)
		else:
			future.append(hit)
	_hits = future
	for hit: Dictionary in due:
		if _outcome != "running":
			break
		var attacker := _unit_by_uid(int(hit.attacker))
		if attacker.is_empty() or not bool(attacker.alive):
			continue
		if bool(hit.base):
			var amount := float(attacker.damage)
			if int(hit.target_team) == 1:
				_player_hp = maxf(0.0, _player_hp - amount)
			else:
				_enemy_hp = maxf(0.0, _enemy_hp - amount)
			combat_event.emit("base_hit", Vector2(PLAYER_X if int(hit.target_team) == 1 else ENEMY_X, GROUND_Y - 70.0), amount, int(attacker.team))
			_check_finish()
			continue
		var target := _unit_by_uid(int(hit.target))
		if target.is_empty() or not bool(target.alive):
			continue
		if bool(hit.heal):
			if int(target.team) != int(attacker.team):
				continue
			var amount := maxf(0.0, float(attacker.special.get("amount", attacker.damage))) * float(attacker.heal_multiplier)
			var restored := minf(amount, float(target.max_hp) - float(target.hp))
			target.hp = minf(float(target.max_hp), float(target.hp) + amount)
			combat_event.emit("heal", Vector2(float(target.x), GROUND_Y - 70.0), restored, int(attacker.team))
			continue
		var radius := float(attacker.aoe_radius)
		var targets: Array = [target]
		if radius > 0.0:
			targets.clear()
			for other: Dictionary in units:
				if bool(other.alive) and int(other.team) != int(attacker.team) and absf(float(other.x) - float(target.x)) <= radius:
					targets.append(other)
		for victim: Dictionary in targets:
			_damage_unit(victim, float(attacker.damage), str(attacker.damage_type), int(attacker.team))
			if bool(victim.alive) and str(attacker.special.get("type", "")) == "slow":
				victim.slow_timer = maxf(float(victim.slow_timer), maxf(0.0, float(attacker.special.get("duration", 2.0))) * float(attacker.heal_multiplier))
				victim.slow_ratio = minf(float(victim.slow_ratio), clampf(float(attacker.special.get("ratio", 0.65)), 0.1, 1.0))

func _damage_unit(target: Dictionary, raw: float, damage_type: String, attacker_team: int) -> float:
	if not bool(target.get("alive", false)):
		return 0.0
	var effective_armor := float(target.get("magic_armor", float(target.armor) * 0.5)) if damage_type == "magic" else maxf(0.0, float(target.armor) * DamageTypes.armor_factor(StringName(damage_type)))
	var amount := maxf(0.0, raw) * 50.0 / (50.0 + effective_armor)
	target.hp = maxf(0.0, float(target.hp) - amount)
	combat_event.emit("hit", Vector2(float(target.x), GROUND_Y - 60.0), amount, attacker_team)
	if float(target.hp) <= 0.0:
		target.alive = false
		target.corpse_timer = CORPSE_DURATION
		_set_visual_state(target, "death", CORPSE_DURATION)
		combat_event.emit("death", Vector2(float(target.x), GROUND_Y - 15.0), 0.0, int(target.team))
	elif float(target.action_timer) <= 0.0:
		target.action_timer = 0.12
		_set_visual_state(target, "hurt", 0.12)
	return amount

func _check_phase(actor: Dictionary) -> void:
	if bool(actor.phase):
		return
	var threshold := float(actor.special.get("phase_threshold", 0.0))
	if threshold <= 0.0 or float(actor.hp) / float(actor.max_hp) > threshold:
		return
	actor.phase = true
	actor.damage = float(actor.damage) * maxf(0.0, float(actor.special.get("phase_damage_mult", 1.0)))
	actor.speed = float(actor.speed) * maxf(0.0, float(actor.special.get("phase_speed_mult", 1.0)))
	actor.attack_interval = maxf(0.1, float(actor.attack_interval) * maxf(0.1, float(actor.special.get("phase_attack_mult", 1.0))))
	combat_event.emit("phase", Vector2(float(actor.x), GROUND_Y - 100.0), threshold, int(actor.team))

func _check_finish() -> void:
	if _outcome != "running":
		return
	if _enemy_hp <= 0.0 or _player_hp <= 0.0:
		_outcome = "victory" if _enemy_hp <= 0.0 else "defeat"
		_hits.clear()
		_waves.clear()
		_accumulator = 0.0
		for actor: Dictionary in units:
			if bool(actor.alive):
				_set_visual_state(actor, "idle")
		battle_finished.emit(_outcome == "victory")

func _unit_by_uid(uid: int) -> Dictionary:
	return _unit_lookup.get(uid, {})

func _set_visual_state(actor: Dictionary, state: String, duration: float = 0.0) -> void:
	if str(actor.state) == state and duration <= 0.0:
		return
	actor.state = state
	var visual: Variant = actor.visual
	if is_instance_valid(visual):
		visual.call("play_state", state, duration)

func _decay_corpses(delta: float) -> void:
	for index: int in range(units.size() - 1, -1, -1):
		var actor: Dictionary = units[index]
		if bool(actor.alive):
			continue
		actor.corpse_timer = float(actor.corpse_timer) - delta
		var visual: Variant = actor.visual
		if is_instance_valid(visual):
			visual.modulate.a = clampf(float(actor.corpse_timer) / 0.35, 0.0, 1.0)
		if float(actor.corpse_timer) <= 0.0:
			if is_instance_valid(visual):
				visual.free()
			units.remove_at(index)
			_unit_lookup.erase(int(actor.uid))
	queue_redraw()

func _draw() -> void:
	if not render_visuals:
		return
	for actor: Dictionary in units:
		if not bool(actor.alive):
			continue
		var x := float(actor.x)
		var width := 38.0 if not bool(actor.special.has("phase_threshold")) else 72.0
		var bar_y := GROUND_Y - 115.0
		var tint := Color(0.28, 0.88, 0.77) if int(actor.team) == 1 else Color(0.97, 0.41, 0.37)
		if not is_instance_valid(actor.visual):
			draw_circle(Vector2(x, GROUND_Y - 26.0), 22.0, actor.color)
			draw_line(Vector2(x, GROUND_Y - 50.0), Vector2(x + 20.0 * int(actor.team), GROUND_Y - 60.0), tint, 4.0)
		draw_rect(Rect2(x - width * 0.5 - 2.0, bar_y - 2.0, width + 4.0, 7.0), Color(0.035, 0.045, 0.075, 0.85))
		draw_rect(Rect2(x - width * 0.5, bar_y, width * clampf(float(actor.hp) / float(actor.max_hp), 0.0, 1.0), 3.0), tint)
		if bool(actor.phase):
			draw_arc(Vector2(x, GROUND_Y - 5.0), 42.0, PI, TAU, 18, Color(1.0, 0.42, 0.13, 0.65), 2.5)
