class_name SiegeStyle
extends RefCounted

const INK := Color("293b48")
const PAPER := Color("f3ecdc")
const MUTED := Color("7d898c")
const GOLD := Color("d49e4a")
const TEAL := Color("3e9189")
const NIGHT := Color("132536")

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

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = load("res://assets/fonts/ZCOOL-Kuaile.ttf")
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", NIGHT)
	result.set_color("font_pressed_color", "Button", NIGHT)
	for type: String in ["Button", "CheckButton", "CheckBox", "OptionButton"]:
		result.set_color("font_focus_color", type, INK)
	result.set_color("font_disabled_color", "Button", Color("969e9c"))
	result.set_stylebox("normal", "Button", box(PAPER, 10, Color("d5cfbe")))
	result.set_stylebox("hover", "Button", box(Color("fffaed"), 10, GOLD))
	result.set_stylebox("pressed", "Button", box(Color("dcd8c6"), 10, TEAL))
	result.set_stylebox("disabled", "Button", box(Color("d4d4ca"), 10))
	result.set_stylebox("focus", "Button", box(Color.TRANSPARENT, 10, GOLD))
	result.set_stylebox("panel", "Panel", box(PAPER, 16))
	return result
