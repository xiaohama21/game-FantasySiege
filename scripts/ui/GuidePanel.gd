class_name ExpeditionGuide
extends Control

signal closed
var page := 0
var starting := false
var story := ""
var heading: Label
var body: Label
var counter: Label
var previous: Button
var next: Button
var closing := false
var input_allowed: Callable
const TITLES := ["点亮第一支队伍", "巡视更远的战场", "抓住反攻的窗口"]
const TEXTS := [
	"能量会自动恢复。先召唤低费前排，再补远程伙伴。\n英魂会自行前进与交战，同一英魂可以重复召唤。\n点击下方卡片，或按 1—8 召唤对应位置的英魂。",
	"战场有两屏宽。按住左键拖动，或按 ← / → 巡视两侧；鼠标移到边缘也能移动。\n点击“跟随战线”回到交战处。空格可暂停观察，再按继续；暂停时不能召唤或释放脉冲。",
	"按 P 释放星灯脉冲：消耗80能量，冷却35秒。它震击最前敌军一带，晕眩并打断尚未命中的攻击。\n重击预警时留好能量，保护前排与远程。摧毁右方基地即可获胜；胜利后用星砂训练和整备编队。"
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 250
	var shade := ColorRect.new()
	shade.size = Vector2(1280, 720)
	shade.color = Color(0.03, 0.08, 0.13, 0.82)
	add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(330, 170)
	panel.size = Vector2(620, 370)
	panel.add_theme_stylebox_override("panel", SiegeStyle.box(SiegeStyle.PAPER, 18, SiegeStyle.GOLD))
	add_child(panel)
	heading = _label(panel, "", Rect2(28, 22, 563, 44), 28, SiegeStyle.TEAL)
	counter = _label(panel, "", Rect2(28, 65, 562, 25), 15, SiegeStyle.MUTED)
	body = _label(panel, "", Rect2(28, 101, 564, 153), 18, SiegeStyle.INK)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var narrative := _label(panel, story if not story.is_empty() else "循光而行，重燃诸岛。", Rect2(28, 259, 564, 43), 15, SiegeStyle.MUTED)
	narrative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	previous = _button(panel, "上一页", Rect2(28, 315, 145, 39), _step.bind(-1))
	_button(panel, "跳过", Rect2(235, 315, 145, 39), close)
	next = _button(panel, "", Rect2(427, 315, 165, 39), _next)
	refresh()

func _label(parent: Node, value: String, rect: Rect2, size_at: int, color: Color) -> Label:
	var label := Label.new()
	label.clip_text = true
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size_at)
	if size_at >= 24:
		label.add_theme_font_override("font", SiegeStyle.emphasis_font())
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text_at: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.clip_text = true
	button.text = text_at
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func refresh() -> void:
	heading.text = str(TITLES[page])
	body.text = str(TEXTS[page])
	counter.text = "操作指南  %d / 3" % (page + 1)
	previous.disabled = page == 0
	next.text = "开始远征" if page == 2 and starting else "关闭指南" if page == 2 else "下一页"

func _step(direction: int) -> void:
	if not _can_interact(): return
	page = clampi(page + direction, 0, 2)
	refresh()

func _next() -> void:
	if not _can_interact(): return
	if page < 2: _step(1)
	else: close()

func close() -> void:
	if not _can_interact(): return
	closing = true
	closed.emit()
	queue_free()

func _can_interact() -> bool:
	return not closing and (not input_allowed.is_valid() or bool(input_allowed.call()))
