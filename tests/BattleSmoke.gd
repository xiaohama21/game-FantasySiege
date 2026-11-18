extends SceneTree

var failures: Array = []
var checks := 0
var report: Dictionary = {"version": "0.1.2.0", "visuals": false, "cases": [], "stages": []}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.0001

func _battle(stage_id: String = "stage_01", roster: Array = [], levels: Dictionary = {}) -> SiegeBattle:
	var battle := SiegeBattle.new()
	battle.auto_step = false
	battle.render_visuals = false
	root.add_child(battle)
	battle.start(stage_id, Catalog.initial_roster() if roster.is_empty() else roster, levels)
	return battle

func _empty_battle() -> SiegeBattle:
	var battle := _battle()
	battle._waves.clear()
	return battle

func _run() -> void:
	if Catalog.stages().is_empty() or Catalog.units().is_empty():
		push_error("内容配置尚未完成：缺units.json或stages.json，不能执行战斗验收")
		quit(2)
		return
	report.units_sha256 = FileAccess.get_sha256("res://resources/units.json")
	report.stages_sha256 = FileAccess.get_sha256("res://resources/stages.json")
	_check(Catalog.stages().size() == 8, "0.1.2必须有8个可玩关卡")
	_check(Catalog.initial_roster().size() == 8, "首版必须有8个初始角色")
	_check(Catalog.playable_roster().size() == 12, "0.1.2必须有12个玩家角色")
	_test_stats()
	_test_frame_independence()
	_test_resources()
	_test_damage()
	_test_heal_and_dead_target()
	_test_aoe_and_slow()
	_test_phase_and_finish()
	_test_restart_and_capacity()
	_test_wide_world_and_roster()
	_test_pulse()
	_test_pulse_interrupt_benefit()
	_test_new_roles()
	_test_visual_rate_budget()
	_benchmark_64()
	for stage: Dictionary in Catalog.stages():
		_simulate_stage(str(stage.id), true)
		_simulate_stage(str(stage.id), false)
	for stage_id: String in ["stage_04", "stage_06", "stage_08"]:
		_simulate_stage(stage_id, true, true)
	report.checks = checks
	report.failures = failures
	report.passed = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var file := FileAccess.open("res://reports/battle_smoke.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("BATTLE_SMOKE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_stats() -> void:
	var unit := {"attributes": {"strength": 10, "agility": 20, "intelligence": 30},
		"primary_attribute": "intelligence", "hp": 100, "damage": 20, "armor": 40,
		"attack_interval": 2.0, "speed": 50.0}
	var stats := UnitStats.calculate(unit, 3)
	_check(_near(float(stats.stats.strength), 12.0) and _near(float(stats.stats.intelligence), 34.0), "三属性默认主+2副+1成长")
	_check(_near(float(stats.hp), 132.16), "力量生命和等级成长公式")
	_check(_near(float(stats.damage), 30.976), "主属性攻击和等级成长公式")
	_check(_near(float(stats.magic_armor), 40.4), "智力魔法护甲公式")
	_check(_near(float(stats.attack_interval), 2.0 / 1.088) and _near(float(stats.speed), 53.3), "敏捷攻击间隔和移动速度公式")
	_check(_near(float(stats.heal_multiplier), 1.34), "智力治疗与减速时长系数")
	_check(UnitStats.calculate(unit, -20).level == 1 and UnitStats.calculate(unit, 100).level == 20, "等级范围夹紧")
	_check(UnitStats.primary_label("intelligence") == "智力", "主属性中文标签")
	report.cases.append("three_attributes")

func _test_frame_independence() -> void:
	var coarse := _empty_battle()
	var fine := _empty_battle()
	for battle: SiegeBattle in [coarse, fine]:
		var guard := battle._spawn("iron_guard", 1)
		var medic := battle._spawn("rune_medic", 1)
		var enemy := battle._spawn("obsidian_guard", -1)
		guard.x = 300.0
		medic.x = 280.0
		enemy.x = 370.0
	for index: int in 30:
		coarse.advance(0.2)
	for index: int in 360:
		fine.advance(SiegeBattle.FIXED_STEP)
	var equal := coarse.units.size() == fine.units.size()
	if equal:
		for index: int in coarse.units.size():
			equal = equal and _near(float(coarse.units[index].hp), float(fine.units[index].hp)) and _near(float(coarse.units[index].x), float(fine.units[index].x))
	_check(equal and _near(float(coarse.get_snapshot().elapsed), float(fine.get_snapshot().elapsed)), "不同渲染帧分组产生同一固定步战斗结果")
	coarse.free()
	fine.free()
	report.cases.append("frame_independence")

func _test_resources() -> void:
	var battle := _empty_battle()
	var initial := battle.get_snapshot()
	_check(not battle.try_summon("unknown"), "未知型号召唤必须失败")
	_check(_near(float(battle.get_snapshot().energy), float(initial.energy)), "失败召唤不扣费")
	_check(battle.try_summon("iron_guard"), "初始资源可召唤低费铁卫")
	var first := battle.get_snapshot()
	_check(not battle.try_summon("iron_guard"), "冷却未结束不得重复召唤")
	_check(_near(float(battle.get_snapshot().energy), float(first.energy)), "冷却失败不扣费")
	battle._energy = 0.0
	_check(not battle.try_summon("lubu"), "资源不足不召唤")
	battle.advance(0.007)
	_check(_near(float(battle.get_snapshot().elapsed), 0.0), "不足固定步不推进时间")
	battle.advance(0.010)
	_check(_near(float(battle.get_snapshot().elapsed), SiegeBattle.FIXED_STEP), "固定步累积推进一次")
	battle.advance(40.0)
	_check(float(battle.get_snapshot().energy) <= float(battle.get_snapshot().capacity), "自动收入受容量约束")
	battle.free()
	report.cases.append("summon_and_fixed_step")

func _test_damage() -> void:
	var battle := _empty_battle()
	var target := battle._spawn("iron_guard", -1)
	target.max_hp = 1000.0
	target.hp = 1000.0
	target.armor = 50.0
	target.magic_armor = 25.0
	_check(_near(battle._damage_unit(target, 100.0, "physical", 1), 50.0), "物理全护甲")
	_check(_near(battle._damage_unit(target, 100.0, "magic", 1), 100.0 * 50.0 / 75.0), "魔法使用魔法护甲")
	_check(_near(battle._damage_unit(target, 100.0, "true", 1), 100.0), "真实忽略护甲")
	var calculated := UnitStats.calculate(Catalog.unit("iron_guard"), 1)
	_check(_near(float(target.stats.strength), float(calculated.stats.strength)), "敌人也从中央三属性计算")
	battle.free()
	report.cases.append("damage_types")

func _test_heal_and_dead_target() -> void:
	var battle := _empty_battle()
	var medic := battle._spawn("rune_medic", 1)
	var ally := battle._spawn("iron_guard", 1)
	var enemy := battle._spawn("riftling", -1)
	medic.x = 200.0
	ally.x = 220.0
	enemy.x = 225.0
	ally.hp = float(ally.max_hp) - 100.0
	enemy.hp = float(enemy.max_hp) * 0.3
	var before := float(ally.hp)
	_check(int(battle._healing_target(medic).uid) == int(ally.uid), "治疗仅选同阵营伤员")
	battle._begin_attack(medic, ally, true)
	battle._elapsed = 10.0
	battle._resolve_hits()
	_check(float(ally.hp) > before and float(ally.hp) <= float(ally.max_hp), "治疗提高生命且不溢出")
	ally.alive = false
	_check(battle._healing_target(medic).is_empty(), "治疗不选尸体")
	var attacker := battle._spawn("zhaoyun", 1)
	var replacement := battle._spawn("riftling", -1)
	attacker.x = 220.0
	enemy.x = 240.0
	replacement.x = 242.0
	var replacement_hp := float(replacement.hp)
	battle._begin_attack(attacker, enemy, false)
	battle._damage_unit(enemy, 999999.0, "true", 1)
	battle._elapsed = 20.0
	battle._resolve_hits()
	_check(_near(float(replacement.hp), replacement_hp), "命中前目标死亡不转移到其他单位")
	_check(not bool(enemy.alive), "死亡立即失去索敌与阻挡资格")
	battle.free()
	report.cases.append("healing_and_target_lifetime")

func _test_aoe_and_slow() -> void:
	var battle := _empty_battle()
	var cleaver := battle._spawn("guanyu", 1)
	var ally := battle._spawn("iron_guard", 1)
	var enemy_a := battle._spawn("riftling", -1)
	var enemy_b := battle._spawn("riftling", -1)
	cleaver.x = 200.0
	ally.x = 240.0
	enemy_a.x = 245.0
	enemy_b.x = 260.0
	cleaver.aoe_radius = 50.0
	var ally_hp := float(ally.hp)
	var a_hp := float(enemy_a.hp)
	var b_hp := float(enemy_b.hp)
	battle._begin_attack(cleaver, enemy_a, false)
	battle._elapsed = 10.0
	battle._resolve_hits()
	_check(float(enemy_a.hp) < a_hp and float(enemy_b.hp) < b_hp, "范围攻击命中半径内多敌人")
	_check(_near(float(ally.hp), ally_hp), "范围攻击不伤同阵营")
	var slower := battle._spawn("zhugeliang", 1)
	var slow_target := battle._spawn("obsidian_guard", -1)
	slower.special = {"type": "slow", "duration": 2.0, "ratio": 0.5}
	slower.aoe_radius = 0.0
	slower.damage = 1.0
	battle._begin_attack(slower, slow_target, false)
	battle._elapsed = 20.0
	battle._resolve_hits()
	_check(_near(float(slow_target.slow_ratio), 0.5), "减速倍率生效")
	_check(_near(float(slow_target.slow_timer), 2.0 * float(slower.heal_multiplier)), "智力延长减速持续时间")
	battle._hits.clear()
	for actor: Dictionary in battle.units:
		actor.attack_timer = 100.0
	battle.advance(5.0)
	_check(_near(float(slow_target.slow_ratio), 1.0), "减速到期恢复原速")
	battle.free()
	report.cases.append("area_and_slow")

func _test_phase_and_finish() -> void:
	var battle := _empty_battle()
	var boss := battle._spawn("obsidian_warden", -1)
	boss.special = {"phase_threshold": 0.5, "phase_damage_mult": 1.25, "phase_speed_mult": 1.15, "phase_attack_mult": 0.8}
	var original_damage := float(boss.damage)
	boss.hp = float(boss.max_hp) * 0.49
	battle._check_phase(boss)
	battle._check_phase(boss)
	_check(bool(boss.phase) and _near(float(boss.damage), original_damage * 1.25), "Boss半血阶段仅触发一次")
	var finish_counter := [0]
	battle.battle_finished.connect(func(_victory: bool) -> void: finish_counter[0] += 1)
	battle._enemy_hp = 0.0
	battle._check_finish()
	battle._check_finish()
	var terminal := battle.get_snapshot()
	battle.advance(10.0)
	_check(finish_counter[0] == 1, "结算信号只发一次")
	_check(str(terminal.outcome) == "victory", "敌基地归零胜利")
	_check(_near(float(battle.get_snapshot().elapsed), float(terminal.elapsed)) and _near(float(battle.get_snapshot().energy), float(terminal.energy)), "终局不推进收入/时间")
	_check(battle._hits.is_empty() and battle._waves.is_empty() and not battle.try_summon("iron_guard"), "终局取消攻击波次并禁召唤")
	battle.free()
	report.cases.append("boss_phase_and_terminal")

func _test_restart_and_capacity() -> void:
	var battle := _empty_battle()
	for index: int in SiegeBattle.MAX_UNITS:
		battle._spawn("iron_guard", 1)
	_check(battle.active_count() == SiegeBattle.MAX_UNITS, "可达到64活单位预算")
	battle._energy = 1000.0
	var old_energy := battle._energy
	_check(not battle.try_summon("zhaoyun") and _near(battle._energy, old_energy), "人数上限失败不扣费")
	battle._waves = [{"time": 0.0, "unit_id": "riftling", "sequence": 0}]
	battle.advance(0.1)
	_check(battle._waves.size() == 1, "人数满时敌波次延后而不丢失")
	battle.units[0].alive = false
	battle.advance(0.1)
	_check(battle._waves.is_empty() and battle.active_count() == SiegeBattle.MAX_UNITS, "空出名额后敌波次补发")
	battle.start("stage_02", Catalog.initial_roster(), {"iron_guard": 5})
	_check(battle.units.is_empty() and battle._hits.is_empty() and _near(float(battle.get_snapshot().elapsed), 0.0), "重开释放旧单位并清空延迟/时间")
	battle.try_summon("iron_guard")
	var stats := UnitStats.calculate(Catalog.unit("iron_guard"), 5)
	_check(_near(float(battle.units[0].max_hp), float(stats.hp)), "战斗继承本局等级快照与中央三属性")
	battle.stop()
	_check(battle.units.is_empty() and battle.get_snapshot().outcome == "idle", "stop完整清理")
	battle.free()
	report.cases.append("capacity_and_restart")

func _benchmark_64() -> void:
	var battle := _empty_battle()
	for index: int in 32:
		battle._spawn("iron_guard", 1)
		battle._spawn("obsidian_guard", -1)
	var before := Time.get_ticks_usec()
	battle.advance(5.0)
	var wall_ms := (Time.get_ticks_usec() - before) / 1000.0
	report.logic_performance = {"visuals": false, "active_count": battle.active_count(), "simulated_seconds": 5.0,
		"wall_ms": wall_ms, "ms_per_step": wall_ms / 300.0, "realtime_factor": 5000.0 / maxf(wall_ms, 0.001)}
	_check(battle.active_count() == 64, "64单位逻辑性能测试期间单位未丢失")
	print("LOGIC64 wall=%.1fms step=%.3fms realtime=%.1fx" % [wall_ms, wall_ms / 300.0, 5000.0 / maxf(wall_ms, 0.001)])
	battle.free()

func _test_wide_world_and_roster() -> void:
	var battle := _empty_battle()
	var snapshot := battle.get_snapshot()
	_check(_near(float(snapshot.world_width), 2560.0) and _near(float(snapshot.player_x), 100.0) and _near(float(snapshot.enemy_x), 2460.0), "两屏宽地图基地使用动态世界坐标")
	var enemy := battle._spawn("riftling", -1)
	_check(_near(float(enemy.x), float(snapshot.enemy_x) - 32.0), "敌军出生点使用宽地图右基地")
	_check(_near(float(battle.get_snapshot().frontline_x), 200.0), "远方敌人不开场跳空地图中央")
	var player := battle._spawn("iron_guard", 1)
	player.x = 500.0
	enemy.x = 1100.0
	_check(_near(float(battle.get_snapshot().frontline_x), 800.0), "两阵线接近时前线点取中点")
	enemy.x = 2000.0
	_check(_near(float(battle.get_snapshot().frontline_x), 600.0), "敌人远离时镜头点随玩家前线")
	var unit_stats := UnitStats.calculate(Catalog.unit("iron_guard"), 1)
	_check(_near(float(player.speed), float(unit_stats.speed) * 1.45), "双方长地图行军倍率进入实际移动")
	battle.start("stage_01", ["riftling", "unknown", "star_hammer", "iron_guard"])
	_check(battle._roster == ["star_hammer", "iron_guard"] and not battle.try_summon("riftling"), "新玩家可进编队，敌人与未知ID不能进玩家阵容")
	battle.start("stage_01", Catalog.playable_roster())
	_check(battle._roster.size() == 8, "出战阵容最多八个不同型号")
	battle.free()
	report.cases.append("wide_world_and_playable_roster")

func _test_pulse() -> void:
	var battle := _empty_battle()
	var initial_energy := battle._energy
	_check(not battle.try_pulse() and _near(battle._energy, initial_energy) and _near(battle._pulse_cooldown, 0.0), "无敌军脉冲不扣费或开冷却")
	var ally := battle._spawn("iron_guard", 1)
	var enemy := battle._spawn("obsidian_guard", -1)
	var boss := battle._spawn("obsidian_warden", -1)
	var far_enemy := battle._spawn("riftling", -1)
	ally.x = 500.0
	enemy.x = 550.0
	boss.x = 620.0
	far_enemy.x = 900.0
	for actor: Dictionary in [enemy, boss, far_enemy]:
		actor.hp = 1000.0
		actor.max_hp = 1000.0
		actor.hit_delay = 0.75
		actor.damage = 0.0 if actor == far_enemy else 200.0
	ally.damage = 0.0
	ally.speed = 0.0
	ally.attack_timer = 100.0
	battle._begin_attack(enemy, ally, false)
	battle._begin_attack(boss, {"base": true, "team": 1, "x": battle.player_x}, false)
	battle._begin_attack(far_enemy, ally, false)
	battle._energy = 79.0
	_check(not battle.try_pulse() and _near(battle._energy, 79.0) and _near(battle._pulse_cooldown, 0.0), "能量不足脉冲无副作用")
	battle._energy = 160.0
	var ally_hp := float(ally.hp)
	var base_hp := battle._player_hp
	_check(battle.try_pulse(), "前线脉冲成功")
	_check(_near(battle._energy, 80.0) and _near(battle._pulse_cooldown, 35.0), "成功脉冲一次性扣80能量并开35秒冷却")
	_check(_near(float(enemy.hp), 910.0) and _near(float(boss.hp), 910.0) and _near(float(far_enemy.hp), 1000.0), "脉冲90真实伤害只作用180px敌军范围")
	_check(_near(float(enemy.x), 610.0) and _near(float(boss.x), 635.0), "脉冲普通兵后推60px，Boss后推15px")
	_check(_near(float(enemy.stun_timer), 1.2) and _near(float(boss.stun_timer), 1.2), "脉冲敌军与Boss均晕眩1.2秒")
	_check(battle._hits.size() == 1 and int(battle._hits[0].attacker) == int(far_enemy.uid), "脉冲取消被击中敌军全部预警攻击，保留远处攻击")
	var after_energy := battle._energy
	_check(not battle.try_pulse() and _near(battle._energy, after_energy), "冷却中的脉冲失败不重复扣费")
	var after_push := float(enemy.x)
	battle.advance(0.5)
	_check(_near(float(enemy.x), after_push) and _near(float(ally.hp), ally_hp) and _near(battle._player_hp, base_hp), "晕眩停止移动且打断攻击不结算单位或基地伤害")
	battle.advance(0.8)
	_check(float(enemy.stun_timer) <= 0.00001 and float(enemy.x) < after_push, "晕眩到期恢复移动")
	battle._enemy_hp = 0.0
	battle._check_finish()
	var terminal := battle.get_snapshot()
	_check(not battle.try_pulse() and _near(battle._energy, float(terminal.energy)), "终局脉冲不扣费")
	battle.free()
	var cooldown_battle := _empty_battle()
	var stationary := cooldown_battle._spawn("obsidian_guard", -1)
	stationary.hp = 10000.0
	stationary.max_hp = 10000.0
	stationary.speed = 0.0
	stationary.damage = 0.0
	stationary.x = cooldown_battle.world_width - 40.0
	_check(cooldown_battle.try_pulse(), "冷却测试首个脉冲成功")
	_check(_near(float(stationary.x), cooldown_battle.world_width - 32.0), "脉冲后推夹在宽地图边缘，不把单位推到可视世界外")
	cooldown_battle.advance(35.0)
	_check(_near(cooldown_battle._pulse_cooldown, 0.0) and cooldown_battle.try_pulse(), "35秒固定步后脉冲恢复可用")
	cooldown_battle.stop()
	_check(_near(cooldown_battle._pulse_cooldown, 0.0), "重开/退出清空脉冲冷却")
	cooldown_battle.free()
	report.cases.append("pulse_resource_range_stun_and_cooldown")

func _test_pulse_interrupt_benefit() -> void:
	var baseline := _empty_battle()
	var countered := _empty_battle()
	var tanks: Array = []
	for battle: SiegeBattle in [baseline, countered]:
		var tank := battle._spawn("iron_guard", 1)
		var boss := battle._spawn("obsidian_warden", -1)
		tank.x = 500.0
		tank.damage = 0.0
		tank.attack_timer = 100.0
		tank.speed = 0.0
		boss.x = 550.0
		boss.hp = 10000.0
		boss.max_hp = 10000.0
		boss.damage = 200.0
		boss.speed = 0.0
		boss.hit_delay = 0.75
		boss.aoe_radius = 0.0
		tanks.append(tank)
		battle.advance(0.2)
	_check(not countered._hits.is_empty(), "Boss重击在0.75秒预警中有可打断待命中")
	_check(countered.try_pulse(), "在重击命中前发动反制脉冲")
	baseline.advance(1.0)
	countered.advance(1.0)
	var saved := float(tanks[1].hp) - float(tanks[0].hp)
	_check(saved > 0.0, "脉冲时机实际阻止Boss伤害并保留前排生命")
	report.pulse_benefit = {"boss_warning_seconds": 0.75, "pulse_at_seconds": 0.2, "prevented_damage": saved,
		"baseline_tank_hp": tanks[0].hp, "countered_tank_hp": tanks[1].hp, "pulse_energy_cost": 80}
	baseline.free()
	countered.free()
	report.cases.append("pulse_interrupt_has_actual_benefit")

func _test_new_roles() -> void:
	var battle := _empty_battle()
	var gunner := battle._spawn("rivet_gunner", 1)
	battle._enemy_hp = 10000.0
	var base_before := battle._enemy_hp
	battle._begin_attack(gunner, {"base": true, "team": -1, "x": battle.enemy_x}, false)
	battle._elapsed = 10.0
	battle._resolve_hits()
	_check(_near(base_before - battle._enemy_hp, float(gunner.damage) * 1.8), "绞弩炮手对基地使用1.8倍攻城倍率")
	var mage := battle._spawn("moon_mage", 1)
	var target_a := battle._spawn("obsidian_guard", -1)
	var target_b := battle._spawn("obsidian_guard", -1)
	var outside := battle._spawn("obsidian_guard", -1)
	target_a.x = 800.0
	target_b.x = 850.0
	outside.x = 920.0
	for target: Dictionary in [target_a, target_b, outside]:
		target.hp = 10000.0
		target.max_hp = 10000.0
	battle._begin_attack(mage, target_a, false)
	battle._elapsed = 20.0
	battle._resolve_hits()
	_check(_near(float(target_a.slow_ratio), 0.42) and _near(float(target_b.slow_ratio), 0.42) and _near(float(outside.slow_ratio), 1.0), "月灯术士对每个范围命中者施加减速，不波及半径外")
	var shield := UnitStats.calculate(Catalog.unit("star_hammer"), 2)
	var light_guard := UnitStats.calculate(Catalog.unit("iron_guard"), 2)
	_check(float(shield.hp) > float(light_guard.hp) and float(Catalog.unit("star_hammer").armor) > float(Catalog.unit("iron_guard").armor), "星槌卫士提供更强生命与护甲守线")
	var beast := UnitStats.calculate(Catalog.unit("spirit_beast"), 1)
	_check(float(beast.speed) > float(light_guard.speed) and float(Catalog.unit("spirit_beast").aoe_radius) > 0.0, "灵契兽卫提供快移范围补线身份")
	battle.free()
	report.cases.append("four_new_roles")

func _test_visual_rate_budget() -> void:
	var battle := _empty_battle()
	_check(battle.seed_performance_units(64) and battle.active_count() == 64, "战斗压力fixture可生成64活单位")
	for actor: Dictionary in battle.units:
		var mock := Node2D.new()
		battle.add_child(mock)
		actor.visual = mock
	battle._update_visual_rates()
	var high_rate := 0
	for actor: Dictionary in battle.units:
		if int(actor.visual_update_rate) == 60:
			high_rate += 1
	_check(high_rate == 12, "关键骨架更新策略最多12实例为60Hz，其余30Hz")
	_check(not battle.seed_performance_units(65), "压力fixture遵守64人数上限")
	battle.free()
	report.cases.append("visual_priority_budget_logic_only")

func _simulate_stage(stage_id: String, summon: bool, core_only: bool = false) -> void:
	var stage := Catalog.stage(stage_id)
	var level := int(stage.get("recommended_level", 1))
	var levels: Dictionary = {}
	for id: String in Catalog.playable_roster():
		levels[id] = level if not core_only or ["iron_guard", "ember_archer", "rune_medic", "guanyu"].has(id) else 1
	var battle := _battle(stage_id, _stage_roster(stage_id), levels)
	var count_summoned := 0
	var max_active := 0
	for tick: int in 3000:
		if str(battle.get_snapshot().outcome) != "running":
			break
		if summon:
			count_summoned += _autoplay(battle)
		battle.advance(0.2)
		max_active = maxi(max_active, battle.active_count())
	var snapshot := battle.get_snapshot()
	var strategy := "core_growth" if core_only else ("mixed_line" if summon else "no_summon")
	report.stages.append({"id": stage_id, "strategy": strategy,
		"recommended_level": level, "roster": battle._roster.duplicate(), "levels": levels,
		"balance_revision": str(stage.get("balance_revision", "baseline")),
		"outcome": snapshot.outcome, "elapsed": snapshot.elapsed, "player_hp": snapshot.player_hp,
		"enemy_hp": snapshot.enemy_hp, "summons": count_summoned, "max_active": max_active})
	_check(str(snapshot.outcome) == ("victory" if summon else "defeat"), "%s %s应%s；实际%s t=%.1f" % [stage_id, "混合召唤" if summon else "不召唤", "获胜" if summon else "失败", str(snapshot.outcome), float(snapshot.elapsed)])
	_check(max_active <= SiegeBattle.MAX_UNITS, "%s全局人数不超预算" % stage_id)
	print("STAGE %s Lv%d %s %s t=%.1f hp=%.0f/%.0f summons=%d" % [stage_id, level, strategy, snapshot.outcome, float(snapshot.elapsed), float(snapshot.player_hp), float(snapshot.enemy_hp), count_summoned])
	battle.free()

func _stage_roster(stage_id: String) -> Array:
	var number := int(stage_id.trim_prefix("stage_"))
	if number <= 3:
		return Catalog.initial_roster()
	var roster := ["iron_guard", "rune_medic", "ember_archer", "zhugeliang", "guanyu", "zhaoyun", "lubu", "star_hammer"]
	if number >= 5:
		roster[5] = "rivet_gunner"
	if number >= 7:
		roster[3] = "moon_mage"
	return roster

func _autoplay(battle: SiegeBattle) -> int:
	var counts: Dictionary = {}
	var frontline := 0
	var army := 0
	for actor: Dictionary in battle.units:
		if bool(actor.alive) and int(actor.team) == 1:
			counts[actor.id] = int(counts.get(actor.id, 0)) + 1
			army += 1
			if float(actor.range) < 100.0:
				frontline += 1
	var choices: Array = []
	if frontline < 2:
		choices.append("iron_guard")
	if army >= 4 and int(counts.get("rune_medic", 0)) < 1:
		choices.append("rune_medic")
	if frontline < 3 and int(counts.get("star_hammer", 0)) < 1:
		choices.append("star_hammer")
	if int(counts.get("ember_archer", 0)) < 3:
		choices.append("ember_archer")
	if int(counts.get("zhugeliang", 0)) < 2:
		choices.append("zhugeliang")
	if int(counts.get("moon_mage", 0)) < 2:
		choices.append("moon_mage")
	if int(counts.get("rivet_gunner", 0)) < 2:
		choices.append("rivet_gunner")
	if frontline < 4:
		choices.append("guanyu")
	choices.append_array(["lubu", "zhaoyun", "diaochan", "ember_archer"])
	for id: String in choices:
		if battle.try_summon(id):
			return 1
	return 0
