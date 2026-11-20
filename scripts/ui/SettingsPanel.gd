class_name SiegeSettingsPanel
extends Control

signal closed

const STYLE = preload("res://scripts/ui/UIStyle.gd")
const VOLUME_ROWS := {
	"master_volume": "主音量",
	"music_volume": "音乐",
	"sfx_volume": "音效",
}
const OPTION_ROWS := {
	"fullscreen": "全屏显示（F11）",
	"damage_numbers": "显示伤害与治疗飘字",
	"edge_scroll": "鼠标贴近边缘时滚动战场",
}

var volume_sliders: Dictionary = {}
var option_buttons: Dictionary = {}
var status_label: Label
var _volume_labels: Dictionary = {}
var _prefs: Node
var _audio: Node
var _save_button: Button
var _leave_button: Button
var _closing := false
var _save_failed := false
var input_allowed: Callable

# Main owns battle pause/resume. This control only owns preferences and the
# modal surface, making it usable from the camp and from an active battle.
func configure(prefs: Node, audio: Node = null) -> void:
	if is_instance_valid(_prefs) and _prefs.has_signal("changed") and _prefs.is_connected("changed", _refresh):
		_prefs.disconnect("changed", _refresh)
	_prefs = prefs
	_audio = audio
	if is_instance_valid(_prefs) and _prefs.has_signal("changed"):
		_prefs.connect("changed", _refresh)
	if is_inside_tree(): _refresh()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = STYLE.make_theme()
	if _prefs == null: configure(get_node_or_null("/root/UserPrefs"), get_node_or_null("/root/GameAudio"))
	var veil := ColorRect.new()
	veil.color = Color(0.025, 0.055, 0.10, 0.85)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(630, 550)
	panel.add_theme_stylebox_override("panel", STYLE.box(STYLE.PAPER, 18, STYLE.GOLD))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var title := _label("远征设置", 30)
	title.add_theme_color_override("font_color", STYLE.NIGHT)
	content.add_child(title)
	var subtitle := _label("调整后立即生效，返回时保存。", 17)
	subtitle.add_theme_color_override("font_color", STYLE.MUTED)
	content.add_child(subtitle)
	content.add_child(HSeparator.new())
	for key: String in VOLUME_ROWS: _add_volume_row(content, key)
	content.add_child(HSeparator.new())
	for key: String in OPTION_ROWS: _add_option_row(content, key)
	status_label = _label("", 17)
	status_label.name = "SaveStatus"
	status_label.custom_minimum_size = Vector2(540, 60)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	_leave_button = Button.new()
	_leave_button.text = "暂时返回"
	_leave_button.tooltip_text = "当前调整保留到本次运行结束，下次启动仍使用上次保存的设置。"
	_leave_button.custom_minimum_size = Vector2(150, 44)
	_leave_button.pressed.connect(_leave_without_save)
	_leave_button.visible = false
	actions.add_child(_leave_button)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(space)
	_save_button = Button.new()
	_save_button.name = "SaveAndReturn"
	_save_button.text = "保存并返回"
	_save_button.custom_minimum_size = Vector2(180, 44)
	_save_button.add_theme_stylebox_override("normal", STYLE.button_box(STYLE.TEAL, 10))
	_save_button.add_theme_stylebox_override("hover", STYLE.button_box(STYLE.TEAL.lightened(0.08), 10, STYLE.GOLD))
	_save_button.add_theme_stylebox_override("pressed", STYLE.button_box(STYLE.TEAL.darkened(0.12), 10))
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_save_button.add_theme_color_override(color_name, STYLE.PAPER)
	_save_button.pressed.connect(close)
	actions.add_child(_save_button)
	_refresh()
	_save_button.grab_focus()

func _label(text: String, font_size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	if font_size >= 24:
		result.add_theme_font_override("font", STYLE.emphasis_font())
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _add_volume_row(content: VBoxContainer, key: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 42
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var title := _label(str(VOLUME_ROWS[key]), 20)
	title.custom_minimum_size.x = 96
	row.add_child(title)
	var slider := HSlider.new()
	slider.name = key.to_pascal_case()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(270, 28)
	slider.add_theme_stylebox_override("slider", STYLE.box(Color("c5cec9"), 6))
	slider.add_theme_stylebox_override("grabber_area", STYLE.box(STYLE.TEAL, 6))
	slider.add_theme_stylebox_override("grabber_area_highlight", STYLE.box(STYLE.GOLD, 6))
	slider.value_changed.connect(_volume_changed.bind(key))
	slider.drag_ended.connect(_volume_drag_ended)
	row.add_child(slider)
	volume_sliders[key] = slider
	var amount := _label("", 20)
	amount.custom_minimum_size.x = 62
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	_volume_labels[key] = amount

func _add_option_row(content: VBoxContainer, key: String) -> void:
	var toggle := CheckBox.new()
	toggle.name = key.to_pascal_case()
	toggle.text = str(OPTION_ROWS[key])
	toggle.custom_minimum_size.y = 38
	toggle.add_theme_color_override("font_color", STYLE.INK)
	toggle.add_theme_color_override("font_hover_color", STYLE.NIGHT)
	toggle.add_theme_color_override("font_pressed_color", STYLE.NIGHT)
	toggle.add_theme_stylebox_override("focus", STYLE.box(Color.TRANSPARENT, 8, STYLE.GOLD))
	toggle.toggled.connect(_option_changed.bind(key))
	content.add_child(toggle)
	option_buttons[key] = toggle

func _refresh() -> void:
	if not is_instance_valid(status_label): return
	var available := is_instance_valid(_prefs)
	var editable := available and bool(_prefs.call("can_save"))
	for key: String in volume_sliders:
		var amount := roundi(float(_prefs.call("get_value", key, 0.0)) * 100) if available else 0
		var slider: HSlider = volume_sliders[key]
		slider.set_value_no_signal(amount)
		slider.editable = editable
		_volume_labels[key].text = "%d%%" % amount
	for key: String in option_buttons:
		var toggle: CheckBox = option_buttons[key]
		toggle.set_pressed_no_signal(bool(_prefs.call("get_value", key, false)) if available else false)
		toggle.disabled = not editable
	var message := str(_prefs.get("error_message")) if available else "设置服务无法连接。"
	status_label.text = message if not message.is_empty() else "音量为 0 时静音。关闭设置后继续原来的游戏状态。"
	status_label.add_theme_color_override("font_color", Color("a74336") if not message.is_empty() else STYLE.MUTED)

func _volume_changed(value: float, key: String) -> void:
	if is_instance_valid(_prefs): _prefs.call("set_value", key, value / 100.0)
	_refresh()

func _option_changed(value: bool, key: String) -> void:
	if is_instance_valid(_prefs): _prefs.call("set_value", key, value)
	_click()
	_refresh()

func _volume_drag_ended(value_changed: bool) -> void:
	if value_changed: _click()

func _click() -> void:
	if is_instance_valid(_audio): _audio.call("play_cue", "click")

func _input(event: InputEvent) -> void:
	if not visible or _closing or not event is InputEventKey or not event.pressed or event.echo: return
	if input_allowed.is_valid() and not bool(input_allowed.call()): return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_handled()
		close()
	elif event.keycode == KEY_F11:
		get_viewport().set_input_handled()
		if is_instance_valid(_prefs): _prefs.call("set_value", "fullscreen", not bool(_prefs.call("get_value", "fullscreen")))
		_refresh()

func close() -> bool:
	if _closing: return true
	_click()
	if not is_instance_valid(_prefs) or not bool(_prefs.call("flush")):
		_save_failed = true
		_refresh()
		if is_instance_valid(_save_button): _save_button.text = "重试保存"
		if is_instance_valid(_leave_button): _leave_button.visible = true
		return false
	_finish_close()
	return true

func _leave_without_save() -> void:
	if not _save_failed: return
	_click()
	_finish_close()

func _finish_close() -> void:
	_closing = true
	hide()
	closed.emit()
	queue_free()
