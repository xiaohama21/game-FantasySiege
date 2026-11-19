extends Control

## Static, locally rendered Spine artwork. This control owns no animation or viewport.
static var _textures: Dictionary = {}
var unit_id := ""
var emphasized := false
var has_art := false
var image: TextureRect

func configure(id: String, highlighted: bool = false) -> void:
	unit_id = id
	emphasized = highlighted
	name = "Portrait_" + id if not id.is_empty() else "PortraitStage"
	set_meta("portrait_unit_id", id)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	if not is_instance_valid(image):
		image = TextureRect.new()
		image.name = "Artwork"
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.offset_left = 3
		image.offset_right = -3
		image.offset_top = 3
		image.offset_bottom = -7
		add_child(image)
	var path := "res://assets/portraits/" + id + ".png"
	if not id.is_empty() and not _textures.has(path) and ResourceLoader.exists(path):
		var texture: Texture2D = load(path)
		if texture != null: _textures[path] = texture
	image.texture = _textures.get(path)
	has_art = image.texture != null
	queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(SiegeStyle.box(Color("203c4b"), 9, Color("c59e62") if emphasized else Color("506e72")), rect)
	# Quiet cold atmosphere and a warm upper lamp echo the battlefield's lighting.
	for band in 8:
		var amount := float(band) / 8.0
		draw_rect(Rect2(3, 3 + amount * (size.y - 6), maxf(0, size.x - 6), maxf(0, (size.y - 6) / 8.0 + 1)), Color("294957").lerp(Color("162d3a"), amount))
	var center := Vector2(size.x * 0.5, size.y * (0.925 if unit_id.is_empty() else 0.87))
	draw_set_transform(center, 0.0, Vector2(1.0, 0.23))
	draw_circle(Vector2.ZERO, size.x * 0.36, Color(0.015, 0.045, 0.065, 0.6))
	draw_arc(Vector2.ZERO, size.x * 0.37, 0, TAU, 32, Color(0.49, 0.71, 0.66, 0.45), 1.0)
	draw_set_transform(Vector2.ZERO)
	draw_line(Vector2(size.x * 0.18, 7), Vector2(size.x * 0.82, 7), Color(0.88, 0.73, 0.45, 0.4), 1.0)
	if not has_art and not unit_id.is_empty():
		# Dashed missing-art outline stays visibly distinct from a validated portrait.
		var at := Vector2(size.x * 0.5, size.y * 0.48)
		var radius := minf(size.x * 0.28, size.y * 0.24)
		for segment in 12:
			var angle := float(segment) * TAU / 12.0
			draw_arc(at, radius, angle, angle + TAU / 19.0, 3, Color("8ca5a4"), 1.4)
		draw_circle(at + Vector2(0, -radius * 0.22), radius * 0.24, Color("677f85"))
		draw_arc(at + Vector2(0, radius * 0.55), radius * 0.49, PI, TAU, 12, Color("677f85"), 3.0)
