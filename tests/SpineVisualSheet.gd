extends SceneTree

const Actor = preload("res://scripts/visuals/SpineActor.gd")
const IDS := ["097", "312", "314", "072", "163", "084", "018", "168", "253", "254", "046", "285", "271"]
var actors: Array = []

func _initialize() -> void:
	call_deferred("_run")

func label(text: String, point: Vector2, size: int = 18) -> void:
	var item := Label.new()
	item.text = text
	item.position = point
	item.add_theme_font_size_override("font_size", size)
	root.add_child(item)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var title := Label.new()
	title.position = Vector2(32, 28)
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	for index in IDS.size():
		var actor := Actor.new()
		root.add_child(actor)
		actor.position = Vector2(94 + (index % 7) * 179, 322 + (index / 7) * 255)
		actor.configure("d69_" + IDS[index], 1)
		actors.append(actor)
		label("D69 " + IDS[index], actor.position + Vector2(-46, 20))
	label("Native Spine / local research / model source and recipe QA", Vector2(32, 675), 17)
	var folder := "res://reports/spine_visuals"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for recipe in [["idle",1,0.25], ["idle",-1,0.25], ["move",1,0.25], ["attack",1,0.3], ["skill",1,0.4], ["hurt",1,0.12], ["death",1,0.65]]:
		var state: String = recipe[0]
		var facing: int = recipe[1]
		title.text = "FANTASY SIEGE   /   %s   /   facing %s" % [state.to_upper(), "RIGHT" if facing == 1 else "LEFT"]
		for index in actors.size():
			actors[index].configure("d69_" + IDS[index], facing)
			actors[index].play_state(state)
		await create_timer(float(recipe[2])).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [folder,state,"right" if facing == 1 else "left"]
		screenshot.save_png(path)
		print("SAVED ",path)
	print("SPINE_VISUAL_SHEET_COMPLETE")
	quit()
