class_name WorldBackdrop
extends Node2D

## Static illustrated layers are retained by the canvas. Only faint star light
## and combat pulses redraw, so the detailed environment has no animation cost.
const ENVIRONMENT_ROOT := "res://assets/environments/"
static var _textures: Dictionary = {}

var battle_mode := false
var chapter := 0
var clock := 0.0
var stars: Array[Vector3] = []
var world_width := 1280.0
var pulses: Array = []
var redraw_timer := 0.0
var _landscape: Sprite2D
var _home_beacon: Sprite2D
var _rift_beacon: Sprite2D

func configure_width(width: float, chapter_id: int = 1) -> void:
	world_width = maxf(1280.0, width)
	chapter = chapter_id
	stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42018
	for i in int(world_width / 1280.0 * 55):
		stars.append(Vector3(rng.randf_range(0, world_width), rng.randf_range(18, 343), rng.randf_range(0.6, 1.5)))
	pulses.clear()
	_apply_environment()
	queue_redraw()

func add_pulse(center: Vector2) -> void:
	pulses.append({"center": center, "life": 0.8})
	queue_redraw()

func _ready() -> void:
	configure_width(world_width, chapter)

func _texture(filename: String) -> Texture2D:
	var path := ENVIRONMENT_ROOT + filename
	if not _textures.has(path):
		if ResourceLoader.exists(path): _textures[path] = load(path) as Texture2D
	return _textures.get(path) as Texture2D

func _make_layer(layer_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = layer_name
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# The scene's dynamic stars and pulses stay above the static illustration.
	sprite.show_behind_parent = true
	add_child(sprite)
	return sprite

func _apply_environment() -> void:
	if not is_inside_tree(): return
	if not is_instance_valid(_landscape): _landscape = _make_layer("IllustratedLandscape")
	var background := "camp-route.svg" if not battle_mode else "brass-remnants.svg" if chapter == 2 else "rift-isles.svg"
	_landscape.texture = _texture(background)
	if _landscape.texture != null:
		_landscape.scale = Vector2(world_width / float(_landscape.texture.get_width()), 1.0)
	if not is_instance_valid(_home_beacon): _home_beacon = _make_layer("StarLampBeacon")
	if not is_instance_valid(_rift_beacon): _rift_beacon = _make_layer("RiftBeacon")
	_home_beacon.texture = _texture("lighthouse-camp.svg")
	_rift_beacon.texture = _texture("lighthouse-rift.svg")
	_home_beacon.scale = Vector2(0.83, 0.83)
	_rift_beacon.scale = Vector2(0.83, 0.83)
	# SVG floor is y220; the corresponding world floor remains y510.
	_home_beacon.position = Vector2(100, 510) - Vector2(90, 220) * 0.83
	_rift_beacon.position = Vector2(world_width - 100, 510) - Vector2(90, 220) * 0.83
	_rift_beacon.visible = battle_mode
	# The camp retains the friendly landmark and its route artwork rather than
	# showing a hostile endpoint in the player's preparation area.
	_home_beacon.visible = true

func _process(delta: float) -> void:
	clock += delta
	for index in range(pulses.size() - 1, -1, -1):
		pulses[index].life -= delta
		if pulses[index].life <= 0: pulses.remove_at(index)
	redraw_timer += delta
	if redraw_timer >= 1.0 / 30.0:
		redraw_timer = 0.0
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_landscape) or _landscape.texture == null:
		# A missing import stays a clear plain background; native resource and
		# package validation must catch the absent artwork before delivery.
		draw_rect(Rect2(0, 0, world_width, 720), Color("15293a"))
	for star in stars:
		draw_circle(Vector2(star.x, star.y), star.z, Color(0.8, 0.88, 0.86, 0.08 + 0.17 * abs(sin(clock * 0.3 + star.x))))
	for pulse: Dictionary in pulses:
		var progress := 1.0 - float(pulse.life) / 0.8
		draw_arc(pulse.center, 25 + progress * 180, 0, TAU, 48, Color(0.4, 1, 0.85, float(pulse.life)), 4)
