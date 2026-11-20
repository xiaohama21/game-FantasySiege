class_name SiegeStatBadge
extends PanelContainer

var value_label: Label
var caption_label: Label
var image: TextureRect

func configure(icon: String, caption: String, value: String, tint: Color = SiegeStyle.TEAL) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(112, 52)
	var style := SiegeStyle.box(Color("e7e7dc"), 9)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 7)
	add_child(row)
	image = TextureRect.new()
	image.name = "Icon"
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.custom_minimum_size = Vector2(26, 26)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image.texture = load("res://assets/ui/icons/" + icon + ".svg")
	row.add_child(image)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	caption_label = Label.new()
	caption_label.name = "Caption"
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.text = caption
	caption_label.add_theme_font_size_override("font_size", 12)
	caption_label.add_theme_color_override("font_color", SiegeStyle.MUTED)
	text.add_child(caption_label)
	value_label = Label.new()
	value_label.name = "Value"
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.text = value
	value_label.add_theme_font_override("font", SiegeStyle.emphasis_font())
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", tint)
	text.add_child(value_label)
