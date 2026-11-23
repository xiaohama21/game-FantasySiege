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
var selected_briefing := ""
var gallery_kind := "heroes"
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
var result_shade: ColorRect
var result_report: Dictionary = {}
var result_award: Dictionary = {}
var result_saved := false
var result_victory := false
var settings_panel
var guide_panel
var settings_was_paused := false
var guide_was_paused := false
var hud_elapsed := 0.0
var mote_cursor := 0
var intro_panel: Panel
var intro_time := 0.0
var exit_panel: Control
var exit_was_paused := false
var focus_locks: Array[Dictionary] = []
var quitting := false
var viewer
var toast: Label
var toast_time := 0.0
var motes: Array = []
var card_list_positions: Dictionary = {}
var active_card_scroll: ScrollContainer
var card_list_generation := 0
var pending_card_focus: Dictionary = {}

func _ready() -> void:
	get_tree().auto_accept_quit = false
	theme = SiegeStyle.make_theme()
	world_host = Node2D.new()
	add_child(world_host)
	world = WorldBackdrop.new()
	world_host.add_child(world)
	show_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _request_quit()

func _request_quit(force: bool = false) -> void:
	if quitting: return
	var preferences_saved: bool = not UserPrefs.dirty or UserPrefs.flush()
	var pending_reward: bool = is_instance_valid(battle) and not run_token.is_empty() and str(battle.get_snapshot().get("outcome", "")) == "victory"
	if not force and (pending_reward or not preferences_saved):
		if is_instance_valid(exit_panel): return
		if is_instance_valid(toast): toast.visible = false
		toast_time = 0.0
		var previous_focus: Control = get_viewport().gui_get_focus_owner()
		exit_was_paused = paused
		if is_instance_valid(battle):
			paused = true
			battle.set_visual_playback(0.0)
		exit_panel = Control.new()
		exit_panel.z_index = 700
		exit_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.add_child(exit_panel)
		var shade := ColorRect.new()
		shade.size = Vector2(1280, 720)
		shade.color = Color(0.025, 0.065, 0.1, 0.86)
		exit_panel.add_child(shade)
		var panel := _panel(Rect2(367, 200, 546, 320), SiegeStyle.PAPER, exit_panel)
		_label("奖励尚未保存" if pending_reward else "设置尚未保存", Rect2(24, 18, 500, 45), 28, SiegeStyle.TEAL, panel)
		var explanation := "退出会丢失本次未领取的奖励。" if pending_reward else ""
		if not preferences_saved: explanation += "当前设置保存失败：" + UserPrefs.error_message + "\n"
		explanation += "可以先重试，也可以明确放弃未保存内容后退出。按Esc返回继续使用。"
		var warning := _label(explanation, Rect2(24, 80, 500, 104), 17, SiegeStyle.INK, panel)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var retry := _button("重试领取与保存" if pending_reward and not preferences_saved else "重试领取" if pending_reward else "重试保存", Rect2(24, 198, 498, 41), _retry_exit_save, panel, true)
		_button("仍然退出 · 放弃未保存内容", Rect2(24, 252, 498, 39), _request_quit.bind(true), panel)
		_lock_modal_focus(exit_panel, previous_focus, retry)
		return
	quitting = true
	if is_instance_valid(battle):
		paused = true
		battle.set_visual_playback(0.0)
	await GameAudio.shutdown()
	get_tree().quit()

func _dismiss_exit() -> void:
	if is_instance_valid(exit_panel):
		_unlock_modal_focus(exit_panel)
		exit_panel.queue_free()
	exit_panel = null
	if is_instance_valid(battle) and not is_instance_valid(result_panel) and not is_instance_valid(settings_panel) and not is_instance_valid(guide_panel):
		paused = exit_was_paused
		battle.set_visual_playback(0.0 if paused else speed)
		_update_hud()

func _retry_exit_save() -> void:
	_dismiss_exit()
	if not run_token.is_empty() and is_instance_valid(result_panel): _retry_reward()
	if UserPrefs.dirty and not UserPrefs.flush(): _message(UserPrefs.error_message)

func _active_modal() -> Control:
	for layer in [exit_panel, settings_panel, guide_panel, result_panel]:
		if is_instance_valid(layer): return layer
	return null

func _button_action_allowed(source: Control) -> bool:
	if quitting: return false
	var modal := _active_modal()
	return not is_instance_valid(modal) or modal == source or modal.is_ancestor_of(source)

func _lock_modal_focus(modal: Control, previous_focus: Control, preferred: Control = null) -> void:
	var entries: Array[Dictionary] = []
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if control == modal or modal.is_ancestor_of(control): continue
		if control.focus_mode != Control.FOCUS_NONE:
			entries.append({"node": control, "mode": control.focus_mode})
			control.focus_mode = Control.FOCUS_NONE
	focus_locks.append({"modal": modal, "entries": entries, "previous": previous_focus})
	if is_instance_valid(preferred): preferred.grab_focus()

func _unlock_modal_focus(modal: Control) -> void:
	if focus_locks.is_empty() or focus_locks.back().modal != modal: return
	var lock: Dictionary = focus_locks.pop_back()
	for entry: Dictionary in lock.entries:
		if is_instance_valid(entry.node): entry.node.focus_mode = entry.mode
	if is_instance_valid(lock.previous) and not lock.previous.is_queued_for_deletion(): lock.previous.grab_focus()

func _process(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		if is_instance_valid(toast): toast.visible = toast_time > 0
	if is_instance_valid(battle):
		if intro_time > 0 and not paused:
			intro_time -= delta
			if is_instance_valid(intro_panel): intro_panel.visible = intro_time > 0
		if not paused: battle.advance(delta * speed)
		_update_camera(delta)
		hud_elapsed += delta
		if hud_elapsed >= 0.1:
			hud_elapsed = 0
			_update_hud()
	for mote: Dictionary in motes:
		if float(mote.life) <= 0: continue
		mote.life -= delta
		if is_instance_valid(mote.node):
			mote.node.position.y -= delta * 30
			mote.node.modulate.a = clampf(mote.life, 0, 1)
		if mote.life <= 0:
			if is_instance_valid(mote.node): mote.node.visible = false

func _input(event: InputEvent) -> void:
	if not is_instance_valid(battle): return
	if is_instance_valid(_active_modal()):
		dragging = false
		return
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
	if is_instance_valid(_active_modal()): return
	if not is_instance_valid(result_panel):
		var movement := float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		var mouse := get_local_mouse_position()
		if bool(UserPrefs.get_value("edge_scroll", true)) and not dragging and mouse.y >= 164 and mouse.y < 526:
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
	if is_instance_valid(exit_panel):
		if event.keycode == KEY_ESCAPE: _dismiss_exit()
		return
	if event.keycode == KEY_F11:
		var changed: bool = UserPrefs.set_value("fullscreen", not bool(UserPrefs.get_value("fullscreen", false)))
		if not changed or not UserPrefs.flush(): _message(UserPrefs.error_message)
		return
	if is_instance_valid(settings_panel):
		if event.keycode == KEY_ESCAPE: settings_panel.close()
		return
	if is_instance_valid(guide_panel):
		if event.keycode == KEY_ESCAPE: guide_panel.close()
		return
	if is_instance_valid(result_panel):
		if event.keycode == KEY_ESCAPE: show_home()
		return
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
	_remember_card_list_position()
	card_list_generation += 1
	active_card_scroll = null
	focus_locks.clear()
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
	result_shade = null
	result_report.clear()
	result_award.clear()
	result_saved = false
	result_victory = false
	settings_panel = null
	guide_panel = null
	intro_panel = null
	exit_panel = null
	for mote: Dictionary in motes:
		if is_instance_valid(mote.node): mote.node.queue_free()
	motes.clear()
	mote_cursor = 0

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
	if font_size >= 24:
		l.add_theme_font_override("font", SiegeStyle.emphasis_font())
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
		b.add_theme_stylebox_override("normal", SiegeStyle.button_box(SiegeStyle.TEAL, 10))
		b.add_theme_stylebox_override("hover", SiegeStyle.button_box(SiegeStyle.TEAL.lightened(0.08), 10, SiegeStyle.GOLD))
		b.add_theme_stylebox_override("pressed", SiegeStyle.button_box(SiegeStyle.TEAL.darkened(0.12), 10))
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(color_name, Color("fffaed"))
	b.pressed.connect(func():
		if not _button_action_allowed(b): return
		GameAudio.play_cue("click")
		action.call())
	(parent if parent != null else screen).add_child(b)
	return b

func _message(value: String) -> void:
	if not is_instance_valid(toast):
		toast = _label("", Rect2(254, 646, 386, 56), 16, Color("ffe3a3"))
		toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		toast.add_theme_stylebox_override("normal", SiegeStyle.box(Color(0.06, 0.15, 0.2, 0.96), 10))
	if is_instance_valid(result_panel):
		toast.position = Vector2(224, 653)
		toast.size = Vector2(832, 45)
	elif is_instance_valid(battle):
		toast.position = Vector2(330, 174)
		toast.size = Vector2(620, 68)
	elif tab in ["敌情", "研修"]:
		toast.position = Vector2(254, 678)
		toast.size = Vector2(1000, 40)
		toast.add_theme_font_size_override("font_size", 14)
	toast.text = value
	toast.visible = true
	toast.z_index = 800
	toast_time = 5

func _open_settings() -> void:
	if is_instance_valid(settings_panel) or is_instance_valid(guide_panel): return
	var previous_focus: Control = get_viewport().gui_get_focus_owner()
	settings_was_paused = paused
	if is_instance_valid(battle):
		paused = true
		battle.set_visual_playback(0.0)
	var script: Script = load("res://scripts/ui/SettingsPanel.gd")
	settings_panel = script.new()
	settings_panel.input_allowed = func() -> bool: return _active_modal() == settings_panel and not quitting
	settings_panel.configure(UserPrefs, GameAudio)
	screen.add_child(settings_panel)
	settings_panel.closed.connect(_close_settings)
	_lock_modal_focus(settings_panel, previous_focus, settings_panel.volume_sliders.master_volume)
	dragging = false
	_update_hud()

func _close_settings() -> void:
	if is_instance_valid(settings_panel): _unlock_modal_focus(settings_panel)
	settings_panel = null
	if is_instance_valid(battle) and not is_instance_valid(result_panel):
		paused = settings_was_paused
		battle.set_visual_playback(0.0 if paused else speed)
		pause_button.text = "继续" if paused else "暂停"
	_update_hud()

func _open_guide() -> void:
	if is_instance_valid(exit_panel) or is_instance_valid(guide_panel) or is_instance_valid(settings_panel) or quitting: return
	var previous_focus: Control = get_viewport().gui_get_focus_owner()
	guide_was_paused = paused
	if is_instance_valid(battle):
		paused = true
		battle.set_visual_playback(0.0)
	var script: Script = load("res://scripts/ui/GuidePanel.gd")
	guide_panel = script.new()
	guide_panel.input_allowed = func() -> bool: return _active_modal() == guide_panel and not quitting
	guide_panel.starting = is_instance_valid(battle)
	guide_panel.story = str(Catalog.stage(active_stage).get("story_intro", "循光而行，重燃诸岛。"))
	screen.add_child(guide_panel)
	guide_panel.closed.connect(_close_guide)
	_lock_modal_focus(guide_panel, previous_focus, guide_panel.next)
	dragging = false
	_update_hud()

func _close_guide() -> void:
	if is_instance_valid(guide_panel): _unlock_modal_focus(guide_panel)
	guide_panel = null
	UserPrefs.set_value("tutorial_seen", true)
	if not UserPrefs.flush(): _message(UserPrefs.error_message)
	if is_instance_valid(battle) and not is_instance_valid(result_panel):
		paused = guide_was_paused
		battle.set_visual_playback(0.0 if paused else speed)
		pause_button.text = "继续" if paused else "暂停"
	_update_hud()

func show_home(next_tab: String = "远征") -> void:
	if not _stop_battle(): return
	_clear_screen()
	tab = next_tab
	world.battle_mode = false
	world.configure_width(1280, 1)
	GameAudio.set_context("camp")
	var sidebar := _panel(Rect2(20, 20, 200, 680), Color("162e3b"))
	_label("FANTASY SIEGE", Rect2(16, 20, 175, 25), 14, Color("a3c6bd"), sidebar)
	_label("星灯远征", Rect2(16, 48, 180, 45), 32, Color("f5deb1"), sidebar)
	_label("循光而行 · 重燃诸岛", Rect2(16, 101, 175, 35), 15, Color("9bb4b3"), sidebar)
	var tabs := ["远征", "英魂", "研修", "编队", "图鉴"]
	for i in tabs.size():
		var title: String = tabs[i]
		_button(title, Rect2(16, 155 + i * 59, 168, 47), show_home.bind(title), sidebar, title == tab)
	_button("设置", Rect2(16, 469, 168, 45), _open_settings, sidebar)
	_button("操作指南", Rect2(16, 526, 168, 45), _open_guide, sidebar)
	_label("本地学习版\nv" + str(ProjectSettings.get_setting("application/config/version")), Rect2(18, 603, 172, 55), 14, Color("8ba6a7"), sidebar)
	_label(tab, Rect2(254, 27, 680, 45), 32, Color("f1e4c6"))
	_panel(Rect2(1053, 27, 201, 45), Color("223f4b"))
	_label("星砂  %d" % ProfileStore.credits(), Rect2(1070, 33, 180, 32), 20, Color("f4d28a"))
	if tab == "远征": _campaign_page()
	elif tab == "英魂": _heroes_page()
	elif tab == "研修": _study_page()
	elif tab == "编队": _squad_page()
	elif tab == "敌情": _briefing_page()
	else: _gallery_page()
	if not ProfileStore.error_message.is_empty(): _message(ProfileStore.error_message)

func _select_chapter(value: int) -> void:
	selected_chapter = value
	show_home("远征")

func _campaign_page() -> void:
	var cleared: Array = ProfileStore.data.get("cleared", [])
	var hero := _panel(Rect2(254, 93, 1000, 125), Color("224957"))
	hero.clip_contents = true
	var route_art := TextureRect.new()
	route_art.texture = world._texture("camp-route.svg")
	route_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	route_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	route_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_art.modulate = Color(1, 1, 1, 0.32)
	route_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero.add_child(route_art)
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
		var inspect := _button("敌情", Rect2(16, 311, 76, 38), _open_briefing.bind(str(stage.id)), p)
		inspect.name = "Briefing_" + str(stage.id)
		var button := _button("重访" if complete else "出征" if unlocked else "未解锁", Rect2(101, 311, 120, 38), start_stage.bind(str(stage.id)), p, unlocked)
		button.disabled = not unlocked or not ProfileStore.can_modify()
	_label("1—8 召唤  ·  P 脉冲  ·  空格 暂停  ·  ← → / 鼠标拖动查看战场", Rect2(261, 618, 973, 30), 17, Color("b6c8c2"))

func _open_briefing(id: String) -> void:
	var stage := Catalog.stage(id)
	if stage.is_empty():
		show_home("远征")
		_message("未找到该关卡的敌情。")
		return
	selected_briefing = id
	selected_chapter = int(stage.get("chapter", 1))
	show_home("敌情")

func _briefing_scroll(rect: Rect2, node_name: String, parent: Node = null) -> VBoxContainer:
	var panel := _panel(rect, SiegeStyle.PAPER, parent)
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.position = Vector2(12, 10)
	scroll.size = rect.size - Vector2(24, 20)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	return content

func _briefing_line(value: String, parent: Node, font_size: int = 16, color: Color = SiegeStyle.INK) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _briefing_names(ids: Array) -> String:
	var names: Array[String] = []
	for id: Variant in ids: names.append(str(Catalog.unit(str(id)).get("name", id)))
	return "、".join(names)

func _icon(id: String, rect: Rect2, parent: Node) -> TextureRect:
	var art := TextureRect.new()
	art.name = "Icon_" + id
	art.position = rect.position
	art.size = rect.size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = load("res://assets/ui/icons/" + id + ".svg")
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art

func _term(parent: Node, text: String, tint: Color = SiegeStyle.TEAL, icon_id: String = "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := SiegeStyle.box(SiegeStyle.PAPER.lerp(tint, 0.13), 7, tint.lightened(0.25))
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", style)
	parent.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	if not icon_id.is_empty():
		var art := TextureRect.new()
		art.texture = load("res://assets/ui/icons/" + icon_id + ".svg")
		art.custom_minimum_size = Vector2(18, 18)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
	var label := _briefing_line(text, row, 14, tint.darkened(0.16))
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return chip

func _briefing_card(parent: Node, tint: Color = SiegeStyle.TEAL) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := SiegeStyle.box(Color("faf6eb"), 12, tint.lightened(0.28))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(box)
	return box

func _stat_badge(parent: Node, key: String, icon_id: String, caption: String, value: String, tint: Color = SiegeStyle.TEAL) -> Control:
	var badge: Control = load("res://scripts/ui/StatBadge.gd").new()
	badge.name = "Stat_" + key
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(badge)
	badge.call("configure", icon_id, caption, value, tint)
	return badge

func _briefing_stat_grid(parent: Node, calc: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	_stat_badge(grid, "hp", "heart", "生命", "%.0f" % float(calc.hp))
	var kind: String = {"physical": "物理", "magic": "魔法", "true": "真实"}.get(str(calc.damage_type), "物理")
	_stat_badge(grid, "damage", "orb" if calc.damage_type == "magic" else "sword", kind + "伤害", "%.0f" % float(calc.damage), Color("b46f45"))
	_stat_badge(grid, "armor", "shield", "护甲", "%.0f" % float(calc.armor))
	_stat_badge(grid, "magic_armor", "ward", "魔抗", "%.0f" % float(calc.magic_armor), Color("80679b"))
	_stat_badge(grid, "range", "range", "射程", "%.0f" % float(calc.range))
	_stat_badge(grid, "hit_delay", "clock", "前摇", "%.2fs" % float(calc.hit_delay), Color("9a712d"))

func _capability_icon(id: String) -> String:
	return {"frontline": "shield", "low_cost": "energy", "aoe": "group", "magic": "orb", "true_damage": "sword", "healing": "heal", "slow": "slow", "siege": "siege"}.get(id, "star")

func _briefing_page() -> void:
	var summary := BattleBriefing.summarize(selected_briefing)
	if summary.is_empty(): return
	var stage: Dictionary = summary.stage
	var terms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/briefings.json"))
	var header := _panel(Rect2(254, 93, 1000, 112), Color("224957"))
	_label(str(stage.get("name", "远征")) + " · 战前准备", Rect2(20, 9, 730, 37), 28, Color("f4e8cb"), header)
	_icon("group", Rect2(816, 14, 26, 26), header)
	_label("%d 名敌军" % int(summary.total_count), Rect2(850, 10, 135, 32), 22, Color("f4cf88"), header)
	_icon("heart", Rect2(20, 49, 21, 21), header)
	_label("星灯 %.0f  /  敌垒 %.0f    ·    建议 Lv.%d" % [float(stage.get("player_base_hp", 0)), float(stage.get("enemy_base_hp", 0)), int(stage.get("recommended_level", 1))], Rect2(48, 47, 914, 25), 17, Color("d8e6dc"), header)
	_icon("energy", Rect2(20, 80, 21, 21), header)
	_label("开局 %.0f  ·  回复 %.0f / 秒  ·  能量上限 %.0f" % [float(stage.get("initial_energy", 0)), float(stage.get("income", 0)), float(stage.get("capacity", 0))], Rect2(48, 78, 914, 25), 17, Color("bdcfca"), header)
	_label("敌军档案", Rect2(258, 216, 610, 30), 21, Color("f1e4c6"))
	_label("队伍准备", Rect2(906, 216, 340, 30), 21, Color("f1e4c6"))
	var enemies := _briefing_scroll(Rect2(254, 252, 636, 360), "BriefingEnemies")
	_briefing_line("计划出场 · 非抵达时间；人数上限可延后入场。", enemies, 14, SiegeStyle.MUTED)
	for enemy: Dictionary in summary.enemies:
		var definition := Catalog.unit(str(enemy.id))
		var presentation: Dictionary = terms.get("enemies", {}).get(str(enemy.id), {})
		var special: Dictionary = enemy.variants[0].stats.special
		var boss: bool = special.has("phase_threshold")
		var card := _briefing_card(enemies, SiegeStyle.GOLD if boss else SiegeStyle.TEAL)
		var title_row := HBoxContainer.new()
		card.add_child(title_row)
		_briefing_line(str(enemy.name), title_row, 23, SiegeStyle.INK)
		_term(title_row, "%d名" % int(enemy.count), Color("9a712d"), "boss" if boss else "group")
		var tags := HBoxContainer.new()
		tags.add_theme_constant_override("separation", 6)
		card.add_child(tags)
		for tag: String in presentation.get("tags", [str(enemy.role)]):
			_term(tags, tag, Color("a57438") if boss else SiegeStyle.TEAL)
		_term(tags, "%.1f—%.1fs" % [float(enemy.first_time), float(enemy.last_time)], Color("697f86"), "clock")
		for variant: Dictionary in enemy.variants:
			var calc: Dictionary = variant.stats
			var variant_label := _briefing_line("%d名 · 本波数值" % int(variant.count) if enemy.variants.size() > 1 else "", card, 13, SiegeStyle.MUTED)
			variant_label.visible = enemy.variants.size() > 1
			variant_label.set_meta("briefing_enemy_id", str(enemy.id))
			variant_label.set_meta("unit_stats", calc.duplicate(true))
			variant_label.set_meta("wave_modifiers", {"hp_mult": variant.hp_mult, "damage_mult": variant.damage_mult})
			_briefing_stat_grid(card, calc)
		var area := HBoxContainer.new()
		card.add_child(area)
		_briefing_line(str(definition.get("skill_name", "战斗技能")), area, 14, SiegeStyle.MUTED)
		if float(enemy.variants[0].stats.aoe_radius) > 0:
			_term(area, "范围 %.0f" % float(enemy.variants[0].stats.aoe_radius), Color("80679b"), "group")
		if boss:
			var phase := _briefing_card(card, SiegeStyle.GOLD)
			_briefing_line("%.0f%%生命 → %s" % [float(special.phase_threshold) * 100, str(special.get("phase_name", "强化阶段"))], phase, 18, Color("9a712d"))
			_briefing_line("伤害×%.2f  ·  出手间隔×%.2f  ·  移速×%.2f" % [float(special.get("phase_damage_mult", 1)), float(special.get("phase_attack_mult", 1)), float(special.get("phase_speed_mult", 1))], phase, 14, SiegeStyle.INK)
		var counters := HBoxContainer.new()
		counters.add_theme_constant_override("separation", 6)
		card.add_child(counters)
		var counter_caption := _briefing_line("应对", counters, 14, SiegeStyle.MUTED)
		counter_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		counter_caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		counter_caption.custom_minimum_size.x = 30
		for counter: String in presentation.get("counters", [str(definition.get("counter_hint", "持续补线"))]):
			_term(counters, counter, Color("9a712d"), "pulse" if "P" in counter else "star")
	var preparation := BattleBriefing.readiness(selected_briefing, ProfileStore.data.get("roster", []), ProfileStore.data.get("levels", {}), ProfileStore.study_modifiers_snapshot(), ProfileStore.data.get("owned", []))
	var squad := _briefing_scroll(Rect2(906, 252, 348, 360), "BriefingPreparation")
	var members := _briefing_card(squad)
	_briefing_line("已保存编队  %d / 8" % preparation.members.size(), members, 19, SiegeStyle.TEAL)
	for member: Dictionary in preparation.members:
		var line := _briefing_line("%s · %d级" % [str(member.name), int(member.level)], members, 15)
		line.set_meta("briefing_member_id", str(member.id))
		line.set_meta("unit_stats", member.stats.duplicate(true))
		if ProfileStore.study_route(str(member.id)) != "base": _briefing_line(_study_name(str(member.id)), members, 13, SiegeStyle.TEAL)
	for recommendation: Dictionary in preparation.recommendations:
		var present: Array = recommendation.present
		var tint := SiegeStyle.TEAL if not present.is_empty() else Color("9a712d")
		var card := _briefing_card(squad, tint)
		var title_row := HBoxContainer.new()
		card.add_child(title_row)
		_term(title_row, str(recommendation.label), tint, _capability_icon(str(recommendation.capability)))
		_briefing_line("已配备" if not present.is_empty() else "可补充", card, 14, tint)
		if not present.is_empty(): _briefing_line(_briefing_names(present), card, 15)
		elif not recommendation.alternatives.is_empty(): _briefing_line("可选 · " + _briefing_names(recommendation.alternatives), card, 15)
		else: _briefing_line("暂无替补，可先训练现有队员。", card, 14)
		_briefing_line(str(recommendation.get("reason", "")), card, 14, SiegeStyle.MUTED)
	var pulse := _briefing_card(squad, SiegeStyle.GOLD)
	var pulse_title := HBoxContainer.new()
	pulse.add_child(pulse_title)
	_term(pulse_title, "星灯脉冲 [P]", Color("9a712d"), "pulse")
	_briefing_line("%.0f能量  ·  %.0f秒冷却" % [SiegeBattle.PULSE_COST, SiegeBattle.PULSE_COOLDOWN], pulse, 16, Color("9a712d"))
	_briefing_line("重击预警 → P打断
首领推退效果减弱", pulse, 15)
	_briefing_line("可选提醒 · 训练、补线与脉冲时机同样重要。", squad, 14, SiegeStyle.MUTED)
	var return_button := _button("返回远征", Rect2(254, 632, 180, 44), show_home.bind("远征"))
	return_button.name = "BriefingReturn"
	var squad_button := _button("调整编队", Rect2(450, 632, 180, 44), show_home.bind("编队"))
	squad_button.name = "BriefingSquad"
	var can_start: bool = ProfileStore.stage_unlocked(selected_briefing) and ProfileStore.can_modify()
	var start_button := _button("出征" if can_start else "只读浏览" if not ProfileStore.can_modify() else "先点亮前一关", Rect2(1046, 632, 208, 44), start_stage.bind(selected_briefing), null, can_start)
	start_button.name = "BriefingStart"
	start_button.disabled = not can_start

func _card_grid(rect: Rect2, columns: int) -> GridContainer:
	var page: String = tab
	var prefix: String = str({"英魂": "HeroList", "研修": "StudyList", "编队": "SquadList"}.get(page, "ActorList"))
	var scroll := ScrollContainer.new()
	scroll.name = prefix + "Scroll"
	scroll.position = rect.position
	scroll.size = rect.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_meta("list_page", page)
	scroll.set_meta("list_restore_ready", false)
	scroll.set_meta("list_selected_id", selected_actor if page in ["英魂", "研修"] else "")
	screen.add_child(scroll)
	active_card_scroll = scroll
	var grid := GridContainer.new()
	grid.name = prefix + "Grid"
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var state: Dictionary = card_list_positions.get(page, {})
	var restore_position: int = int(state.get("scroll_vertical", 0))
	var focus_id := ""
	if pending_card_focus.has(page) and str(pending_card_focus[page]) != selected_actor:
		pending_card_focus.erase(page)
	if page in ["英魂", "研修"] and (state.is_empty() or str(state.get("selected_id", "")) != selected_actor or str(pending_card_focus.get(page, "")) == selected_actor):
		focus_id = selected_actor
	# Keep a selection request until its layout task actually completes. A route,
	# unlock or training action may rebuild this same page synchronously first.
	_restore_card_list.call_deferred(weakref(scroll), weakref(grid), page, card_list_generation, restore_position, focus_id)
	return grid

func _remember_card_list_position() -> void:
	if not is_instance_valid(active_card_scroll) or not active_card_scroll.is_inside_tree(): return
	# A just-created list still has the temporary zero position. Keep its previous
	# state until the layout restoration completes, including during rapid navigation.
	if not bool(active_card_scroll.get_meta("list_restore_ready", false)): return
	var page: String = str(active_card_scroll.get_meta("list_page", ""))
	if page.is_empty(): return
	card_list_positions[page] = {"scroll_vertical": active_card_scroll.scroll_vertical, "selected_id": str(active_card_scroll.get_meta("list_selected_id", ""))}

func _card_list_restore_is_current(scroll_ref: WeakRef, generation: int) -> bool:
	if generation != card_list_generation: return false
	var instance: Variant = scroll_ref.get_ref()
	return instance is ScrollContainer and is_instance_valid(instance) and instance == active_card_scroll and instance.is_inside_tree()

func _restore_card_list(scroll_ref: WeakRef, grid_ref: WeakRef, page: String, generation: int, restore_position: int, focus_id: String) -> void:
	if not _card_list_restore_is_current(scroll_ref, generation): return
	# Containers need their minimum sizes before the scroll range and selected-card
	# rectangle are usable. Recheck ownership after each layout frame.
	await get_tree().process_frame
	if not _card_list_restore_is_current(scroll_ref, generation): return
	await get_tree().process_frame
	if not _card_list_restore_is_current(scroll_ref, generation): return
	var scroll := scroll_ref.get_ref() as ScrollContainer
	var grid := grid_ref.get_ref() as GridContainer
	if not is_instance_valid(grid) or grid.get_parent() != scroll or str(scroll.get_meta("list_page", "")) != page: return
	var scrollbar := scroll.get_v_scroll_bar()
	var limit: int = maxi(0, floori(scrollbar.max_value - scrollbar.page))
	var target: int = clampi(restore_position, 0, limit)
	if not focus_id.is_empty():
		for card: Node in grid.get_children():
			if card is Control and str(card.get_meta("list_unit_id", "")) == focus_id:
				# The grid's content coordinates are stable after layout. A global
				# rectangle can still reflect the previous scroll transform in this
				# frame, so calculate the target without first moving the grid.
				var top: float = card.position.y
				var bottom: float = top + card.size.y
				if top < float(target): target = floori(top)
				elif bottom > float(target) + scrollbar.page: target = ceili(bottom - scrollbar.page)
				break
	scroll.scroll_vertical = clampi(target, 0, limit)
	await get_tree().process_frame
	if not _card_list_restore_is_current(scroll_ref, generation): return
	scroll = scroll_ref.get_ref() as ScrollContainer
	scroll.set_meta("list_restore_ready", true)
	_remember_card_list_position()
	if str(pending_card_focus.get(page, "")) == focus_id:
		pending_card_focus.erase(page)

func _hero_card(id: String, rect: Rect2, parent: Node = null) -> Panel:
	var unit := Catalog.unit(id)
	var p := _panel(rect, SiegeStyle.PAPER, parent)
	p.name = "HeroCard_" + id
	p.set_meta("list_unit_id", id)
	p.set_meta("list_selected", tab in ["英魂", "研修"] and id == selected_actor)
	var name_label := _label(str(unit.get("name", id)), Rect2(12, 9, rect.size.x - 24, 32), 22, SiegeStyle.INK, p)
	_fit_name(name_label, 22)
	var image_width := 87.0 if rect.size.x >= 230 else 78.0
	_portrait(id, Rect2(10, 46, image_width, 98), p, id == selected_actor and tab in ["英魂", "研修"])
	var text_x := image_width + 19.0
	var text_width := rect.size.x - text_x - 9.0
	_label(str(unit.get("role_name", unit.get("role", "英魂"))), Rect2(text_x, 48, text_width, 26), 15, SiegeStyle.TEAL, p)
	_label("Lv.%d" % ProfileStore.level(id) if ProfileStore.owns(id) else "未契约", Rect2(text_x, 79, text_width, 24), 16, SiegeStyle.INK, p)
	var attr := str(unit.get("primary_attribute", "strength"))
	var identity := _study_name(id) if ProfileStore.study_unlocked(id) else "主 · " + _attribute_name(attr)
	var identity_label := _label(identity, Rect2(text_x, 110, text_width, 25), 14, Color("a67836"), p)
	_fit_name(identity_label, 14)
	return p

func _study_name(id: String) -> String:
	return str(Catalog.study_route(id, ProfileStore.study_route(id)).get("name", "基础路线"))

func _hero_calculation(id: String) -> Dictionary:
	return UnitStats.calculate(Catalog.unit(id), ProfileStore.level(id), Catalog.study_modifiers(id, ProfileStore.study_route(id)))

func _fit_name(label: Label, maximum: int, minimum: int = 12) -> void:
	var font := label.get_theme_font("font")
	var font_size := maximum
	while font_size > minimum and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)

func _portrait(id: String, rect: Rect2, parent: Node, highlighted: bool = false) -> Control:
	var script: Script = load("res://scripts/ui/PortraitFrame.gd")
	var art: Control = script.new()
	art.position = rect.position
	art.size = rect.size
	parent.add_child(art)
	art.call("configure", id, highlighted)
	return art

func _heroes_page() -> void:
	var roster := Catalog.playable_roster()
	if not roster.has(selected_actor): selected_actor = str(roster[0])
	var grid := _card_grid(Rect2(254, 98, 442, 535), 2)
	for id: String in roster:
		var p := _hero_card(id, Rect2(0, 0, 207, 158), grid)
		p.custom_minimum_size = Vector2(207, 158)
		var select := _button("", Rect2(0, 0, 207, 158), _select_hero.bind(id), p)
		select.add_theme_stylebox_override("normal", SiegeStyle.box(Color.TRANSPARENT, 16, SiegeStyle.GOLD if id == selected_actor else Color.TRANSPARENT))
		select.add_theme_stylebox_override("hover", SiegeStyle.box(Color(1, 0.9, 0.6, 0.09), 16, SiegeStyle.GOLD))
		select.add_theme_stylebox_override("pressed", SiegeStyle.box(Color(0.2, 0.5, 0.5, 0.1), 16, SiegeStyle.TEAL))
	var panel := _panel(Rect2(712, 98, 542, 535))
	var unit := Catalog.unit(selected_actor)
	var calc := _hero_calculation(selected_actor)
	panel.set_meta("unit_stats", calc.duplicate(true))
	panel.set_meta("unit_id", selected_actor)
	var title := _label(str(unit.get("name", selected_actor)), Rect2(24, 14, 316, 42), 32, SiegeStyle.INK, panel)
	_fit_name(title, 32)
	_portrait(selected_actor, Rect2(355, 14, 163, 145), panel, true)
	var desc := _label(str(unit.get("description", unit.get("summary", "守住微光，与同伴并肩而行。"))), Rect2(24, 65, 312, 60), 18, SiegeStyle.MUTED, panel)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(str(unit.get("role_name", "英魂")) + " · " + ("Lv.%d" % ProfileStore.level(selected_actor) if ProfileStore.owns(selected_actor) else "未契约") + " · " + _study_name(selected_actor), Rect2(24, 132, 312, 25), 15, SiegeStyle.TEAL, panel)
	var stats: Dictionary = calc.get("stats", {})
	for i in 3:
		var key: String = ["strength", "agility", "intelligence"][i]
		var main: bool = key == str(unit.get("primary_attribute", "strength"))
		var stat_panel := _panel(Rect2(24 + i * 165, 173, 151, 66), Color("e5e4d6") if not main else Color("ebdbb5"), panel)
		_icon(key, Rect2(10, 4, 24, 24), stat_panel)
		_label(_attribute_name(key) + (" · 主" if main else ""), Rect2(40, 5, 105, 23), 16, SiegeStyle.INK, stat_panel)
		_label("%.0f" % float(stats.get(key, 0)), Rect2(10, 29, 138, 32), 25, SiegeStyle.TEAL, stat_panel)
		var growth: Dictionary = unit.get("attribute_growth", {})
		_label("+%.0f / Lv" % float(growth.get(key, 2 if main else 1)), Rect2(66, 35, 79, 25), 13, SiegeStyle.MUTED, stat_panel)
	var stat_grid := GridContainer.new()
	stat_grid.position = Vector2(24, 253)
	stat_grid.size = Vector2(488, 110)
	stat_grid.columns = 3
	stat_grid.add_theme_constant_override("h_separation", 7)
	stat_grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(stat_grid)
	_stat_badge(stat_grid, "hp", "heart", "生命", "%.0f" % float(calc.hp))
	var healer: bool = str(calc.special.get("type", "")) == "heal"
	_stat_badge(stat_grid, "damage", "heal" if healer else "orb" if calc.damage_type == "magic" else "sword", "治疗" if healer else "伤害", "%.0f" % float(calc.special.get("amount", 0) if healer else calc.damage), Color("9a712d"))
	_stat_badge(stat_grid, "armor", "shield", "护甲", "%.0f" % float(calc.armor))
	_stat_badge(stat_grid, "range", "range", "射程", "%.0f" % float(calc.range))
	_stat_badge(stat_grid, "attack_interval", "clock", "出手间隔", "%.2fs" % float(calc.attack_interval))
	_stat_badge(stat_grid, "cost", "energy", "召唤能量", "%d" % int(unit.get("cost", 0)), Color("9a712d"))
	_icon("clock", Rect2(24, 373, 20, 20), panel)
	_label("召唤冷却 %.1fs" % float(unit.get("cooldown", 0)), Rect2(52, 369, 454, 25), 15, SiegeStyle.MUTED, panel)
	var rules := _label(_skill_focus(unit, calc), Rect2(24, 402, 488, 43), 15, SiegeStyle.TEAL, panel)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var level: int = ProfileStore.level(selected_actor)
	var b := _button("通关 %s 后契约" % Catalog.unlock_stage(selected_actor) if not ProfileStore.owns(selected_actor) else "已满级" if level >= 20 else "训练至 Lv.%d  ·  %d星砂" % [level + 1, ProfileStore.training_cost(selected_actor)], Rect2(24, 454, 488, 51), _train.bind(selected_actor), panel, true)
	b.disabled = not ProfileStore.can_modify() or not ProfileStore.owns(selected_actor) or level >= 20 or ProfileStore.credits() < ProfileStore.training_cost(selected_actor)

func _attribute_name(key: String) -> String:
	return {"strength": "力量", "agility": "敏捷", "intelligence": "智力"}.get(key, "力量")

func _skill_focus(unit: Dictionary, calc: Dictionary) -> String:
	var title := str(unit.get("skill_name", "战斗职责"))
	var special: Dictionary = calc.special
	var kind: String = {"physical": "物理", "magic": "魔法", "true": "真实"}.get(str(calc.damage_type), "物理")
	if str(special.get("type", "")) == "heal": return title + " · 治疗最受伤的伙伴\n不能修复基地"
	if str(special.get("type", "")) == "slow": return title + "\n减速：剩余移速 %.0f%% · %.2fs · 范围 %.0f" % [float(special.ratio) * 100, float(special.duration), float(calc.aoe_radius)]
	if str(special.get("type", "")) == "siege": return title + "\n攻城：基地伤害 %.2f倍 · %s" % [float(special.get("base_damage_multiplier", 1)), kind]
	return title + "\n%s%s · 前摇 %.2fs" % ["范围 %.0f · " % float(calc.aoe_radius) if float(calc.aoe_radius) > 0 else "单体", kind, float(calc.hit_delay)]

func _select_hero(id: String) -> void:
	pending_card_focus["英魂"] = id
	selected_actor = id
	show_home("英魂")

func _train(id: String) -> void:
	var success: bool = ProfileStore.upgrade(id)
	if success: GameAudio.play_cue("train")
	show_home("英魂")
	_message("训练完成，所有召唤实例都会继承成长。" if success else ProfileStore.error_message if not ProfileStore.error_message.is_empty() else "星砂不足或已满级。")

func _select_study(id: String) -> void:
	pending_card_focus["研修"] = id
	selected_actor = id
	show_home("研修")

func _study_modifier_text(modifiers: Dictionary) -> String:
	var labels := {"hp_mult": "生命", "damage_mult": "伤害", "speed_mult": "移速", "range_mult": "射程", "attack_interval_mult": "间隔", "hit_delay_mult": "前摇", "aoe_radius_mult": "范围", "heal_amount_mult": "治疗", "slow_duration_mult": "减速时长"}
	var parts: Array[String] = []
	for key: String in modifiers:
		var value := float(modifiers[key])
		if labels.has(key): parts.append("%s %+.0f%%" % [labels[key], (value - 1.0) * 100.0])
		elif key == "armor_add": parts.append("护甲 %+.0f" % value)
		elif key == "slow_ratio": parts.append("剩余移速 %.0f%%" % (value * 100))
		elif key == "base_damage_multiplier": parts.append("基地伤害 %.2f倍" % value)
	return " · ".join(parts)

func _study_preview_text(calc: Dictionary) -> String:
	var text := "生命 %.0f · 伤害 %.0f · 护甲 %.0f\n射程 %.0f · 移速 %.0f · 间隔 %.2fs" % [float(calc.hp), float(calc.damage), float(calc.armor), float(calc.range), float(calc.speed), float(calc.attack_interval)]
	var special: Dictionary = calc.get("special", {})
	if str(special.get("type", "")) == "heal": text += "\n治疗 %.0f" % float(special.amount)
	elif str(special.get("type", "")) == "slow": text += "\n剩余移速 %.0f%% · %.2fs" % [float(special.ratio) * 100, float(special.duration)]
	elif str(special.get("type", "")) == "siege": text += "\n基地伤害 %.2f倍" % float(special.base_damage_multiplier)
	else: text += "\n范围 %.0f · 前摇 %.2fs" % [float(calc.aoe_radius), float(calc.hit_delay)]
	return text

func _study_tradeoffs(modifiers: Dictionary, base: Dictionary) -> Dictionary:
	var result := {"benefits": [], "costs": []}
	var labels := {"hp_mult": "生命", "damage_mult": "伤害", "speed_mult": "移速", "range_mult": "射程", "attack_interval_mult": "间隔", "hit_delay_mult": "前摇", "aoe_radius_mult": "范围", "heal_amount_mult": "治疗", "slow_duration_mult": "控制时长"}
	for key: String in modifiers:
		var value := float(modifiers[key])
		var benefit := true
		var text := ""
		if labels.has(key):
			benefit = value < 1.0 if key in ["attack_interval_mult", "hit_delay_mult"] else value > 1.0
			text = "%s %+.0f%%" % [labels[key], (value - 1) * 100]
		elif key == "armor_add":
			benefit = value > 0
			text = "护甲 %+.0f" % value
		elif key == "slow_ratio":
			benefit = value < float(base.special.get("ratio", 1))
			text = "剩余移速 %.0f%%" % (value * 100)
		elif key == "base_damage_multiplier":
			benefit = value > float(base.special.get("base_damage_multiplier", 1))
			text = "攻城 %.2f倍" % value
		if not text.is_empty():
			if benefit: result.benefits.append(text)
			else: result.costs.append(text)
	return result

func _study_changed_values(base: Dictionary, preview: Dictionary) -> String:
	var labels := {"hp": "生命", "damage": "伤害", "armor": "护甲", "range": "射程", "speed": "移速", "attack_interval": "间隔", "hit_delay": "前摇", "aoe_radius": "范围"}
	var parts: Array[String] = []
	for key: String in labels:
		if is_equal_approx(float(base[key]), float(preview[key])): continue
		parts.append("%s %.2fs" % [labels[key], float(preview[key])] if key in ["attack_interval", "hit_delay"] else "%s %.0f" % [labels[key], float(preview[key])])
	for entry: Array in [["amount", "治疗"], ["duration", "控制秒数"], ["ratio", "剩余移速"], ["base_damage_multiplier", "攻城倍率"]]:
		var key := str(entry[0])
		if is_equal_approx(float(base.special.get(key, 0)), float(preview.special.get(key, 0))): continue
		if key == "ratio": parts.append("剩余移速 %.0f%%" % (float(preview.special.get(key, 1)) * 100))
		elif key == "duration": parts.append("控制 %.2fs" % float(preview.special.get(key, 0)))
		elif key == "amount": parts.append("治疗 %.0f" % float(preview.special.get(key, 0)))
		else: parts.append("攻城 %.2f倍" % float(preview.special.get(key, 0)))
	return " · ".join(parts)

func _study_page() -> void:
	var roster := Catalog.playable_roster()
	if not roster.has(selected_actor): selected_actor = str(roster[0])
	var grid := _card_grid(Rect2(254, 98, 228, 535), 1)
	for id: String in roster:
		var card := _hero_card(id, Rect2(0, 0, 211, 158), grid)
		card.custom_minimum_size = Vector2(211, 158)
		var choose := _button("", Rect2(0, 0, 211, 158), _select_study.bind(id), card)
		choose.add_theme_stylebox_override("normal", SiegeStyle.box(Color.TRANSPARENT, 16, SiegeStyle.GOLD if id == selected_actor else Color.TRANSPARENT))
		choose.add_theme_stylebox_override("hover", SiegeStyle.box(Color(1, 0.9, 0.6, 0.09), 16, SiegeStyle.GOLD))
	var panel := _panel(Rect2(498, 98, 756, 535))
	panel.name = "StudyDetails"
	var unit := Catalog.unit(selected_actor)
	var calc := _hero_calculation(selected_actor)
	panel.set_meta("unit_stats", calc.duplicate(true))
	panel.set_meta("unit_id", selected_actor)
	var title := _label(str(unit.get("name", selected_actor)) + " · 英魂研修", Rect2(18, 10, 580, 37), 27, SiegeStyle.INK, panel)
	_fit_name(title, 27)
	_portrait(selected_actor, Rect2(630, 12, 108, 106), panel, true)
	_label("当前 · %s    Lv.%d" % [_study_name(selected_actor), ProfileStore.level(selected_actor)], Rect2(18, 51, 590, 25), 17, SiegeStyle.TEAL, panel)
	var attrs: Dictionary = calc.stats
	_label("力量 %.0f · 敏捷 %.0f · 智力 %.0f · 主属性 %s" % [float(attrs.strength), float(attrs.agility), float(attrs.intelligence), _attribute_name(str(calc.primary))], Rect2(18, 80, 590, 25), 15, SiegeStyle.MUTED, panel)
	var current := GridContainer.new()
	current.name = "StudyCurrentStats"
	current.position = Vector2(18, 117)
	current.size = Vector2(720, 52)
	current.columns = 6
	current.add_theme_constant_override("h_separation", 6)
	panel.add_child(current)
	_stat_badge(current, "hp", "heart", "生命", "%.0f" % float(calc.hp))
	var healing: bool = str(calc.special.get("type", "")) == "heal"
	_stat_badge(current, "damage", "heal" if healing else "sword", "治疗" if healing else "伤害", "%.0f" % float(calc.special.get("amount", 0) if healing else calc.damage))
	_stat_badge(current, "armor", "shield", "护甲", "%.0f" % float(calc.armor))
	_stat_badge(current, "range", "range", "射程", "%.0f" % float(calc.range))
	_stat_badge(current, "speed", "agility", "移速", "%.0f" % float(calc.speed))
	_stat_badge(current, "attack_interval", "clock", "间隔", "%.2fs" % float(calc.attack_interval))
	var skill := _label(_skill_focus(unit, calc), Rect2(18, 182, 720, 49), 15, SiegeStyle.TEAL, panel)
	skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var config := Catalog.study(selected_actor)
	var study_stage := str(config.get("unlock_stage", "stage_04"))
	var ready_stage: bool = ProfileStore.data.get("cleared", []).has(study_stage)
	var cost: int = ProfileStore.study_unlock_cost()
	var unlocked: bool = ProfileStore.study_unlocked(selected_actor)
	var conditions := "已解锁 · 营地免费切换，两条路线均已开放" if unlocked else "%s契约 · %sLv.%d · %s第四关首通\n一次解锁两条路线，初始保留基础" % ["✓ " if ProfileStore.owns(selected_actor) else "未", "✓ " if ProfileStore.level(selected_actor) >= int(config.get("min_level", 3)) else "需", int(config.get("min_level", 3)), "✓ " if ready_stage else "需"]
	var condition_label := _label(conditions, Rect2(18, 238, 500, 38), 14, SiegeStyle.TEAL, panel)
	condition_label.name = "StudyConditions"
	var unlock := _button("已解锁" if unlocked else "解锁 · %d星砂" % cost, Rect2(536, 239, 202, 36), _unlock_study.bind(selected_actor), panel, true)
	unlock.name = "StudyUnlock"
	unlock.disabled = unlocked or not ProfileStore.can_modify() or not ProfileStore.owns(selected_actor) or ProfileStore.level(selected_actor) < int(config.get("min_level", 3)) or not ready_stage or ProfileStore.credits() < cost
	var routes := Catalog.study_routes(selected_actor)
	var base_calc := UnitStats.calculate(unit, ProfileStore.level(selected_actor))
	for i in routes.size():
		var route: Dictionary = routes[i]
		var active := ProfileStore.study_route(selected_actor) == str(route.id)
		var card := _panel(Rect2(18 + i * 369, 286, 351, 208), Color("ede4cd") if active else Color("e7e6d9"), panel)
		card.name = "StudyRoute_" + str(route.id)
		var preview := UnitStats.calculate(unit, ProfileStore.level(selected_actor), route.modifiers)
		card.set_meta("unit_stats", preview.duplicate(true))
		_label(str(route.name) + (" · 当前" if active else ""), Rect2(14, 7, 323, 27), 21, SiegeStyle.TEAL, card)
		var tradeoffs := _study_tradeoffs(route.modifiers, base_calc)
		var benefit := _label("收益 · " + " / ".join(tradeoffs.benefits), Rect2(14, 40, 323, 38), 14, SiegeStyle.TEAL, card)
		benefit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var cost_label := _label("代价 · " + " / ".join(tradeoffs.costs), Rect2(14, 84, 323, 38), 14, Color("9a712d"), card)
		cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var changed := _label("选择后 · " + _study_changed_values(base_calc, preview), Rect2(14, 128, 323, 44), 12, SiegeStyle.MUTED, card)
		changed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var switch := _button("当前路线" if active else "免费切换" if unlocked else "解锁后可选", Rect2(14, 177, 323, 27), _set_study_route.bind(selected_actor, str(route.id)), card, active)
		switch.name = "StudySelect_" + str(route.id)
		switch.add_theme_font_size_override("font_size", 14)
		switch.disabled = not unlocked or active or not ProfileStore.can_modify()
	var restore := _button("当前为基础路线" if ProfileStore.study_route(selected_actor) == "base" else "免费恢复基础路线", Rect2(18, 501, 720, 27), _set_study_route.bind(selected_actor, "base"), panel)
	restore.name = "StudyRestore"
	restore.add_theme_font_size_override("font_size", 14)
	restore.disabled = not unlocked or ProfileStore.study_route(selected_actor) == "base" or not ProfileStore.can_modify()
	var footer_rule := _label("路线有收益，也有代价。基础八关可用基础路线完成；研修只改变出战策略。", Rect2(504, 641, 742, 28), 15, Color("c2d5cb"))
	footer_rule.name = "StudyFooterRule"

func _unlock_study(id: String) -> void:
	var success: bool = ProfileStore.unlock_study(id)
	if success: GameAudio.play_cue("train")
	show_home("研修")
	_message("两条研修路线已解锁，可免费切换；当前仍为基础路线。" if success else ProfileStore.error_message if not ProfileStore.error_message.is_empty() else "请满足契约、等级、首通及星砂条件。")

func _set_study_route(id: String, route_id: String) -> void:
	var success: bool = ProfileStore.set_study_route(id, route_id)
	show_home("研修")
	_message("已保存 · " + _study_name(id) if success else ProfileStore.error_message if not ProfileStore.error_message.is_empty() else "研修尚未解锁或路线无效。")

func _squad_page() -> void:
	draft_roster = ProfileStore.data.get("roster", Catalog.initial_roster()).duplicate()
	_label("前排承压、远程破阵、辅助续航。最多携带八名英魂。", Rect2(256, 88, 995, 38), 20, Color("c2d5cb"))
	var grid := _card_grid(Rect2(254, 145, 1000, 442), 4)
	for id: String in Catalog.playable_roster():
		var p := _hero_card(id, Rect2(0, 0, 234, 236), grid)
		p.custom_minimum_size = Vector2(234, 236)
		var unit := Catalog.unit(id)
		_icon("energy", Rect2(16, 148, 19, 19), p)
		_label("召唤 %d能量" % int(unit.get("cost", 0)), Rect2(42, 146, 174, 23), 14, Color("9a712d"), p)
		_icon("clock", Rect2(16, 175, 19, 19), p)
		_label("冷却 %.1fs" % float(unit.get("cooldown", 0)), Rect2(42, 173, 174, 23), 14, SiegeStyle.MUTED, p)
		var owned: bool = ProfileStore.owns(id)
		var slot: int = draft_roster.find(id) + 1
		p.set_meta("roster_slot", slot)
		var button := _button("%s 后契约" % Catalog.unlock_stage(id) if not owned else "%d号位 · 移出" % slot if slot > 0 else "加入编队", Rect2(16, 200, 202, 30), _toggle_roster.bind(id), p, slot > 0)
		button.name = "RosterToggle_" + id
		button.set_meta("roster_slot", slot)
		button.add_theme_font_size_override("font_size", 15)
		button.disabled = not ProfileStore.can_modify() or not owned or (not draft_roster.has(id) and draft_roster.size() >= 8)
	_label("当前 %d / 8 名英魂。点击即保存，至少保留一名；1—8号位对应召唤键。" % draft_roster.size(), Rect2(263, 610, 970, 39), 18, Color("c2d5cb"))

func _toggle_roster(id: String) -> void:
	var candidate := draft_roster.duplicate()
	if candidate.has(id): candidate.erase(id)
	else: candidate.append(id)
	var success: bool = ProfileStore.set_roster(candidate)
	show_home("编队")
	_message("编队已保存。" if success else ProfileStore.error_message if not ProfileStore.error_message.is_empty() else "编队需包含一至八名已契约英魂。")

func _gallery_category(value: String) -> void:
	gallery_kind = value
	show_home("图鉴")

func _skill_details(unit: Dictionary, calc: Dictionary) -> String:
	var text := str(unit.get("skill_name", "战斗职责"))
	var special: Dictionary = calc.get("special", {})
	if str(special.get("type", "")) == "heal":
		text += "\n每次治疗 %.0f · 选择范围内最受伤的伙伴" % float(special.get("amount", calc.get("damage", 0)))
	elif str(special.get("type", "")) == "slow":
		text += "\n魔法攻击 · 范围 %.0f · 移速剩余 %.0f%% · %.2fs" % [float(calc.get("aoe_radius", 0)), float(special.get("ratio", 1)) * 100, float(special.get("duration", 0))]
	elif str(special.get("type", "")) == "siege":
		text += "\n对基地 %.2f倍 · 真实伤害" % float(special.get("base_damage_multiplier", 1))
	elif float(calc.get("aoe_radius", 0)) > 0:
		text += "\n范围攻击 %.0fpx · 命中前摇 %.2fs" % [float(calc.get("aoe_radius", 0)), float(calc.get("hit_delay", 0))]
	else:
		var kind: String = {"physical": "物理", "magic": "魔法", "true": "真实"}.get(str(calc.get("damage_type", "physical")), "物理")
		text += "\n单体%s · 射程 %.0f · 前摇 %.2fs · 护甲 %.0f" % [kind, float(calc.get("range", 0)), float(calc.get("hit_delay", 0)), float(calc.get("armor", 0))]
	if special.has("phase_threshold"):
		text += "\n半血伤害×%.2f · 攻击间隔×%.2f" % [float(special.get("phase_damage_mult", 1)), float(special.get("phase_attack_mult", 1))]
	return text

func _gallery_page() -> void:
	var ids := Catalog.playable_roster() if gallery_kind == "heroes" else Catalog.enemy_roster()
	if ids.is_empty(): return
	_button("英魂", Rect2(272, 98, 166, 40), _gallery_category.bind("heroes"), null, gallery_kind == "heroes")
	_button("敌军", Rect2(454, 98, 166, 40), _gallery_category.bind("enemies"), null, gallery_kind == "enemies")
	var picker := OptionButton.new()
	picker.name = "GalleryPicker"
	picker.position = Vector2(272, 151)
	picker.size = Vector2(364, 44)
	var current := 0
	for i in ids.size():
		var unit := Catalog.unit(str(ids[i]))
		picker.add_item(str(unit.get("name", ids[i])))
		if str(unit.get("visual_id", "")) == selected_visual: current = i
	picker.select(current)
	screen.add_child(picker)
	picker.item_selected.connect(func(index: int):
		if not _button_action_allowed(picker): return
		selected_visual = str(Catalog.unit(str(ids[index])).get("visual_id", ""))
		show_home("图鉴"))
	var id: String = ids[current]
	var unit := Catalog.unit(id)
	selected_visual = str(unit.get("visual_id", ""))
	var owned: bool = ProfileStore.owns(id)
	var level: int = ProfileStore.level(id) if gallery_kind == "heroes" else 1
	var calc := _hero_calculation(id) if gallery_kind == "heroes" else UnitStats.calculate(unit, level)
	var panel := _panel(Rect2(254, 211, 386, 421))
	panel.set_meta("unit_stats", calc.duplicate(true))
	panel.set_meta("unit_id", id)
	_label(str(unit.get("name", id)), Rect2(18, 13, 348, 36), 25, SiegeStyle.INK, panel)
	_label(str(unit.get("role_name", "")) + " · 主属性 " + _attribute_name(str(calc.primary)), Rect2(18, 53, 348, 25), 15, SiegeStyle.TEAL, panel)
	var attrs: Dictionary = calc.get("stats", {})
	_label("力量 %.0f · 敏捷 %.0f · 智力 %.0f" % [float(attrs.get("strength", 0)), float(attrs.get("agility", 0)), float(attrs.get("intelligence", 0))], Rect2(18, 80, 348, 25), 14, SiegeStyle.MUTED, panel)
	var grid := GridContainer.new()
	grid.position = Vector2(18, 113)
	grid.size = Vector2(348, 110)
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)
	_stat_badge(grid, "hp", "heart", "生命", "%.0f" % float(calc.hp))
	var healing: bool = str(calc.special.get("type", "")) == "heal"
	var damage_name: String = {"physical":"物理", "magic":"魔法", "true":"真实"}.get(str(calc.damage_type), "物理")
	_stat_badge(grid, "damage", "heal" if healing else "orb" if calc.damage_type == "magic" else "sword", "治疗" if healing else damage_name + "伤害", "%.0f" % float(calc.special.get("amount", 0) if healing else calc.damage))
	_stat_badge(grid, "armor", "shield", "护甲", "%.0f" % float(calc.armor))
	_stat_badge(grid, "magic_armor", "ward", "魔抗", "%.0f" % float(calc.magic_armor), Color("80679b"))
	_stat_badge(grid, "range", "range", "射程", "%.0f" % float(calc.range))
	_stat_badge(grid, "attack_interval", "clock", "攻击间隔", "%.2fs" % float(calc.attack_interval))
	var skills := _label(_skill_focus(unit, calc), Rect2(18, 233, 348, 43), 14, SiegeStyle.TEAL, panel)
	skills.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if gallery_kind == "enemies":
		var special: Dictionary = calc.special
		if special.has("phase_threshold"):
			var phase := _panel(Rect2(18, 282, 348, 64), Color("efe1c2"), panel)
			phase.name = "GalleryPhase"
			var threshold := float(special.phase_threshold)
			_label(("半血" if is_equal_approx(threshold, 0.5) else "%.0f%%生命" % (threshold * 100)) + " → " + str(special.get("phase_name", "强化阶段")), Rect2(10, 7, 328, 22), 16, Color("9a712d"), phase)
			_label("伤害×%.2f · 间隔×%.2f · 移速×%.2f" % [float(special.get("phase_damage_mult", 1)), float(special.get("phase_attack_mult", 1)), float(special.get("phase_speed_mult", 1))], Rect2(10, 35, 328, 20), 12, SiegeStyle.INK, phase)
		var terms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/briefings.json"))
		var counters: Array = terms.get("enemies", {}).get(id, {}).get("counters", [])
		var advice := " · ".join(counters)
		if special.has("phase_threshold"): advice += " · 首领推退25%"
		var counter := _label(advice, Rect2(18, 353, 348, 28), 13, SiegeStyle.TEAL, panel)
		counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var context := _label("出现 · " + "、".join(Catalog.appearances(id)), Rect2(18, 385, 348, 32), 12, SiegeStyle.MUTED, panel)
		context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		var rule := _label("已契约 · Lv.%d · %s" % [level, _study_name(id)] if owned else "通关 %s 后契约" % Catalog.unlock_stage(id), Rect2(18, 286, 348, 33), 15, SiegeStyle.TEAL, panel)
		rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var summon := GridContainer.new()
		summon.position = Vector2(18, 334)
		summon.size = Vector2(348, 54)
		summon.columns = 2
		summon.add_theme_constant_override("h_separation", 8)
		panel.add_child(summon)
		_stat_badge(summon, "cost", "energy", "召唤能量", "%d" % int(unit.get("cost", 0)), Color("9a712d"))
		_stat_badge(summon, "cooldown", "clock", "召唤冷却", "%.1fs" % float(unit.get("cooldown", 0)))
	var glossary := _panel(Rect2(254, 642, 386, 55), Color("1c3a48"))
	_label("魔法按魔抗减伤 · 真实无视护甲\n前摇是命中等待；间隔是两次出手节奏", Rect2(12, 7, 362, 43), 13, Color("d2e1d8"), glossary)
	_label("星灯之友" if gallery_kind == "heroes" else "裂隙生物", Rect2(690, 107, 545, 39), 25, Color("f1e4c6"))
	var frame := _panel(Rect2(671, 158, 583, 380), Color("1c3a48"))
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait("", Rect2(8, 8, 567, 364), frame)
	var actor_script: Script = load("res://scripts/visuals/SpineActor.gd")
	viewer = actor_script.new()
	viewer.position = Vector2(273, 345)
	frame.add_child(viewer)
	viewer.configure(selected_visual, 1)
	viewer.scale = Vector2(1.65, 1.65)
	viewer.play_state("idle")
	var states := ["idle", "move", "attack", "skill", "hurt", "death"]
	var names := ["待机", "行走", "攻击", "技能", "受击", "死亡"]
	for i in states.size():
		_button(names[i], Rect2(690 + (i % 3) * 187, 550 + int(i / 3) * 53, 170, 42), _preview_state.bind(states[i]))
	_button("朝左", Rect2(721, 660, 165, 37), _preview_facing.bind(-1))
	_button("朝右", Rect2(928, 660, 165, 37), _preview_facing.bind(1))

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
	selected_chapter = int(stage.get("chapter", 1))
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
	battle.start(id, draft_roster, ProfileStore.data.get("levels", {}), ProfileStore.study_modifiers_snapshot())
	_build_battle_hud()
	status_label.text = str(stage.get("hint", "持续补线，守住微光。"))
	GameAudio.set_context("battle")
	hud_elapsed = 0
	intro_time = 12.0
	intro_panel = _panel(Rect2(390, 177, 500, 88), Color(0.08, 0.18, 0.25, 0.9))
	intro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var narrative := _label(str(stage.get("story_intro", "")), Rect2(18, 10, 464, 69), 16, Color("d7e6dc"), intro_panel)
	narrative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if id == "stage_01" and not bool(UserPrefs.get_value("tutorial_seen", false)): _open_guide()

func _health_bar(rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.show_percentage = false
	for entry: Array in [["background", Color("162d38")], ["fill", color]]:
		var style := SiegeStyle.box(entry[1], 7)
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		style.content_margin_left = 0
		style.content_margin_right = 0
		bar.add_theme_stylebox_override(entry[0], style)
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
	pulse_button.icon = load("res://assets/ui/icons/pulse.svg")
	pulse_button.expand_icon = true
	pulse_button.add_theme_constant_override("icon_max_width", 21)
	pulse_button.add_theme_font_size_override("font_size", 14)
	view_slider = HSlider.new()
	view_slider.position = Vector2(244, 534)
	view_slider.size = Vector2(792, 15)
	view_slider.max_value = view_max
	view_slider.step = 1
	screen.add_child(view_slider)
	view_slider.value_changed.connect(_slide_view)
	_label("星灯", Rect2(33, 525, 130, 26), 14, Color("b6c8c2"))
	_label("← → / 拖动", Rect2(1049, 525, 105, 26), 14, Color("b6c8c2"))
	_button("设置", Rect2(1162, 527, 93, 27), _open_settings)
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
		var name_label := _label("%d · %s" % [i + 1, str(unit.get("name", id))], Rect2(7, 4, 135, 27), 17, SiegeStyle.INK, b)
		_fit_name(name_label, 17)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_portrait(id, Rect2(8, 34, 59, 76), b)
		var role_label := _label(str(unit.get("role_name", unit.get("role", "英魂"))), Rect2(73, 36, 70, 24), 13, SiegeStyle.TEAL, b)
		_icon("energy", Rect2(71, 66, 17, 17), b)
		var cost_label := _label("%d能量" % int(unit.get("cost", 0)), Rect2(91, 65, 54, 23), 13, Color("9a712d"), b)
		var ready_label := _label("召唤", Rect2(73, 91, 70, 21), 12, SiegeStyle.TEAL, b)
		summon_labels.append({"name": name_label, "role": role_label, "cost": cost_label, "ready": ready_label})
		summon_buttons.append(b)
	for i in 24:
		var label := _label("", Rect2(0, 0, 100, 30), 18, Color("ffdfa5"), world_host)
		label.z_index = 60
		label.visible = false
		motes.append({"node": label, "life": 0.0, "tint": Color("ffdfa5")})
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
	pulse_button.text = "脉冲[P] 80能量 · %.1fs" % (ceilf(pulse_remaining * 10.0) / 10.0) if pulse_remaining > SiegeBattle.READY_EPSILON else "星灯脉冲 [P] · 80"
	pulse_button.disabled = paused or pulse_remaining > SiegeBattle.READY_EPSILON or float(snap.get("energy", 0)) + SiegeBattle.READY_EPSILON < float(snap.get("pulse_cost", 80)) or str(snap.get("outcome", "running")) != "running"
	for i in summon_buttons.size():
		var id: String = draft_roster[i]
		var unit := Catalog.unit(id)
		var remaining := float(cooldowns.get(id, 0))
		var cost := int(unit.get("cost", 0))
		var b := summon_buttons[i]
		b.disabled = paused or remaining > SiegeBattle.READY_EPSILON or float(snap.get("energy", 0)) + SiegeBattle.READY_EPSILON < cost or str(snap.get("outcome", "running")) != "running" or int(snap.get("active_count", 0)) >= 64
		var ready: Label = summon_labels[i].ready
		ready.text = "%.1fs" % (ceilf(remaining * 10.0) / 10.0) if remaining > SiegeBattle.READY_EPSILON else "暂停中" if paused else "能量不足" if float(snap.get("energy", 0)) + SiegeBattle.READY_EPSILON < cost else "已满" if int(snap.get("active_count", 0)) >= 64 else "召唤"
		ready.add_theme_color_override("font_color", SiegeStyle.MUTED if b.disabled else SiegeStyle.TEAL)

func _summon(id: String) -> void:
	if not is_instance_valid(battle) or paused: return
	if not battle.try_summon(id):
		_message("能量不足、尚在冷却或战场已满。")
	else: GameAudio.play_cue("summon")
	_update_hud()

func _pulse() -> void:
	if not is_instance_valid(battle) or paused: return
	if not battle.try_pulse(): _message("需要80能量、冷却完成，并有可命中的敌军。")
	_update_hud()

func _toggle_pause() -> void:
	if not is_instance_valid(battle) or is_instance_valid(result_panel) or is_instance_valid(_active_modal()): return
	paused = not paused
	if battle.has_method("set_visual_playback"): battle.set_visual_playback(0.0 if paused else speed)
	pause_button.text = "继续" if paused else "暂停"
	status_label.text = "已暂停 · 整理思路，然后继续。" if paused else "守住前排，让远程英魂持续输出。"

func _toggle_speed() -> void:
	if not is_instance_valid(battle) or is_instance_valid(_active_modal()): return
	speed = 2.0 if speed == 1 else 1.0
	if battle.has_method("set_visual_playback"): battle.set_visual_playback(0.0 if paused else speed)
	speed_button.text = "%d×" % int(speed)

func _combat_event(kind: String, position_at: Vector2, amount: float, team: int) -> void:
	if not is_instance_valid(screen): return
	if kind == "hit" or kind == "heal" or kind == "base_hit":
		_floating_text(("+" if kind == "heal" else "") + ("%.0f" % amount), position_at, Color("94e7b0") if kind == "heal" else Color("ffdfa5"))
		GameAudio.play_cue("heal" if kind == "heal" else "hit")
	elif kind == "pulse":
		world.add_pulse(position_at)
		GameAudio.play_cue("pulse")
		status_label.text = "星灯脉冲！打断前线敌军，争取补线时间。"
	elif kind == "stun":
		_floating_text("打断", position_at, Color("8cf6d8"))
	elif kind == "phase":
		GameAudio.play_cue("warning")
		var phase_name := "首领强化阶段"
		if is_instance_valid(battle):
			for actor: Dictionary in battle.units:
				if not bool(actor.get("phase", false)) or int(actor.get("team", 0)) != team: continue
				var phase_position := Vector2(float(actor.x), SiegeBattle.GROUND_Y - 100.0)
				if not phase_position.is_equal_approx(position_at): continue
				var special: Dictionary = actor.get("special", {})
				var configured_name := str(special.get("phase_name", "")).strip_edges()
				if float(special.get("phase_threshold", 0.0)) <= 0.0 or configured_name.is_empty(): continue
				phase_name = configured_name
				break
		status_label.text = phase_name + "！坚守阵线，寻找反攻窗口。"
	elif kind == "attack" and team == -1 and amount >= 0.7:
		GameAudio.play_cue("warning")
		status_label.text = "重击预警！补上前排，保护远程。"

func _floating_text(value: String, point: Vector2, color: Color) -> void:
	if not bool(UserPrefs.get_value("damage_numbers", true)) or motes.is_empty(): return
	if point.x < view_x - 100 or point.x > view_x + 1380: return
	var mote: Dictionary = motes[mote_cursor]
	mote_cursor = (mote_cursor + 1) % motes.size()
	var label: Label = mote.node
	label.text = value
	label.position = point - Vector2(35, 87)
	label.visible = true
	label.modulate = Color.WHITE
	if mote.tint != color:
		label.add_theme_color_override("font_color", color)
		mote.tint = color
	mote.life = 1.0

func _battle_finished(victory: bool) -> void:
	if is_instance_valid(result_panel): return
	if is_instance_valid(toast): toast.visible = false
	toast_time = 0.0
	GameAudio.play_cue("victory" if victory else "defeat")
	paused = true
	if battle.has_method("set_visual_playback"): battle.set_visual_playback(0.0)
	result_report = battle.get_battle_report()
	result_victory = victory
	result_saved = ProfileStore.win(run_token) if victory else false
	result_award.clear()
	if victory and result_saved:
		result_award = ProfileStore.last_award.duplicate(true)
		run_token = ""
	elif not victory:
		ProfileStore.abandon(run_token)
		run_token = ""
	if not is_instance_valid(result_shade):
		result_shade = ColorRect.new()
		result_shade.size = Vector2(1280, 720)
		result_shade.color = Color(0.03, 0.09, 0.13, 0.82)
		screen.add_child(result_shade)
	_render_result()

func _result_value(parent: Node, name: String, text: String, tint: Color = SiegeStyle.INK) -> Label:
	var label := _briefing_line(text, parent, 16, tint)
	label.name = name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

func _render_result() -> void:
	if result_report.is_empty() or str(result_report.get("outcome", "")) not in ["victory", "defeat"]: return
	for layer in [exit_panel, settings_panel, guide_panel]:
		if is_instance_valid(layer): return
	if is_instance_valid(result_panel):
		_unlock_modal_focus(result_panel)
		screen.remove_child(result_panel)
		result_panel.queue_free()
	var previous_focus := get_viewport().gui_get_focus_owner()
	result_panel = _panel(Rect2(224, 78, 832, 566))
	result_panel.name = "BattleResult"
	result_panel.z_index = 200
	_label("星灯重燃" if result_victory else "微光尚未熄灭", Rect2(24, 13, 784, 42), 33, SiegeStyle.TEAL if result_victory else SiegeStyle.INK, result_panel)
	var stage := Catalog.stage(str(result_report.get("stage_id", active_stage)))
	var elapsed := maxi(0, int(result_report.get("elapsed", 0)))
	_label("%s  ·  本场 %02d:%02d%s" % [str(stage.get("name", "远征")), elapsed / 60, elapsed % 60, " · 测试夹具" if bool(result_report.get("fixture", false)) else ""], Rect2(24, 58, 784, 27), 17, SiegeStyle.MUTED, result_panel)
	var reward := _panel(Rect2(24, 100, 254, 354), Color("faf6eb"), result_panel)
	reward.name = "ResultReward"
	reward.set_meta("result_award", result_award.duplicate(true))
	reward.set_meta("result_saved", result_saved)
	_label("战利与保存" if result_victory else "下一次尝试", Rect2(14, 10, 226, 30), 22, SiegeStyle.TEAL, reward)
	var retry: Button
	if result_victory and result_saved:
		var gain := GridContainer.new()
		gain.position = Vector2(14, 55)
		gain.size = Vector2(226, 54)
		reward.add_child(gain)
		_stat_badge(gain, "award_credits", "star", "获得星砂", "%d" % int(result_award.get("credits", 0)), Color("9a712d"))
		_label("基础 %d · 首通额外 %d" % [int(result_award.get("base_credits", 0)), int(result_award.get("bonus_credits", 0))], Rect2(14, 118, 226, 26), 14, SiegeStyle.MUTED, reward)
		var saved := _label("已保存 · " + ("首次点亮" if bool(result_award.get("first_clear", false)) else "重访奖励"), Rect2(14, 150, 226, 27), 16, SiegeStyle.TEAL, reward)
		saved.name = "ResultSavedStatus"
		var unlocks: Array = result_award.get("unlock_units", [])
		if not unlocks.is_empty():
			_portrait(str(unlocks[0]), Rect2(14, 190, 76, 104), reward)
			var contract := _label("新契约\n" + _briefing_names(unlocks), Rect2(102, 192, 138, 104), 17, SiegeStyle.TEAL, reward)
			contract.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			var ready := _label("星砂可用于训练。\n也可结合敌情调整编队与研修。", Rect2(14, 198, 226, 87), 17, SiegeStyle.INK, reward)
			ready.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif result_victory:
		var pending := _label("奖励尚未保存", Rect2(14, 58, 226, 36), 22, Color("9a712d"), reward)
		pending.name = "ResultPendingStatus"
		var reason := _label("保存失败，请重试领取。\n" + ProfileStore.error_message, Rect2(14, 107, 226, 114), 16, SiegeStyle.INK, reward)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		retry = _button("重试保存奖励", Rect2(14, 253, 226, 45), _retry_reward, reward, true)
		retry.name = "ResultRetry"
		_label("战报可查看，保存后再继续。", Rect2(14, 312, 226, 27), 14, SiegeStyle.MUTED, reward)
	else:
		var advice := _label("本次未获得奖励。\n查看本关敌情，再考虑前排、治疗与召唤节奏。", Rect2(14, 59, 226, 110), 18, SiegeStyle.INK, reward)
		advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var options := _label("可直接再战，或先调整编队。\n这些操作不扣除星砂。", Rect2(14, 205, 226, 82), 16, SiegeStyle.TEAL, reward)
		options.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var report := _panel(Rect2(298, 100, 510, 354), Color("faf6eb"), result_panel)
	report.name = "ResultReport"
	report.set_meta("battle_report", result_report.duplicate(true))
	_label("本场有效贡献", Rect2(12, 9, 486, 30), 22, SiegeStyle.TEAL, report)
	var totals: Dictionary = result_report.get("totals", {})
	var grid := GridContainer.new()
	grid.position = Vector2(12, 45)
	grid.size = Vector2(486, 52)
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	report.add_child(grid)
	_stat_badge(grid, "report_damage", "sword", "对兵伤害", "%.0f" % float(totals.get("damage", 0)))
	_stat_badge(grid, "report_healing", "heal", "有效治疗", "%.0f" % float(totals.get("healing", 0)))
	_stat_badge(grid, "report_base_damage", "siege", "有效攻城", "%.0f" % float(totals.get("base_damage", 0)), Color("9a712d"))
	_label("召唤 %d · 阵亡 %d · 支出 %.0f能量 · 英魂承伤 %.0f" % [int(totals.get("summons", 0)), int(totals.get("fallen", 0)), float(totals.get("energy_spent", 0)), float(totals.get("damage_taken", 0))], Rect2(12, 104, 486, 25), 13, SiegeStyle.MUTED, report)
	var pulse := _label("脉冲 %d次 · 命中 %d人次 · 打断 %d次 · 有效伤害 %.0f" % [int(totals.get("pulse_uses", 0)), int(totals.get("pulse_targets", 0)), int(totals.get("pulse_interrupts", 0)), float(totals.get("pulse_damage", 0))], Rect2(12, 133, 486, 26), 14, Color("9a712d"), report)
	pulse.name = "ResultPulse"
	var scroll := ScrollContainer.new()
	scroll.name = "ResultMemberScroll"
	scroll.position = Vector2(12, 172)
	scroll.size = Vector2(486, 168)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	for member: Dictionary in result_report.get("members", []):
		var row := _briefing_card(rows)
		row.get_parent().name = "ResultMember_" + str(member.id)
		row.get_parent().set_meta("report_member", member.duplicate(true))
		var columns := HBoxContainer.new()
		columns.add_theme_constant_override("separation", 8)
		row.add_child(columns)
		var identity := VBoxContainer.new()
		identity.custom_minimum_size.x = 142
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(identity)
		_briefing_line("%s · %d级" % [str(member.name), int(member.level)], identity, 14)
		var count := _briefing_line("未召唤" if int(member.summons) == 0 else "召唤 %d / 阵亡 %d" % [int(member.summons), int(member.fallen)], identity, 12, SiegeStyle.MUTED)
		count.name = "SummonsValue"
		for metric: Array in [["damage", "伤害", "DamageValue"], ["healing", "治疗", "HealingValue"], ["base_damage", "攻城", "BaseDamageValue"]]:
			var cell := VBoxContainer.new()
			cell.custom_minimum_size.x = 78
			columns.add_child(cell)
			var caption := _briefing_line(str(metric[1]), cell, 12, SiegeStyle.MUTED)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_result_value(cell, str(metric[2]), "%.0f" % float(member.get(str(metric[0]), 0)))
	if result_report.get("members", []).is_empty(): _briefing_line("本场未携带英魂。", rows, 16, SiegeStyle.MUTED)
	var can_leave: bool = not result_victory or result_saved
	var next_id := active_stage
	if result_victory:
		var stages := Catalog.stages()
		for i in stages.size():
			if str(stages[i].id) == active_stage and i + 1 < stages.size(): next_id = str(stages[i + 1].id)
	var next := _button("继续远征" if result_victory and next_id != active_stage else "再战一次", Rect2(24, 474, 240, 43), start_stage.bind(next_id), result_panel, can_leave)
	next.name = "ResultContinue"
	next.disabled = not can_leave or not ProfileStore.can_modify() or not ProfileStore.stage_unlocked(next_id)
	var briefing := _button("本关敌情", Rect2(280, 474, 160, 43), _open_briefing.bind(active_stage), result_panel)
	briefing.name = "ResultBriefing"
	briefing.disabled = not can_leave
	var squad := _button("调整编队", Rect2(456, 474, 160, 43), show_home.bind("编队"), result_panel)
	squad.name = "ResultSquad"
	squad.disabled = not can_leave
	var home := _button("返回营地", Rect2(632, 474, 176, 43), show_home.bind("远征"), result_panel)
	home.name = "ResultHome"
	home.disabled = not can_leave
	var ending_text := str(stage.get("story_outro", "每一次尝试，都让微光更近一步。")) if result_victory and result_saved else "统计有效生命变化；守线与控制价值还需结合战线判断。"
	ending_text += "\n对兵总伤害含脉冲；英魂表只计各自贡献。"
	var ending := _label(ending_text, Rect2(24, 523, 784, 40), 13, SiegeStyle.MUTED, result_panel)
	ending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lock_modal_focus(result_panel, previous_focus, retry if is_instance_valid(retry) else next if not next.disabled else home)

func _retry_reward() -> void:
	if not result_victory or result_saved or run_token.is_empty(): return
	if ProfileStore.win(run_token):
		run_token = ""
		result_saved = true
		result_award = ProfileStore.last_award.duplicate(true)
		_render_result()
		_message("奖励已保存。")
	else: _message(ProfileStore.error_message)
