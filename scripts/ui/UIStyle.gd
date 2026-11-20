class_name SiegeStyle
extends RefCounted

const INK := Color("293b48")
const PAPER := Color("f3ecdc")
const MUTED := Color("7d898c")
const GOLD := Color("d49e4a")
const TEAL := Color("3e9189")
const NIGHT := Color("132536")
const FONT_FAMILY := "Noto Sans SC"
const FONT_FILE := "res://assets/fonts/NotoSansSC.ttf"
const BODY_WEIGHT := 400.0
const EMPHASIS_WEIGHT := 600.0

static func body_font() -> Font:
	return load("res://resources/ui_font_body.tres") as Font

static func emphasis_font() -> Font:
	return load("res://resources/ui_font_emphasis.tres") as Font

static func box(color: Color, radius: int = 12, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.border_color = border
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func button_box(color: Color, radius: int = 12, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := box(color, radius, border)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = body_font()
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", NIGHT)
	result.set_color("font_pressed_color", "Button", NIGHT)
	for type: String in ["Button", "CheckButton", "CheckBox", "OptionButton"]:
		result.set_font("font", type, emphasis_font())
		result.set_color("font_focus_color", type, INK)
	result.set_color("font_disabled_color", "Button", Color("969e9c"))
	result.set_stylebox("normal", "Button", button_box(PAPER, 10, Color("d5cfbe")))
	result.set_stylebox("hover", "Button", button_box(Color("fffaed"), 10, GOLD))
	result.set_stylebox("pressed", "Button", button_box(Color("dcd8c6"), 10, TEAL))
	result.set_stylebox("disabled", "Button", button_box(Color("d4d4ca"), 10))
	result.set_stylebox("focus", "Button", button_box(Color.TRANSPARENT, 10, GOLD))
	result.set_stylebox("panel", "Panel", box(PAPER, 16))
	return result
