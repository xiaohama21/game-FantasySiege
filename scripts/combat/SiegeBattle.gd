class_name SiegeBattle
extends Node2D

signal battle_finished(victory: bool)
signal combat_event(kind: String, position: Vector2, amount: float, team: int)

const FIXED_STEP := 1.0 / 60.0
const READY_EPSILON := 0.00001
const PLAYER_X := 100.0
const ENEMY_X := 1180.0
const GROUND_Y := 510.0
const SPACING := 16.0
const MAX_UNITS := 64
const CORPSE_DURATION := 0.8
const PULSE_COST := 80.0
const PULSE_COOLDOWN := 35.0
const PULSE_RADIUS := 180.0
const PULSE_DAMAGE := 90.0
const PULSE_STUN := 1.2
const PULSE_PUSH := 60.0
const REPORT_PULSE_SOURCE := "@pulse"
const REPORT_TOTAL_DEFAULTS := {
	"summons": 0, "fallen": 0, "damage": 0.0, "healing": 0.0,
	"base_damage": 0.0, "damage_taken": 0.0, "energy_spent": 0.0,
	"pulse_uses": 0, "pulse_damage": 0.0, "pulse_targets": 0, "pulse_interrupts": 0,
}

var auto_step := true
var render_visuals := true
var units: Array = []
var world_width := 2560.0
var player_x := PLAYER_X
var enemy_x := 2460.0
var _move_speed_multiplier := 1.35
var _stage: Dictionary = {}
var _roster: Array = []
var _levels: Dictionary = {}
var _study_modifiers: Dictionary = {}
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
var _pulse_cooldown := 0.0
var _visual_rate_timer := 0.0
var _defer_visual_positions := false
var _report_opening: Dictionary = {}
var _report_members: Dictionary = {}
var _report_totals: Dictionary = REPORT_TOTAL_DEFAULTS.duplicate(true)
var _report_frozen: Dictionary = {}
var _report_fixture := false

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

func start(stage_id: String, roster: Array, levels: Dictionary = {}, study_modifiers: Dictionary = {}) -> void:
	stop()
	_stage = Catalog.stage(stage_id)
	if _stage.is_empty():
		return
	world_width = maxf(1280.0, float(_stage.get("world_width", 2560.0)))
	player_x = clampf(float(_stage.get("player_x", 100.0)), 32.0, world_width - 132.0)
	enemy_x = clampf(float(_stage.get("enemy_x", world_width - 100.0)), player_x + 64.0, world_width - 32.0)
	_move_speed_multiplier = maxf(0.01, float(_stage.get("move_speed_multiplier", 1.35)))
	for id: Variant in roster:
		if _roster.size() >= 8:
			break
		if Catalog.playable_roster().has(id) and not _roster.has(id) and not Catalog.unit(str(id)).is_empty():
			_roster.append(str(id))
	_levels = levels.duplicate(true)
	_study_modifiers = study_modifiers.duplicate(true)
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
	_reset_battle_report()
	queue_redraw()

func stop() -> void:
	for unit: Dictionary in units:
		if unit.has("slow_sources"): unit.slow_sources.clear()
		unit.slow_ratio = 1.0
		unit.slow_timer = 0.0
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
	_study_modifiers.clear()
	_waves.clear()
	_hits.clear()
	_cooldowns.clear()
	_elapsed = 0.0
	_accumulator = 0.0
	_energy = 0.0
	_next_uid = 1
	_pulse_cooldown = 0.0
	_visual_rate_timer = 0.0
	_defer_visual_positions = false
	_outcome = "idle"
	_report_opening.clear()
	_report_members.clear()
	_report_totals = REPORT_TOTAL_DEFAULTS.duplicate(true)
	_report_frozen.clear()
	_report_fixture = false
	queue_redraw()

func try_summon(id: String) -> bool:
	if _outcome != "running" or not _roster.has(id) or active_count() >= MAX_UNITS:
		return false
	var definition := Catalog.unit(id)
	if definition.is_empty() or float(_cooldowns.get(id, 0.0)) > READY_EPSILON:
		return false
	var cost := maxf(0.0, float(definition.get("cost", 0.0)))
	if _energy + READY_EPSILON < cost:
		return false
	var spawned := _spawn(id, 1)
	if spawned.is_empty():
		return false
	_energy = maxf(0.0, _energy - cost)
	_cooldowns[id] = maxf(0.0, float(definition.get("cooldown", 1.0)))
	_record_energy_spent(cost)
	return true

func try_pulse() -> bool:
	if _outcome != "running" or _pulse_cooldown > READY_EPSILON or _energy + READY_EPSILON < PULSE_COST:
		return false
	var center_x := INF
	for actor: Dictionary in units:
		if bool(actor.alive) and int(actor.team) == -1:
			center_x = minf(center_x, float(actor.x))
	if center_x == INF:
		return false
	var affected: Array = []
	var interrupted: Dictionary = {}
	for actor: Dictionary in units:
		if bool(actor.alive) and int(actor.team) == -1 and absf(float(actor.x) - center_x) <= PULSE_RADIUS:
			affected.append(actor)
			interrupted[int(actor.uid)] = true
	_energy = maxf(0.0, _energy - PULSE_COST)
	_pulse_cooldown = PULSE_COOLDOWN
	var cancelled_attacks: Dictionary = {}
	_hits = _hits.filter(func(hit: Dictionary) -> bool:
		var cancelled := interrupted.has(int(hit.attacker))
		if cancelled and not bool(hit.get("heal", false)): cancelled_attacks[int(hit.attacker)] = true
		return not cancelled)
	_record_energy_spent(PULSE_COST)
	if _battle_report_recording():
		_report_totals.pulse_uses = int(_report_totals.pulse_uses) + 1
		_report_totals.pulse_targets = int(_report_totals.pulse_targets) + affected.size()
		_report_totals.pulse_interrupts = int(_report_totals.pulse_interrupts) + cancelled_attacks.size()
	combat_event.emit("pulse", Vector2(center_x, GROUND_Y - 45.0), PULSE_RADIUS, 1)
	for actor: Dictionary in affected:
		_damage_unit(actor, PULSE_DAMAGE, "true", 1, REPORT_PULSE_SOURCE)
		if not bool(actor.alive):
			continue
		actor.stun_timer = maxf(float(actor.stun_timer), PULSE_STUN)
		actor.action_timer = maxf(float(actor.action_timer), PULSE_STUN)
		var push := PULSE_PUSH * (0.25 if actor.special.has("phase_threshold") else 1.0)
		actor.x = maxf(float(actor.x), minf(float(actor.x) + push, world_width - 32.0))
		var visual: Variant = actor.visual
		if is_instance_valid(visual):
			visual.position = Vector2(float(actor.x), GROUND_Y)
			actor.render_x = float(actor.x)
		_set_visual_state(actor, "hurt", PULSE_STUN)
		combat_event.emit("stun", Vector2(float(actor.x), GROUND_Y - 95.0), PULSE_STUN, -1)
	_lines_valid = false
	_visual_rate_timer = 0.0
	queue_redraw()
	return true

func active_count() -> int:
	var total := 0
	for unit: Dictionary in units:
		if bool(unit.alive):
			total += 1
	return total

func get_snapshot() -> Dictionary:
	return {"stage_id": str(_stage.get("id", "")), "elapsed": _elapsed,
		"world_width": world_width, "player_x": player_x, "enemy_x": enemy_x, "frontline_x": _frontline_x(),
		"energy": _energy, "capacity": _capacity, "income": _income,
		"player_hp": _player_hp, "player_max_hp": _player_max_hp,
		"enemy_hp": _enemy_hp, "enemy_max_hp": _enemy_max_hp,
		"cooldowns": _cooldowns.duplicate(true), "active_count": active_count(),
		"pulse_cooldown": _pulse_cooldown, "pulse_cost": PULSE_COST, "pulse_max_cooldown": PULSE_COOLDOWN,
		"wave_pending": _waves.size(), "outcome": _outcome}

func get_battle_report() -> Dictionary:
	# All values are data snapshots; callers never receive live actor dictionaries.
	return _report_frozen.duplicate(true) if not _report_frozen.is_empty() else _build_battle_report()

func _reset_battle_report(fixture: bool = false) -> void:
	_report_opening = {"stage_id": str(_stage.get("id", "")), "roster": _roster.duplicate(),
		"levels": _levels.duplicate(true), "study_modifiers": _study_modifiers.duplicate(true)}
	_report_members.clear()
	for id: String in _roster:
		_report_members[id] = {"id": id, "name": str(Catalog.unit(id).get("name", id)),
			"level": clampi(int(_levels.get(id, 1)), 1, 20), "summons": 0, "fallen": 0,
			"damage": 0.0, "healing": 0.0, "base_damage": 0.0, "damage_taken": 0.0}
	_report_totals = REPORT_TOTAL_DEFAULTS.duplicate(true)
	_report_frozen.clear()
	_report_fixture = fixture

func _build_battle_report() -> Dictionary:
	var members: Array[Dictionary] = []
	for id: String in _report_opening.get("roster", []):
		if _report_members.has(id): members.append(_report_members[id].duplicate(true))
	return {"stage_id": str(_report_opening.get("stage_id", "")), "outcome": _outcome,
		"elapsed": _elapsed, "roster": _report_opening.get("roster", []).duplicate(),
		"levels": _report_opening.get("levels", {}).duplicate(true),
		"study_modifiers": _report_opening.get("study_modifiers", {}).duplicate(true),
		"members": members, "totals": _report_totals.duplicate(true), "fixture": _report_fixture}

func _battle_report_recording() -> bool:
	return _outcome == "running" and _report_frozen.is_empty()

func _record_energy_spent(amount: float) -> void:
	if _battle_report_recording():
		_report_totals.energy_spent = float(_report_totals.energy_spent) + maxf(0.0, amount)

func _record_member_amount(id: String, key: String, amount: float) -> void:
	if not _battle_report_recording() or not _report_members.has(id) or amount <= 0.0: return
	var member: Dictionary = _report_members[id]
	member[key] = float(member[key]) + amount
	_report_totals[key] = float(_report_totals[key]) + amount

func _record_player_spawn(actor: Dictionary) -> void:
	if not _battle_report_recording() or int(actor.team) != 1 or not _report_members.has(str(actor.id)): return
	var member: Dictionary = _report_members[str(actor.id)]
	member.summons = int(member.summons) + 1
	_report_totals.summons = int(_report_totals.summons) + 1

func _record_player_fallen(actor: Dictionary) -> void:
	if not _battle_report_recording() or int(actor.team) != 1 or not _report_members.has(str(actor.id)): return
	var member: Dictionary = _report_members[str(actor.id)]
	member.fallen = int(member.fallen) + 1
	_report_totals.fallen = int(_report_totals.fallen) + 1

func _record_effective_damage(target: Dictionary, amount: float, attacker_team: int, source_id: String) -> void:
	if not _battle_report_recording() or amount <= 0.0: return
	if int(target.team) == 1:
		_record_member_amount(str(target.id), "damage_taken", amount)
	elif attacker_team == 1:
		if source_id == REPORT_PULSE_SOURCE:
			_report_totals.damage = float(_report_totals.damage) + amount
			_report_totals.pulse_damage = float(_report_totals.pulse_damage) + amount
		else:
			_record_member_amount(source_id, "damage", amount)

func _frontline_x() -> float:
	var player_front := player_x
	var enemy_front := INF
	for actor: Dictionary in units:
		if not bool(actor.alive):
			continue
		if int(actor.team) == 1:
			player_front = maxf(player_front, float(actor.x))
		else:
			enemy_front = minf(enemy_front, float(actor.x))
	var point := (player_front + enemy_front) * 0.5 if enemy_front != INF and enemy_front - player_front <= 900.0 else player_front + 100.0
	return clampf(point, player_x, enemy_x)

func seed_performance_units(count: int = 24) -> bool:
	if _outcome != "running" or _roster.is_empty() or count < 2 or count > MAX_UNITS:
		return false
	var enemies: Array = []
	for id: String in Catalog.units():
		if not Catalog.playable_roster().has(id):
			enemies.append(id)
	if enemies.is_empty():
		return false
	_reset_battle_report(true)
	for actor: Dictionary in units:
		if is_instance_valid(actor.visual):
			actor.visual.free()
	units.clear()
	_unit_lookup.clear()
	_line_units[1].clear()
	_line_units[-1].clear()
	_friendly_ahead.clear()
	_lines_valid = false
	_waves.clear()
	_hits.clear()
	_visual_rate_timer = 0.0
	var player_count := (count + 1) / 2
	var center := world_width * 0.5
	for index: int in count:
		var team := 1 if index < player_count else -1
		var row := index if team == 1 else index - player_count
		var id: String = _roster[row % _roster.size()] if team == 1 else enemies[row % enemies.size()]
		var actor := _spawn(id, team, {"hp_mult": 20.0})
		actor.max_hp = maxf(float(actor.max_hp), 100000.0)
		actor.hp = float(actor.max_hp)
		actor.x = center - 60.0 - row * SPACING if team == 1 else center + 60.0 + row * SPACING
		if is_instance_valid(actor.visual):
			actor.visual.position = Vector2(float(actor.x), GROUND_Y)
			actor.render_x = float(actor.x)
	_update_visual_rates()
	queue_redraw()
	return true

func advance(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	if _outcome != "running":
		_decay_corpses(delta)
		return
	_accumulator += delta
	_defer_visual_positions = true
	while _accumulator + 0.0000001 >= FIXED_STEP and _outcome == "running":
		_accumulator -= FIXED_STEP
		_step(FIXED_STEP)
	_defer_visual_positions = false
	if render_visuals: _sync_visual_positions()
	queue_redraw()

func _sync_visual_positions() -> void:
	for actor: Dictionary in units:
		var x := float(actor.x)
		if is_equal_approx(x, float(actor.get("render_x", INF))): continue
		var visual: Variant = actor.visual
		if is_instance_valid(visual):
			visual.position = Vector2(x, GROUND_Y)
			actor.render_x = x

func _step(delta: float) -> void:
	_elapsed += delta
	_energy = minf(_capacity, _energy + _income * delta)
	_pulse_cooldown = maxf(0.0, _pulse_cooldown - delta)
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
		_tick_slows(actor, delta)
		actor.stun_timer = maxf(0.0, float(actor.stun_timer) - delta)
		_check_phase(actor)
		if float(actor.stun_timer) > 0.00001:
			continue
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
	_visual_rate_timer -= delta
	if render_visuals and _visual_rate_timer <= 0.0:
		_update_visual_rates()
		_visual_rate_timer = 0.5

func _spawn(id: String, team: int, wave: Dictionary = {}) -> Dictionary:
	var definition := Catalog.unit(id)
	if definition.is_empty() or active_count() >= MAX_UNITS:
		return {}
	var level := clampi(int(_levels.get(id, 1)), 1, 20) if team == 1 else 1
	var modifiers: Dictionary = {}
	var study_value: Variant = _study_modifiers.get(id, {}) if team == 1 else {}
	if study_value is Dictionary: modifiers = study_value.duplicate(true)
	# Wave HP/damage are input multipliers too. Final unit values remain owned
	# by UnitStats; enemies never consume the player's study map.
	if wave.has("hp_mult"):
		modifiers.hp_mult = maxf(0.01, UnitStats.modifier_value(modifiers, "hp_mult")) * maxf(0.01, UnitStats.modifier_value(wave, "hp_mult"))
	if wave.has("damage_mult"):
		modifiers.damage_mult = maxf(0.0, UnitStats.modifier_value(modifiers, "damage_mult")) * maxf(0.0, UnitStats.modifier_value(wave, "damage_mult"))
	var calculated := UnitStats.calculate(definition, level, modifiers)
	var hp := float(calculated.hp)
	var damage := float(calculated.damage)
	var spawn_x := player_x + 32.0 if team == 1 else enemy_x - 32.0
	for other: Dictionary in units:
		if bool(other.alive) and int(other.team) == team:
			if team == 1:
				spawn_x = minf(spawn_x, float(other.x) - SPACING)
			else:
				spawn_x = maxf(spawn_x, float(other.x) + SPACING)
	var actor := {"uid": _next_uid, "id": id, "name": str(definition.get("name", id)), "team": team,
		"x": spawn_x, "render_x": spawn_x, "hp": hp, "max_hp": hp, "damage": damage,
		"armor": float(calculated.armor),
		"range": float(calculated.range),
		"speed": float(calculated.speed) * _move_speed_multiplier, "stats": calculated.stats,
		"magic_armor": float(calculated.magic_armor), "heal_multiplier": float(calculated.heal_multiplier),
		"attack_interval": float(calculated.attack_interval),
		"hit_delay": float(calculated.hit_delay),
		"damage_type": str(calculated.damage_type),
		"aoe_radius": float(calculated.aoe_radius),
		"special": calculated.special, "attack_timer": 0.0, "action_timer": 0.0,
		"slow_timer": 0.0, "slow_ratio": 1.0, "slow_sources": {}, "stun_timer": 0.0, "alive": true, "phase": false,
		"visual_update_rate": 30,
		"corpse_timer": CORPSE_DURATION, "visual": null, "state": "", "level": level,
		"color": Color(str(definition.get("color", "#6be2d0" if team == 1 else "#ed8274")))}
	_next_uid += 1
	units.append(actor)
	_unit_lookup[int(actor.uid)] = actor
	_record_player_spawn(actor)
	_lines_valid = false
	if render_visuals and _actor_script != null:
		var visual: Node2D = _actor_script.new()
		add_child(visual)
		visual.position = Vector2(spawn_x, GROUND_Y)
		visual.z_index = 10 + int(actor.uid) % 20
		visual.call("configure", str(definition.get("visual_id", id)), team)
		if visual.has_method("set_playback_speed"):
			visual.call("set_playback_speed", _visual_playback_multiplier)
		if visual.has_method("set_update_rate"):
			visual.call("set_update_rate", 30)
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
	return {"base": true, "team": -int(actor.team), "x": enemy_x if int(actor.team) == 1 else player_x}

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
	if not _defer_visual_positions and is_instance_valid(visual):
		visual.position = Vector2(float(actor.x), GROUND_Y)
		actor.render_x = float(actor.x)

func _begin_attack(actor: Dictionary, target: Dictionary, heal: bool) -> void:
	actor.attack_timer = float(actor.attack_interval)
	var state := "skill" if heal else "attack"
	var natural := 0.9
	var visual: Variant = actor.visual
	if is_instance_valid(visual):
		var spec: Dictionary = visual.get("spec")
		natural = maxf(0.1, float(spec.get("durations", {}).get(state, 0.9)))
	actor.action_timer = maxf(float(actor.hit_delay), minf(natural, minf(float(actor.attack_interval) * 0.85, 1.2)))
	if str(actor.state) == state:
		_set_visual_state(actor, "idle")
	_set_visual_state(actor, state, float(actor.action_timer))
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
			var amount := float(attacker.damage) * maxf(0.0, float(attacker.special.get("base_damage_multiplier", 1.0)))
			var previous_base_hp := _player_hp if int(hit.target_team) == 1 else _enemy_hp
			if int(hit.target_team) == 1:
				_player_hp = maxf(0.0, _player_hp - amount)
			else:
				_enemy_hp = maxf(0.0, _enemy_hp - amount)
			if int(attacker.team) == 1 and int(hit.target_team) == -1:
				_record_member_amount(str(attacker.id), "base_damage", maxf(0.0, previous_base_hp - _enemy_hp))
			combat_event.emit("base_hit", Vector2(player_x if int(hit.target_team) == 1 else enemy_x, GROUND_Y - 70.0), amount, int(attacker.team))
			_check_finish()
			continue
		var target := _unit_by_uid(int(hit.target))
		if target.is_empty() or not bool(target.alive):
			continue
		if bool(hit.heal):
			if int(target.team) != int(attacker.team):
				continue
			var amount := maxf(0.0, float(attacker.special.get("amount", attacker.damage)))
			var restored := minf(amount, float(target.max_hp) - float(target.hp))
			target.hp = minf(float(target.max_hp), float(target.hp) + amount)
			if int(attacker.team) == 1:
				_record_member_amount(str(attacker.id), "healing", maxf(0.0, restored))
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
			_damage_unit(victim, float(attacker.damage), str(attacker.damage_type), int(attacker.team), str(attacker.id))
			if bool(victim.alive) and str(attacker.special.get("type", "")) == "slow":
				_apply_slow(victim, attacker)

func _apply_slow(target: Dictionary, attacker: Dictionary) -> void:
	var duration := maxf(0.0, float(attacker.special.get("duration", 0.0)))
	var ratio := clampf(float(attacker.special.get("ratio", 1.0)), 0.1, 1.0)
	if not bool(target.alive) or duration<=0.0 or ratio>=1.0: return
	var sources: Dictionary = target.slow_sources
	sources[int(attacker.uid)] = {"ratio": ratio, "remaining": duration}
	_refresh_slow_summary(target)

func _tick_slows(actor: Dictionary, delta: float) -> void:
	var sources: Dictionary = actor.slow_sources
	for source: Variant in sources.keys():
		var remaining := maxf(0.0, float(sources[source].remaining) - delta)
		if remaining<=0.0000001: sources.erase(source)
		else: sources[source].remaining = remaining
	_refresh_slow_summary(actor)

func _refresh_slow_summary(actor: Dictionary) -> void:
	var ratio := 1.0
	var remaining := 0.0
	for effect: Dictionary in actor.slow_sources.values():
		if float(effect.remaining)<=0.0: continue
		ratio = minf(ratio, float(effect.ratio))
		remaining = maxf(remaining, float(effect.remaining))
	actor.slow_ratio = ratio
	actor.slow_timer = remaining

func _damage_unit(target: Dictionary, raw: float, damage_type: String, attacker_team: int, report_source_id: String = "") -> float:
	if not bool(target.get("alive", false)):
		return 0.0
	var effective_armor := float(target.get("magic_armor", float(target.armor) * 0.5)) if damage_type == "magic" else maxf(0.0, float(target.armor) * DamageTypes.armor_factor(StringName(damage_type)))
	var amount := maxf(0.0, raw) * 50.0 / (50.0 + effective_armor)
	var previous_hp := float(target.hp)
	target.hp = maxf(0.0, float(target.hp) - amount)
	_record_effective_damage(target, maxf(0.0, previous_hp - float(target.hp)), attacker_team, report_source_id)
	combat_event.emit("hit", Vector2(float(target.x), GROUND_Y - 60.0), amount, attacker_team)
	if float(target.hp) <= 0.0:
		target.alive = false
		target.corpse_timer = CORPSE_DURATION
		_record_player_fallen(target)
		_set_visual_state(target, "death", CORPSE_DURATION)
		combat_event.emit("death", Vector2(float(target.x), GROUND_Y - 15.0), 0.0, int(target.team))
		_visual_rate_timer = 0.0
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
		_report_frozen = _build_battle_report()
		battle_finished.emit(_outcome == "victory")

func _unit_by_uid(uid: int) -> Dictionary:
	return _unit_lookup.get(uid, {})

func _update_visual_rates() -> void:
	var candidates: Array = []
	for actor: Dictionary in units:
		if not bool(actor.alive) or not is_instance_valid(actor.visual):
			continue
		var enemy := _nearest_enemy(actor)
		var distance := absf(float(enemy.x) - float(actor.x))
		var priority := 1000.0 - minf(distance, 1000.0)
		if actor.special.has("phase_threshold"):
			priority += 250.0
		if str(actor.state) == "attack" or str(actor.state) == "skill":
			priority += 120.0
		if float(actor.range) >= 100.0:
			priority += 80.0
		candidates.append({"actor": actor, "priority": priority})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.priority) == float(b.priority):
			return int(a.actor.uid) < int(b.actor.uid)
		return float(a.priority) > float(b.priority))
	var critical: Dictionary = {}
	var critical_limit := clampi(int(ProjectSettings.get_setting("fantasy_siege/visuals/critical_instance_limit", 12)), 1, 64)
	for index: int in mini(critical_limit, candidates.size()):
		critical[int(candidates[index].actor.uid)] = true
	var frame_groups := clampi(int(ProjectSettings.get_setting("fantasy_siege/visuals/frame_group_count", 2)), 2, 4)
	for actor: Dictionary in units:
		var visual: Variant = actor.visual
		if is_instance_valid(visual) and visual.has_method("set_frame_group_count") and visual.has_method("get_frame_group_count"):
			if int(visual.call("get_frame_group_count")) != frame_groups:
				visual.call("set_frame_group_count", frame_groups)
		var rate := 60 if critical.has(int(actor.uid)) else 30
		if int(actor.visual_update_rate) == rate:
			continue
		actor.visual_update_rate = rate
		if is_instance_valid(visual) and visual.has_method("set_update_rate"):
			visual.call("set_update_rate", rate)

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
		if float(actor.stun_timer) > 0.00001:
			draw_arc(Vector2(x, GROUND_Y - 100.0), 12.0, 0.0, TAU, 18, Color(1.0, 0.84, 0.34), 2.0)
