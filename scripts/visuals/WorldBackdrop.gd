class_name WorldBackdrop
extends Node2D

var battle_mode := false
var chapter := 0
var clock := 0.0
var stars: Array[Vector3] = []
var world_width := 1280.0
var pulses: Array = []
var redraw_timer := 0.0

func configure_width(width: float, chapter_id: int = 1) -> void:
	world_width = maxf(1280.0, width)
	chapter = chapter_id
	stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42018
	for i in int(world_width / 1280.0 * 95):
		stars.append(Vector3(rng.randf_range(0, world_width), rng.randf_range(15, 360), rng.randf_range(0.7, 2)))
	pulses.clear()
	queue_redraw()

func add_pulse(center: Vector2) -> void:
	pulses.append({"center": center, "life": 0.8})

func _ready() -> void:
	configure_width(world_width, chapter)

func _process(delta: float) -> void:
	clock += delta
	for pulse: Dictionary in pulses.duplicate():
		pulse.life -= delta
		if pulse.life <= 0: pulses.erase(pulse)
	redraw_timer += delta
	if redraw_timer >= 1.0 / 30.0:
		redraw_timer = 0.0
		queue_redraw()

func _draw() -> void:
	for i in 72:
		var t := float(i) / 72.0
		draw_rect(Rect2(0, i * 10, world_width, 11), (Color("201c36") if chapter == 2 else Color("101d32")).lerp(Color("456772"), t * 0.88))
	for star in stars:
		draw_circle(Vector2(star.x, star.y), star.z, Color(0.8, 0.88, 0.86, 0.25 + 0.35 * abs(sin(clock * 0.3 + star.x))))
	draw_circle(Vector2(world_width - 230, 108), 43, Color("d1d7be"))
	draw_circle(Vector2(world_width - 213, 91), 40, Color("182a3e"))
	# Distant shards and layered cloud banks establish the broken-island world.
	for i in int(world_width / 218.0) + 2:
		var x := i * 218.0 - 35
		var y := 290.0 + sin(i * 2.7) * 42
		draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 130, y - 18), Vector2(x + 168, y + 12), Vector2(x + 70, y + 70)]), Color("254252"))
		draw_line(Vector2(x + 25, y + 1), Vector2(x + 141, y - 6), Color("47716d"), 4)
	for i in int(world_width / 87.0) + 3:
		var x := i * 87.0
		draw_circle(Vector2(x, 418 + sin(i * 1.3) * 20), 75, Color("355862"))
		draw_circle(Vector2(x + 16, 458), 84, Color("294c55"))
	draw_rect(Rect2(0, 507, world_width, 213), Color("223e45"))
	draw_line(Vector2(0, 509), Vector2(world_width, 509), Color("8aab8e"), 5)
	for i in int(world_width / 34.0) + 1:
		var x := float(i * 34)
		draw_line(Vector2(x, 518), Vector2(x + 22, 523 + sin(i) * 8), Color("43615d"), 2)
	# Mossy foreground islands frame the battlefield instead of covering the units.
	draw_colored_polygon(PackedVector2Array([Vector2(0, 546), Vector2(220, 565), Vector2(180, 650), Vector2(63, 697), Vector2(0, 674)]), Color("172f3a"))
	draw_colored_polygon(PackedVector2Array([Vector2(world_width - 280, 559), Vector2(world_width, 547), Vector2(world_width, 696), Vector2(world_width - 140, 657)]), Color("172f3a"))
	_draw_lighthouse(Vector2(100, 505), false)
	_draw_lighthouse(Vector2(world_width - 100, 505), true)
	for i in int(world_width / 480.0):
		var x := 282.0 + i * 480.0
		draw_line(Vector2(x, 506), Vector2(x, 447), Color("507879"), 3)
		draw_circle(Vector2(x, 445), 7, Color("e0ad62"))
		draw_circle(Vector2(x, 445), 17, Color(1, 0.74, 0.32, 0.08))
	if not battle_mode:
		draw_rect(Rect2(0, 0, world_width, 720), Color(0.03, 0.09, 0.13, 0.18))
	if chapter == 2:
		for i in int(world_width / 520.0):
			var at := Vector2(380 + i * 520, 355)
			draw_arc(at, 48, 0, TAU, 24, Color("8a775c"), 7)
			for spoke in 8:
				var direction := Vector2.from_angle(spoke * TAU / 8)
				draw_line(at + direction * 14, at + direction * 44, Color("79694f"), 5)
	for pulse: Dictionary in pulses:
		var progress := 1.0 - float(pulse.life) / 0.8
		draw_arc(pulse.center, 25 + progress * 180, 0, TAU, 48, Color(0.4, 1, 0.85, float(pulse.life)), 4)

func _draw_lighthouse(origin: Vector2, hostile: bool) -> void:
	var wall := Color("554e66") if hostile else Color("b4b8a5")
	var light := Color("b67ad8") if hostile else Color("edbe69")
	draw_circle(origin + Vector2(0, -100), 65, Color(light, 0.07))
	draw_colored_polygon(PackedVector2Array([origin + Vector2(-43, 0), origin + Vector2(-30, -105), origin + Vector2(30, -105), origin + Vector2(43, 0)]), wall)
	draw_rect(Rect2(origin + Vector2(-40, -123), Vector2(80, 22)), wall.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([origin + Vector2(-46, -126), origin + Vector2(0, -163), origin + Vector2(46, -126)]), Color("243c4b") if not hostile else Color("362e4c"))
	draw_rect(Rect2(origin + Vector2(-14, -123), Vector2(28, 25)), light)
	draw_rect(Rect2(origin + Vector2(-13, -50), Vector2(26, 50)), wall.darkened(0.55))
	for y in [-84, -64]:
		draw_line(origin + Vector2(-27, y), origin + Vector2(25, y), wall.darkened(0.2), 2)
	draw_line(origin + Vector2(-46, 0), origin + Vector2(46, 0), Color("7b9e87"), 6)
