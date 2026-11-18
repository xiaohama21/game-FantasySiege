extends Control

var world: WorldBackdrop
var world_host: Node2D
var screen: Control
var battle
var tab := "远征"
var active_stage := ""
var run_token := ""
var paused := false
var speed := 1.0
var selected_actor := "guanyu"
var selected_visual := "d69_097"
var selected_chapter := 1
var view_x := 0.0
var view_max := 0.0
var follow_frontline := true
var dragging := false
var follow_button: Button
var pulse_button: Button
var view_slider: HSlider
var draft_roster: Array = []
var summon_buttons: Array[Button] = []
var summon_labels: Array = []
var energy_label: Label
var timer_label: Label
var player_hp: ProgressBar
var enemy_hp: ProgressBar
var player_label: Label
var enemy_label: Label
var status_label: Label
var pause_button: Button
var speed_button: Button
var result_panel: Panel
var viewer
var toast: Label
var toast_time := 0.0
var motes: Array = []

func _ready() -> void:
	theme = SiegeStyle.make_theme()
	world_host = Node2D.new()
	add_child(world_host)
	world = WorldBackdrop.new()
	world_host.add_child(world)
	show_home()

func _process(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		if is_instance_valid(toast): toast.visible = toast_time > 0
	if is_instance_valid(battle):
		if not paused: battle.advance(delta * speed)
		_update_camera(delta)
		_update_hud()
	for mote: Dictionary in motes.duplicate():
		mote.life -= delta
		if is_instance_valid(mote.node):
			mote.node.position.y -= delta * 30
			mote.node.modulate.a = clampf(mote.life, 0, 1)
		if mote.life <= 0:
			if is_instance_valid(mote.node): mote.node.queue_free()
			motes.erase(mote)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(battle): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging = false
		else:
			var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			if point.y >= 164 and point.y < 526 and point.x >= 0 and point.x <= 1280 and not is_instance_valid(result_panel):
				dragging = true
				follow_frontline = false
	elif event is InputEventMouseMotion and dragging:
		var local_motion: Vector2 = get_global_transform_with_canvas().basis_xform_inv(event.relative)
		_set_view_position(view_x - local_motion.x)

func _set_view_position(value: float) -> void:
	view_x = clampf(value, 0, view_max)
	world_host.position.x = -view_x
	if is_instance_valid(view_slider): view_slider.set_value_no_signal(view_x)

func _update_camera(delta: float) -> void:
	if not is_instance_valid(result_panel):
		var movement := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		var mouse := get_local_mouse_position()
		if not dragging and mouse.y >= 164 and mouse.y < 526:
			if mouse.x >= 0 and mouse.x < 24: movement -= 1
			elif mouse.x > 1256 and mouse.x <= 1280: movement += 1
		if movement != 0:
			follow_frontline = false
			_set_view_position(view_x + movement * 650 * delta)
	if follow_frontline and not dragging:
		var snap: Dictionary = battle.get_snapshot()
		var target := clampf(float(snap.get("frontline_x", 100)) - 560, 0, view_max)
		_set_view_position(lerpf(view_x, target, minf(1, delta * 4.5)))
	if is_instance_valid(follow_button): follow_button.text = "跟随中" if follow_frontline else "跟随战线"

func _resume_follow() -> void:
	follow_frontline = true
	dragging = false

func _slide_view(value: float) -> void:
	follow_frontline = false
	_set_view_position(value)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if is_instance_valid(battle):
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			var index: int = event.keycode - KEY_1
			if index < draft_roster.size(): _summon(str(draft_roster[index]))
		elif event.keycode == KEY_SPACE: _toggle_pause()
		elif event.keycode == KEY_F: _toggle_speed()
		elif event.keycode == KEY_P: _pulse()
		elif event.keycode == KEY_C: _resume_follow()
		elif event.keycode == KEY_ESCAPE: show_home()
	elif event.keycode == KEY_ESCAPE: show_home()

func _clear_screen() -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.z_index = 100
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	viewer = null
	view_slider = null
	toast = null
	result_panel = null
	for mote: Dictionary in motes:
		if is_instance_valid(mote.node): mote.node.queue_free()
	motes.clear()

func _stop_battle() -> bool:
	if is_instance_valid(battle) and not run_token.is_empty() and str(battle.get_snapshot().get("outcome", "")) == "victory":
		_message("奖励尚未保存，请先重试领取。")
		return false
	if not run_token.is_empty(): ProfileStore.abandon(run_token)
	run_token = ""
	if is_instance_valid(battle):
		battle.stop()
		battle.get_parent().remove_child(battle)
		battle.queue_free()
	battle = null
	dragging = false
	view_max = 0
	_set_view_position(0)
	return true

func _panel(rect: Rect2, color: Color = SiegeStyle.PAPER, parent: Node = null) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", SiegeStyle.box(color, 16, Color(color.lightened(0.18), 0.6)))
	(parent if parent != null else screen).add_child(p)
	return p

func _label(value: String, rect: Rect2, font_size: int = 18, color: Color = SiegeStyle.INK, parent: Node = null) -> Label:
	var l := Label.new()
	l.clip_text = true
	l.text = value
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else screen).add_child(l)
	return l

func _button(value: String, rect: Rect2, action: Callable, parent: Node = null, accent: bool = false) -> Button:
	var b := Button.new()
	b.clip_text = true
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if accent:
		b.add_theme_stylebox_override("normal", SiegeStyle.box(SiegeStyle.TEAL, 10))
		b.add_theme_color_override("font_color", Color("fffaed"))
	b.pressed.connect(action)
	(parent if parent != null else screen).add_child(b)
	return b

func _message(value: String) -> void:
	if not is_instance_valid(toast):
		toast = _label("", Rect2(265, 668, 980, 33), 18, Color("ffe3a3"))
	toast.text = value
	toast.visible = true
	toast_time = 5

func show_home(next_tab: String = "远征") -> void:
	if not _stop_battle(): return
	_clear_screen()
	tab = next_tab
	world.battle_mode = false
	world.configure_width(1280, 1)
	var sidebar := _panel(Rect2(20, 20, 200, 680), Color("162e3b"))
	_label("FANTASY SIEGE", Rect2(16, 20, 175, 25), 14, Color("a3c6bd"), sidebar)
	_label("星灯远征", Rect2(16, 48, 180, 45), 32, Color("f5deb1"), sidebar)
	_label("循光而行 · 重燃诸岛", Rect2(16, 101, 175, 35), 15, Color("9bb4b3"), sidebar)
	var tabs := ["远征", "英魂", "编队", "图鉴"]
	for i in tabs.size():
		var title: String = tabs[i]
		_button(title, Rect2(16, 175 + i * 66, 168, 51), show_home.bind(title), sidebar, title == tab)
	_label("本地学习版\nv" + str(ProjectSettings.get_setting("application/config/version")), Rect2(18, 603, 172, 55), 14, Color("8ba6a7"), sidebar)
	_label(tab, Rect2(254, 27, 680, 45), 32, Color("f1e4c6"))
	_panel(Rect2(1053, 27, 201, 45), Color("223f4b"))
	_label("星砂  %d" % ProfileStore.credits(), Rect2(1070, 33, 180, 32), 20, Color("f4d28a"))
	if tab == "远征": _campaign_page()
	elif tab == "英魂": _heroes_page()
	elif tab == "编队": _squad_page()
	else: _gallery_page()
	if not ProfileStore.error_message.is_empty(): _message(ProfileStore.error_message)

func _select_chapter(value: int) -> void:
	selected_chapter = value
	show_home("远征")

func _campaign_page() -> void:
	var cleared: Array = ProfileStore.data.get("cleared", [])
	var hero := _panel(Rect2(254, 93, 1000, 125), Color("224957"))
	_label("沿着微光，重连破碎的航路", Rect2(24, 14, 750, 38), 29, Color("f4e8cb"), hero)
	_label("星灯 %d / 8  ·  英魂 %d / 12" % [cleared.size(), ProfileStore.data.get("owned", []).size()], Rect2(24, 61, 560, 30), 20, Color("bdcfca"), hero)
	_button("裂隙初明", Rect2(616, 59, 163, 44), _select_chapter.bind(1), hero, selected_chapter == 1)
	_button("黄铜迷航", Rect2(795, 59, 180, 44), _select_chapter.bind(2), hero, selected_chapter == 2)
	var stages := Catalog.stages()
	var column := 0
	for i in stages.size():
		var stage: Dictionary = stages[i]
		if int(stage.get("chapter", 1)) != selected_chapter: continue
		var p := _panel(Rect2(254 + column * 252, 237, 238, 362))
		column += 1
		var unlocked: bool = ProfileStore.stage_unlocked(str(stage.id))
		var complete: bool = cleared.has(str(stage.id))
		_label("%02d  ·  %s" % [i + 1, "已点亮" if complete else "待远征" if unlocked else "未抵达"], Rect2(16, 14, 205, 26), 16, SiegeStyle.TEAL if complete else SiegeStyle.MUTED, p)
		_label(str(stage.get("name", "无名遗迹")), Rect2(16, 49, 205, 40), 25, SiegeStyle.INK, p)
		_label("推荐主力 Lv.%d" % int(stage.get("recommended_level", 1)), Rect2(16, 98, 205, 28), 17, SiegeStyle.TEAL, p)
		var advice := _label(str(stage.get("hint", "前排持续补线，远程负责突破。")), Rect2(16, 136, 205, 85), 17, SiegeStyle.INK, p)
		advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var reward: Dictionary = ProfileStore.reward_preview(str(stage.id))
		_label("%s %d 星砂" % ["重访" if complete else "首通", int(reward.credits)], Rect2(16, 226, 205, 26), 18, Color("9a712d"), p)
		var names: Array[String] = []
		for id: String in Catalog.reward_units(str(stage.id)): names.append(str(Catalog.unit(id).get("name", id)))
		var reward_text := "英魂 · " + "、".join(names) if not names.is_empty() else "星砂用于训练英魂"
		var reward_label := _label(reward_text, Rect2(16, 257, 205, 48), 15, SiegeStyle.MUTED, p)
		reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var button := _button("重访" if complete else "出征" if unlocked else "先点亮前一关", Rect2(16, 311, 205, 38), start_stage.bind(str(stage.id)), p, unlocked)
		button.disabled = not unlocked or not ProfileStore.can_modify()
	_label("1—8 召唤  ·  P 脉冲  ·  空格 暂停  ·  ← → / 鼠标拖动查看战场", Rect2(261, 618, 973, 30), 17, Color("b6c8c2"))

func _card_grid(rect: Rect2, columns: int) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.position = rect.position
	scroll.size = rect.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	return grid

func _hero_card(id: String, rect: Rect2, parent: Node = null) -> Panel:
	var unit := Catalog.unit(id)
	var p := _panel(rect, SiegeStyle.PAPER, parent)
	_label(str(unit.get("name", id)), Rect2(16, 13, rect.size.x - 28, 35), 24, SiegeStyle.INK, p)
	_label("%s · %s" % [str(unit.get("role_name", unit.get("role", "英魂"))), "Lv.%d" % ProfileStore.level(id) if ProfileStore.owns(id) else "未契约"], Rect2(16, 53, rect.size.x - 28, 28), 16, SiegeStyle.TEAL, p)
	var attr := str(unit.get("primary_attribute", "strength"))
	_label("主属性 · " + _attribute_name(attr), Rect2(16, 85, rect.size.x - 28, 28), 16, Color("b07c34"), p)
	return p

func _heroes_page() -> void:
	var roster := Catalog.playable_roster()
	if not roster.has(selected_actor): selected_actor = str(roster[0])
	var grid := _card_grid(Rect2(254, 98, 442, 535), 2)
	for id: String in roster:
		var p := _hero_card(id, Rect2(0, 0, 207, 117), grid)
		p.custom_minimum_size = Vector2(207, 117)
		var select := _button("", Rect2(0, 0, 207, 117), _select_hero.bind(id), p)
		select.add_theme_stylebox_override("normal", SiegeStyle.box(Color.TRANSPARENT, 16, SiegeStyle.GOLD if id == selected_actor else Color.TRANSPARENT))
		select.add_theme_stylebox_override("hover", SiegeStyle.box(Color(1, 0.9, 0.6, 0.09), 16, SiegeStyle.GOLD))
		select.add_theme_stylebox_override("pressed", SiegeStyle.box(Color(0.2, 0.5, 0.5, 0.1), 16, SiegeStyle.TEAL))
	var panel := _panel(Rect2(712, 98, 542, 535))
	var unit := Catalog.unit(selected_actor)
	var calc := UnitStats.calculate(unit, ProfileStore.level(selected_actor))
	_label(str(unit.get("name", selected_actor)), Rect2(24, 16, 488, 48), 35, SiegeStyle.INK, panel)
	var desc := _label(str(unit.get("description", unit.get("summary", "守住微光，与同伴并肩而行。"))), Rect2(24, 73, 488, 58), 19, SiegeStyle.MUTED, panel)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stats: Dictionary = calc.get("stats", {})
	for i in 3:
		var key: String = ["strength", "agility", "intelligence"][i]
		var main: bool = key == str(unit.get("primary_attribute", "strength"))
		var stat_panel := _panel(Rect2(24 + i * 165, 144, 151, 79), Color("e5e4d6") if not main else Color("ebdbb5"), panel)
		_label(_attribute_name(key) + (" · 主" if main else ""), Rect2(10, 8, 138, 25), 17, SiegeStyle.INK, stat_panel)
		_label("%.0f" % float(stats.get(key, 0)), Rect2(10, 37, 138, 32), 25, SiegeStyle.TEAL, stat_panel)
		var growth: Dictionary = unit.get("attribute_growth", {})
		_label("+%.0f / Lv" % float(growth.get(key, 2 if main else 1)), Rect2(66, 45, 79, 25), 13, SiegeStyle.MUTED, stat_panel)
	_label("生命  %d       伤害  %d" % [int(calc.get("hp", unit.get("hp", 0))), int(calc.get("damage", unit.get("damage", 0)))], Rect2(24, 247, 488, 31), 20, SiegeStyle.INK, panel)
	_label("间隔  %.2fs    射程  %d" % [float(calc.get("attack_interval", 1)), int(unit.get("range", 0))], Rect2(24, 287, 488, 31), 20, SiegeStyle.INK, panel)
	_label("召唤  %d能量    冷却  %.1fs" % [int(unit.get("cost", 0)), float(unit.get("cooldown", 0))], Rect2(24, 327, 488, 31), 20, SiegeStyle.INK, panel)
	var rules := _label(str(unit.get("skill_name", "战斗职责")) + " · " + str(unit.get("skill_description", "力量稳住前线，敏捷加快出手，智力提高魔抗与技能效果。主属性额外提高伤害。")), Rect2(24, 372, 488, 65), 16, SiegeStyle.MUTED, panel)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var level: int = ProfileStore.level(selected_actor)
	var b := _button("通关 %s 后契约" % Catalog.unlock_stage(selected_actor) if not ProfileStore.owns(selected_actor) else "已满级" if level >= 20 else "训练至 Lv.%d  ·  %d星砂" % [level + 1, ProfileStore.training_cost(selected_actor)], Rect2(24, 454, 488, 51), _train.bind(selected_actor), panel, true)
	b.disabled = not ProfileStore.can_modify() or not ProfileStore.owns(selected_actor) or level >= 20 or ProfileStore.credits() < ProfileStore.training_cost(selected_actor)

func _attribute_name(key: String) -> String:
	return {"strength": "力量", "agility": "敏捷", "intelligence": "智力"}.get(key, "力量")

func _select_hero(id: String) -> void:
	selected_actor = id
	show_home("英魂")

func _train(id: String) -> void:
	var success: bool = ProfileStore.upgrade(id)
	show_home("英魂")
	_message("训练完成，所有召唤实例都会继承成长。" if success else ProfileStore.error_message if not ProfileStore.error_message.is_empty() else "星砂不足或已满级。")

func _squad_page() -> void:
	draft_roster = ProfileStore.data.get("roster", Catalog.initial_roster()).duplicate()
	_label("前排承压、远程破阵、辅助续航。最多携带八名英魂。", Rect2(256, 88, 995, 38), 20, Color("c2d5cb"))
	var grid := _card_grid(Rect2(254, 145, 1000, 442), 4)
	for id: String in Catalog.playable_roster():
		var p := _hero_card(id, Rect2(0, 0, 234, 190), grid)
		p.custom_minimum_size = Vector2(234, 190)
		var desc := _label(str(Catalog.unit(id).get("description", Catalog.unit(id).get("summary", ""))), Rect2(16, 111, 202, 28), 14, SiegeStyle.MUTED, p)
		desc.clip_text = true
		var owned: bool = ProfileStore.owns(id)
		var button := _button("%s 后契约" % Catalog.unlock_stage(id) if not owned else "已出战 · 移出" if draft_roster.has(id) else "加入编队", Rect2(16, 148, 202, 30), _toggle_roster.bind(id), p, draft_roster.has(id))
		button.disabled = not ProfileStore.can_modify() or not owned or (not draft_roster.has(id) and draft_roster.size() >= 8)
	_label("当前 %d / 8 名英魂。点击即保存，至少保留一名。" % draft_roster.size(), Rect2(263, 610, 970, 39), 20, Color("c2d5cb"))

func _toggle_roster(id: String) -> void:
	var candidate := draft_roster.duplicate()
	if candidate.has(id): candidate.erase(id)
	else: candidate.append(id)
	var success: bool = ProfileStore.set_roster(candidate)
	show_home("编队")
	_message("编队已保存。" if success else ProfileStore.error_message if not ProfileStore.error_message.is_empty() else "编队需包含一至八名已契约英魂。")

func _gallery_page() -> void:
	var visuals := Catalog.visuals()
	var ids := visuals.keys()
	ids.sort()
	if ids.is_empty():
		_label("素材正在接入。", Rect2(280, 150, 930, 80), 25, Color("f1e4c6"))
		return
	var picker := OptionButton.new()
	picker.position = Vector2(272, 106)
	picker.size = Vector2(364, 47)
	for id: String in ids:
		var name := id
		for unit: Dictionary in Catalog.units().values():
			if str(unit.get("visual_id", "")) == id: name = str(unit.get("name", id)); break
		picker.add_item(name + " / " + id)
	var current := ids.find(selected_visual)
	if current < 0: current = 0
	picker.select(current)
	screen.add_child(picker)
	picker.item_selected.connect(func(index: int): selected_visual = str(ids[index]); show_home("图鉴"))
	selected_visual = str(ids[current])
	_label("英魂与裂隙生物", Rect2(695, 108, 520, 43), 24, Color("f1e4c6"))
	var actor_script: Script = load("res://scripts/visuals/SpineActor.gd")
	if actor_script != null:
		viewer = actor_script.new()
		viewer.position = Vector2(757, 505)
		screen.add_child(viewer)
		viewer.configure(selected_visual, 1)
		viewer.scale = Vector2(2.1, 2.1)
		viewer.play_state("idle")
	var states := ["idle", "move", "attack", "skill", "hurt", "death"]
	var labels := ["待机", "行走", "攻击", "技能", "受击", "死亡"]
	for i in states.size():
		_button(labels[i], Rect2(276 + (i % 2) * 146, 205 + int(i / 2) * 67, 130, 50), _preview_state.bind(states[i]))
	_button("朝左", Rect2(278, 444, 128, 45), _preview_facing.bind(-1))
	_button("朝右", Rect2(424, 444, 128, 45), _preview_facing.bind(1))
	_label("每个角色的姿态，是战场上可读的语言。", Rect2(691, 594, 545, 41), 18, Color("c1d0c7"))

func _preview_state(state: String) -> void:
	if is_instance_valid(viewer): viewer.play_state(state, 2.0)

func _preview_facing(facing: int) -> void:
	if is_instance_valid(viewer): viewer.configure(selected_visual, facing); viewer.play_state("idle")

func start_stage(id: String) -> void:
	if not ProfileStore.can_modify():
		_message(ProfileStore.error_message)
		return
	if not ProfileStore.stage_unlocked(id):
		_message("先点亮前一关，再继续这段航路。")
		return
	if not _stop_battle(): return
	_clear_screen()
	active_stage = id
	world.battle_mode = true
	var stage := Catalog.stage(id)
	world.configure_width(float(stage.get("world_width", 2560)), int(stage.get("chapter", 1)))
	view_max = world.world_width - 1280
	follow_frontline = true
	_set_view_position(0)
	draft_roster = ProfileStore.data.get("roster", Catalog.initial_roster()).duplicate()
	run_token = ProfileStore.begin_run(id)
	if run_token.is_empty():
		show_home()
		_message("暂时不能进入这段航路。")
		return
	paused = false
	speed = 1.0
	var script: Script = load("res://scripts/combat/SiegeBattle.gd")
	if script == null:
		show_home()
		_message("战斗正在接入。")
		return
	battle = script.new()
	battle.auto_step = false
	world_host.add_child(battle)
	battle.battle_finished.connect(_battle_finished)
	if battle.has_signal("combat_event"): battle.combat_event.connect(_combat_event)
	battle.start(id, draft_roster, ProfileStore.data.get("levels", {}))
	_build_battle_hud()
	status_label.text = str(stage.get("hint", "持续补线，守住微光。"))

func _health_bar(rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", SiegeStyle.box(Color("162d38"), 7))
	bar.add_theme_stylebox_override("fill", SiegeStyle.box(color, 7))
	screen.add_child(bar)
	return bar

func _build_battle_hud() -> void:
	_panel(Rect2(16, 16, 1248, 86), Color("172f3e"))
	player_label = _label("", Rect2(35, 26, 240, 28), 17, Color("d5e4d3"))
	player_hp = _health_bar(Rect2(35, 65, 247, 12), Color("64b8a0"))
	enemy_label = _label("", Rect2(995, 26, 246, 28), 17, Color("decae7"))
	enemy_hp = _health_bar(Rect2(995, 65, 245, 12), Color("b689c1"))
	_label(str(Catalog.stage(active_stage).get("name", "裂隙远征")), Rect2(333, 24, 380, 32), 24, Color("f0ddb7"))
	timer_label = _label("", Rect2(337, 61, 317, 25), 16, Color("9fb7b8"))
	energy_label = _label("", Rect2(749, 35, 237, 36), 24, Color("f3cf82"))
	_button("营地", Rect2(17, 119, 91, 39), show_home.bind("远征"))
	pause_button = _button("暂停", Rect2(119, 119, 91, 39), _toggle_pause)
	speed_button = _button("1×", Rect2(221, 119, 79, 39), _toggle_speed)
	follow_button = _button("跟随中", Rect2(311, 119, 113, 39), _resume_follow)
	status_label = _label("", Rect2(439, 117, 555, 43), 16, Color("d8dfc8"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pulse_button = _button("星灯脉冲 [P] · 80", Rect2(1009, 119, 246, 39), _pulse, null, true)
	view_slider = HSlider.new()
	view_slider.position = Vector2(244, 534)
	view_slider.size = Vector2(792, 15)
	view_slider.max_value = view_max
	view_slider.step = 1
	screen.add_child(view_slider)
	view_slider.value_changed.connect(_slide_view)
	_label("星灯", Rect2(33, 525, 130, 26), 14, Color("b6c8c2"))
	_label("← → / 拖动查看", Rect2(1055, 525, 190, 26), 14, Color("b6c8c2"))
	_panel(Rect2(16, 557, 1248, 148), Color("e9e3d4"))
	summon_buttons.clear()
	summon_labels.clear()
	var width := 149.0
	for i in draft_roster.size():
		var id: String = draft_roster[i]
		var unit := Catalog.unit(id)
		var b := _button("", Rect2(30 + i * 154, 571, width, 118), _summon.bind(id))
		b.add_theme_font_size_override("font_size", 17)
		b.tooltip_text = str(unit.get("description", unit.get("summary", "")))
		var name_label := _label("%d · %s" % [i + 1, str(unit.get("name", id))], Rect2(7, 8, 135, 30), 17, SiegeStyle.INK, b)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var role_label := _label(str(unit.get("role_name", unit.get("role", "英魂"))), Rect2(7, 38, 135, 22), 13, SiegeStyle.TEAL, b)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cost_label := _label("%d 能量" % int(unit.get("cost", 0)), Rect2(7, 61, 135, 24), 16, Color("9a712d"), b)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var ready_label := _label("召唤", Rect2(7, 88, 135, 23), 13, SiegeStyle.TEAL, b)
		ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summon_labels.append({"name": name_label, "role": role_label, "cost": cost_label, "ready": ready_label})
		summon_buttons.append(b)
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(battle) or not is_instance_valid(energy_label): return
	var snap: Dictionary = battle.get_snapshot()
	energy_label.text = "能量  %d / %d" % [int(snap.get("energy", 0)), int(snap.get("capacity", 400))]
	player_hp.max_value = float(snap.get("player_max_hp", 1))
	player_hp.value = float(snap.get("player_hp", 0))
	enemy_hp.max_value = float(snap.get("enemy_max_hp", 1))
	enemy_hp.value = float(snap.get("enemy_hp", 0))
	player_label.text = "星灯  %d / %d" % [int(player_hp.value), int(player_hp.max_value)]
	enemy_label.text = "裂隙  %d / %d" % [int(enemy_hp.value), int(enemy_hp.max_value)]
	var elapsed := int(snap.get("elapsed", 0))
	timer_label.text = "%02d:%02d    在场 %d / 64" % [int(elapsed / 60), elapsed % 60, int(snap.get("active_count", 0))]
	var cooldowns: Dictionary = snap.get("cooldowns", {})
	var pulse_remaining := float(snap.get("pulse_cooldown", 0))
	pulse_button.text = "星灯脉冲 · %.1fs" % pulse_remaining if pulse_remaining > 0.05 else "星灯脉冲 [P] · 80"
	pulse_button.disabled = paused or pulse_remaining > 0.05 or float(snap.get("energy", 0)) < float(snap.get("pulse_cost", 80)) or str(snap.get("outcome", "running")) != "running"
	for i in summon_buttons.size():
		var id: String = draft_roster[i]
		var unit := Catalog.unit(id)
		var remaining := float(cooldowns.get(id, 0))
		var cost := int(unit.get("cost", 0))
		var b := summon_buttons[i]
		b.disabled = paused or remaining > 0.05 or float(snap.get("energy", 0)) < cost or str(snap.get("outcome", "running")) != "running" or int(snap.get("active_count", 0)) >= 64
		var ready: Label = summon_labels[i].ready
		ready.text = "%.1fs" % remaining if remaining > 0.05 else "暂停中" if paused else "能量不足" if float(snap.get("energy", 0)) < cost else "已满" if int(snap.get("active_count", 0)) >= 64 else "召唤"
		ready.add_theme_color_override("font_color", SiegeStyle.MUTED if b.disabled else SiegeStyle.TEAL)

func _summon(id: String) -> void:
	if not is_instance_valid(battle) or paused: return
	if not battle.try_summon(id):
		_message("能量不足、尚在冷却或战场已满。")
	_update_hud()

func _pulse() -> void:
	if not is_instance_valid(battle) or paused: return
	if not battle.try_pulse(): _message("需要80能量、冷却完成，并有可命中的敌军。")
	_update_hud()

func _toggle_pause() -> void:
	if not is_instance_valid(battle) or is_instance_valid(result_panel): return
	paused = not paused
	if battle.has_method("set_visual_playback"): battle.set_visual_playback(0.0 if paused else speed)
	pause_button.text = "继续" if paused else "暂停"
	status_label.text = "已暂停 · 整理思路，然后继续。" if paused else "守住前排，让远程英魂持续输出。"

func _toggle_speed() -> void:
	if not is_instance_valid(battle): return
	speed = 2.0 if speed == 1 else 1.0
	if battle.has_method("set_visual_playback"): battle.set_visual_playback(0.0 if paused else speed)
	speed_button.text = "%d×" % int(speed)

func _combat_event(kind: String, position_at: Vector2, amount: float, team: int) -> void:
	if not is_instance_valid(screen): return
	if kind == "hit" or kind == "heal" or kind == "base_hit":
		var l := _label(("+" if kind == "heal" else "") + str(int(amount)), Rect2(position_at.x - 35, position_at.y - 87, 100, 30), 18, Color("94e7b0") if kind == "heal" else Color("ffdfa5"), world_host)
		l.z_index = 60
		motes.append({"node": l, "life": 1.0})
	elif kind == "pulse":
		world.add_pulse(position_at)
		status_label.text = "星灯脉冲！打断前线敌军，争取补线时间。"
	elif kind == "stun":
		var l := _label("打断", Rect2(position_at.x - 35, position_at.y - 55, 100, 30), 17, Color("8cf6d8"), world_host)
		l.z_index = 60
		motes.append({"node": l, "life": 1.0})
	elif kind == "phase":
		status_label.text = "裂隙狂潮！坚守阵线，寻找反攻窗口。"
	elif kind == "attack" and team == -1 and amount >= 0.7:
		status_label.text = "重击预警！补上前排，保护远程。"

func _battle_finished(victory: bool) -> void:
	if is_instance_valid(result_panel): return
	paused = true
	if battle.has_method("set_visual_playback"): battle.set_visual_playback(0.0)
	var saved := false
	if victory: saved = ProfileStore.win(run_token)
	else: ProfileStore.abandon(run_token); run_token = ""
	var shade := ColorRect.new()
	shade.position = Vector2.ZERO
	shade.size = Vector2(1280, 720)
	shade.color = Color(0.03, 0.09, 0.13, 0.72)
	screen.add_child(shade)
	result_panel = _panel(Rect2(397, 176, 486, 364))
	_label("星灯重燃" if victory else "微光尚未熄灭", Rect2(25, 20, 436, 58), 35, SiegeStyle.TEAL if victory else SiegeStyle.INK, result_panel)
	var stage := Catalog.stage(active_stage)
	var reward: Variant = stage.get("rewards", 80)
	var earned := int(reward.get("credits", 80)) if reward is Dictionary else int(reward)
	var text := "保存失败，请重试领取。" if victory else "尝试低费前排持续补线，再搭配范围输出或治疗。"
	if victory and saved:
		run_token = ""
		var award: Dictionary = ProfileStore.last_award
		earned = int(award.get("credits", earned))
		text = "获得 %d 星砂" % earned
		if bool(award.get("first_clear", false)): text += "（首通额外 %d）" % int(award.get("bonus_credits", 0))
		var names: Array[String] = []
		for id: String in award.get("unlock_units", []): names.append(str(Catalog.unit(id).get("name", id)))
		text += "\n新契约 · " + "、".join(names) if not names.is_empty() else "\n可以训练英魂，继续远征。"
	var desc := _label(text, Rect2(25, 83, 436, 91), 19, SiegeStyle.MUTED, result_panel)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if victory and not saved:
		_button("重试保存奖励", Rect2(25, 185, 436, 46), _retry_reward, result_panel, true)
	else:
		var stages := Catalog.stages()
		var next_id := ""
		for i in stages.size():
			if str(stages[i].id) == active_stage and i + 1 < stages.size(): next_id = str(stages[i + 1].id)
		_button("继续远征" if victory and not next_id.is_empty() else "再战一次", Rect2(25, 185, 436, 46), start_stage.bind(next_id if victory and not next_id.is_empty() else active_stage), result_panel, true)
	_button("返回营地 · 整备英魂", Rect2(25, 247, 436, 46), show_home.bind("英魂" if not victory else "远征"), result_panel)
	var ending := _label(str(stage.get("story_outro", "每一次尝试，都让微光更近一步。")) if victory and saved else "每一次尝试，都让微光更近一步。", Rect2(25, 304, 436, 49), 14, SiegeStyle.MUTED, result_panel)
	ending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _retry_reward() -> void:
	if ProfileStore.win(run_token):
		run_token = ""
		show_home()
		_message("奖励已保存。")
	else: _message(ProfileStore.error_message)
