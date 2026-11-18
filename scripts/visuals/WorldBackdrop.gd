class_name WorldBackdrop
extends Node2D

var battle_mode := false
var chapter := 0
var clock := 0.0
var stars: Array[Vector3] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42018
	for i in 95:
		stars.append(Vector3(rng.randf_range(0, 1280), rng.randf_range(15, 360), rng.randf_range(0.7, 2)))
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	for i in 72:
		var t := float(i) / 72.0
		draw_rect(Rect2(0, i * 10, 1280, 11), Color("101d32").lerp(Color("456772"), t * 0.88))
	for star in stars:
		draw_circle(Vector2(star.x, star.y), star.z, Color(0.8, 0.88, 0.86, 0.25 + 0.35 * abs(sin(clock * 0.3 + star.x))))
	draw_circle(Vector2(1050, 108), 43, Color("d1d7be"))
	draw_circle(Vector2(1067, 91), 40, Color("182a3e"))
	# Distant shards and layered cloud banks establish the broken-island world.
	for i in 7:
		var x := i * 218.0 - 35
		var y := 290.0 + sin(i * 2.7) * 42
		draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 130, y - 18), Vector2(x + 168, y + 12), Vector2(x + 70, y + 70)]), Color("254252"))
		draw_line(Vector2(x + 25, y + 1), Vector2(x + 141, y - 6), Color("47716d"), 4)
	for i in 18:
		var x := i * 87.0
		draw_circle(Vector2(x, 418 + sin(i * 1.3) * 20), 75, Color("355862"))
		draw_circle(Vector2(x + 16, 458), 84, Color("294c55"))
	draw_rect(Rect2(0, 507, 1280, 213), Color("223e45"))
	draw_line(Vector2(0, 509), Vector2(1280, 509), Color("8aab8e"), 5)
	for i in 40:
		var x := float(i * 34)
		draw_line(Vector2(x, 518), Vector2(x + 22, 523 + sin(i) * 8), Color("43615d"), 2)
	# Mossy foreground islands frame the battlefield instead of covering the units.
	draw_colored_polygon(PackedVector2Array([Vector2(0, 546), Vector2(220, 565), Vector2(180, 650), Vector2(63, 697), Vector2(0, 674)]), Color("172f3a"))
	draw_colored_polygon(PackedVector2Array([Vector2(1000, 559), Vector2(1280, 547), Vector2(1280, 696), Vector2(1140, 657)]), Color("172f3a"))
	_draw_lighthouse(Vector2(100, 505), false)
	_draw_lighthouse(Vector2(1180, 505), true)
	for x in [282, 992]:
		draw_line(Vector2(x, 506), Vector2(x, 447), Color("507879"), 3)
		draw_circle(Vector2(x, 445), 7, Color("e0ad62"))
		draw_circle(Vector2(x, 445), 17, Color(1, 0.74, 0.32, 0.08))
	if not battle_mode:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.09, 0.13, 0.18))

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
