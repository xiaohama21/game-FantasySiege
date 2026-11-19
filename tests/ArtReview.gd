extends SceneTree

## Real Main composition in a hidden offscreen viewport. Never measures performance.
const SIZE := Vector2i(1280, 720)
const DIRECTORY := "res://tests/.user/art_review"
const OUTPUT := "res://reports/runtime"
var app
var viewport: SubViewport
var failures: Array[String] = []
var checks := 0
var captures: Array[Dictionary] = []
var portrait_records: Dictionary = {}
var text_records: Array[Dictionary] = []
var text_labels_audited := 0
var native_viewers := 0
var native_battle_instances := 0
var project_sha256 := ""

func _initialize() -> void:
	root.mode = Window.MODE_MINIMIZED
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(descendants(child))
	return result

func audit_portraits(context: String) -> void:
	for node: Node in descendants(app.screen):
		if not node.has_meta("portrait_unit_id"): continue
		var id := str(node.get_meta("portrait_unit_id"))
		if id.is_empty(): continue
		check(str(node.name).begins_with("Portrait_"), context + ": stable portrait node " + id)
		check(node is Control and node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, context + ": artwork cannot consume input " + id)
		var image: TextureRect = node.get("image")
		check(is_instance_valid(image) and image.mouse_filter == Control.MOUSE_FILTER_IGNORE and image.focus_mode == Control.FOCUS_NONE, context + ": image cannot consume input " + id)
		check(node.get("has_art") == true and is_instance_valid(image) and image.texture != null, context + ": real portrait loaded " + id)
		if not is_instance_valid(image) or image.texture == null: continue
		var expected := "res://assets/portraits/" + id + ".png"
		check(image.texture.resource_path == expected, context + ": portrait texture identity " + id)
		if portrait_records.has(id): continue
		var source := Image.load_from_file(expected)
		var displayed := image.texture.get_image()
		check(source != null and not source.is_empty() and source.get_used_rect().size != Vector2i.ZERO, context + ": source artwork is nonempty " + id)
		if source == null or source.is_empty() or displayed == null: continue
		source.convert(Image.FORMAT_RGBA8)
		displayed.convert(Image.FORMAT_RGBA8)
		check(visible_pixels_match(source, displayed), context + ": visible character pixels and alpha match source PNG " + id)
		portrait_records[id] = {"unit_id": id, "visual_id": str(Catalog.unit(id).get("visual_id", "")), "path": expected, "sha256": FileAccess.get_sha256(expected), "size": [source.get_width(), source.get_height()], "nonempty": source.get_used_rect().size != Vector2i.ZERO}

func visible_pixels_match(source: Image, displayed: Image) -> bool:
	if source.get_size() != displayed.get_size(): return false
	# Match the default Godot texture import's documented alpha-border repair.
	# This alters fringe RGB, including semitransparent edges, but not alpha.
	source.fix_alpha_edges()
	var source_bytes := source.get_data()
	var displayed_bytes := displayed.get_data()
	if source_bytes == displayed_bytes: return true
	# Godot's alpha-edge import fills RGB in fully transparent texels to avoid
	# filtered dark fringes. Alpha and all visible artwork must remain identical.
	for offset in range(0, source_bytes.size(), 4):
		if source_bytes[offset + 3] != displayed_bytes[offset + 3]: return false
		if source_bytes[offset + 3] == 0: continue
		for channel in 3:
			if source_bytes[offset + channel] != displayed_bytes[offset + channel]: return false
	return true

func audit_text(context: String) -> void:
	for node: Node in descendants(app.screen):
		if not node is Label or not canvas_visible(node) or node.text.is_empty(): continue
		var label := node as Label
		text_labels_audited += 1
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var lines := label.get_line_count()
		var measured_height := font.get_height(font_size) * lines + label.get_theme_constant("line_spacing") * maxi(0, lines - 1)
		var measured_width := 0.0
		for line: String in label.text.split("\n"):
			measured_width = maxf(measured_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var width_ok := label.autowrap_mode != TextServer.AUTOWRAP_OFF or measured_width <= label.size.x + 1.0
		var height_ok := measured_height <= label.size.y + 2.0
		check(width_ok and height_ok, context + ": readable label without clipped text: " + label.text.replace("\n", " / "))
		if not width_ok or not height_ok:
			text_records.append({"context": context, "text": label.text, "font_size": font_size, "line_count": lines, "measured_width": measured_width, "measured_height": measured_height, "allocated_size": [label.size.x, label.size.y]})

func canvas_visible(node: Node) -> bool:
	# A hidden host Window must not suppress audits of its actively rendered SubViewport.
	var current := node
	while current != null and not current is Viewport:
		if current is CanvasItem and not current.visible: return false
		current = current.get_parent()
	return true

func capture(filename: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	check(root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED, filename + ": actual host window stays minimized")
	audit_portraits(filename)
	audit_text(filename)
	var picture := viewport.get_texture().get_image()
	check(picture != null and picture.get_size() == SIZE, filename + ": full-size offscreen Main image")
	if picture == null: return
	var colors: Dictionary = {}
	for y in range(16, SIZE.y, 32):
		for x in range(16, SIZE.x, 32): colors[picture.get_pixel(x, y).to_html()] = true
	check(colors.size() >= 12, filename + ": composition is rendered rather than an empty surface")
	var path := OUTPUT + "/" + filename + ".png"
	check(picture.save_png(path) == OK, filename + ": save real Main composition")
	captures.append({"name": filename, "path": path, "sha256": FileAccess.get_sha256(path), "sampled_colors": colors.size(), "size": [SIZE.x, SIZE.y], "tab": app.tab, "stage": app.active_stage if is_instance_valid(app.battle) else "", "view_x": app.view_x})

func scroll_to_bottom() -> void:
	for node: Node in descendants(app.screen):
		if node is ScrollContainer:
			node.scroll_vertical = int(node.get_v_scroll_bar().max_value)
			return

func setup_battle(stage_id: String) -> void:
	app.start_stage(stage_id)
	check(is_instance_valid(app.battle), "actual Main starts art fixture battle " + stage_id)
	if not is_instance_valid(app.battle): return
	# Visual fixture uses actual energy recovery, summon requests and fixed-step combat.
	# No fabricated actors, altered HP, free energy, progression claim or performance timing.
	app.set_process(false)
	app.paused = true
	for step in 60:
		for id: String in ["iron_guard", "ember_archer", "rune_medic"]: app.battle.try_summon(id)
		app.battle.advance(0.5)
		app._process(0.5)
		if app.battle.get_snapshot().outcome != "running": break
	app.paused = true
	app.pause_button.text = "继续"
	app.battle.set_visual_playback(0.0)
	app._update_hud()
	if is_instance_valid(app.intro_panel): app.intro_panel.visible = false
	app.follow_frontline = false
	var native_here := 0
	for unit: Dictionary in app.battle.units:
		if not bool(unit.get("alive", false)): continue
		check(is_instance_valid(unit.get("visual")) and unit.visual.using_spine(), "actual battle uses native character " + str(unit.id))
		native_battle_instances += 1
		native_here += 1
	check(native_here > 0, "battle composition contains actual living Spine models " + stage_id)
	app._set_view_position(0)

func run() -> void:
	project_sha256 = FileAccess.get_sha256("res://project.godot")
	if DisplayServer.get_name() == "headless":
		check(false, "ArtReview requires a real renderer for offscreen images; omit --headless")
		await finish()
		return
	check(not RenderingServer.get_video_adapter_name().is_empty(), "real renderer available for offscreen composition")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var profile = root.get_node("ProfileStore")
	var prefs = root.get_node("UserPrefs")
	for filename: String in ["profile.json", "preferences.json"]:
		for suffix: String in ["", ".bak", ".tmp"]:
			var path: String = DIRECTORY + "/" + filename + suffix
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	prefs.configure_path(DIRECTORY + "/preferences.json")
	prefs.set_value("master_volume", 0.0)
	prefs.set_value("tutorial_seen", true)
	prefs.set_value("edge_scroll", false)
	check(prefs.flush(), "write isolated silent art preferences")
	# configure_path applies window preferences; hide it again before any rendering awaits.
	root.mode = Window.MODE_MINIMIZED
	profile.configure_path(DIRECTORY + "/profile.json")
	profile.load_profile()
	var fixture: Dictionary = profile.data.duplicate(true)
	fixture.owned = Catalog.playable_roster()
	fixture.cleared = []
	for stage: Dictionary in Catalog.stages(): fixture.cleared.append(str(stage.id))
	for id: String in fixture.owned: fixture.levels[id] = 1
	check(profile._commit(fixture), "persist isolated all-unlocked visual fixture")
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	app = load("res://scenes/Main.tscn").instantiate()
	viewport.add_child(app)
	await capture("art_camp")
	for id: String in Catalog.playable_roster():
		app._select_hero(id)
		await capture("art_hero_" + id)
	check(portrait_records.size() == 12, "all twelve character PNGs displayed and audited")
	scroll_to_bottom()
	await capture("art_hero_collection_lower")
	app._select_study("guanyu")
	await capture("art_study_locked")
	var study_fixture: Dictionary = fixture.duplicate(true)
	study_fixture.cleared = []
	study_fixture.owned = Catalog.initial_roster()
	check(profile._commit(study_fixture), "save isolated unowned study art fixture")
	app._select_study("spirit_beast")
	await capture("art_study_unowned")
	study_fixture = fixture.duplicate(true)
	study_fixture.credits = 5000
	for id: String in study_fixture.owned: study_fixture.levels[id] = 3
	check(profile._commit(study_fixture), "save isolated eligible study art fixture")
	app._select_study("guanyu")
	await capture("art_study_ready")
	app._unlock_study("guanyu")
	await capture("art_study_base")
	app._set_study_route("guanyu", "sweep")
	await capture("art_study_sweep")
	app._select_hero("guanyu")
	await capture("art_hero_studied")
	for entry: Array in [["rune_medic", "beacon", "art_study_heal"], ["rivet_gunner", "siege", "art_study_siege"], ["moon_mage", "freeze", "art_study_slow"]]:
		app._select_study(str(entry[0]))
		app._unlock_study(str(entry[0]))
		app._set_study_route(str(entry[0]), str(entry[1]))
		await capture(str(entry[2]))
	app.selected_visual = str(Catalog.unit("rune_medic").visual_id)
	app._gallery_category("heroes")
	await capture("art_gallery_studied")
	var studied_gallery: Dictionary = app._hero_calculation("rune_medic")
	for panel: Node in descendants(app.screen):
		if panel.get_meta("unit_id", "") == "rune_medic": check(panel.get_meta("unit_stats", {}) == studied_gallery, "actual studied gallery uses the same central final values")
	app._open_briefing("stage_08")
	await capture("art_briefing_studied")
	check(profile._commit(fixture), "restore original base-route art/battle fixture")
	for stage: Dictionary in Catalog.stages():
		app._open_briefing(str(stage.id))
		check(app.tab == "敌情" and app.selected_briefing == str(stage.id), "real Main exposes the requested briefing " + str(stage.id))
		await capture("art_briefing_" + str(stage.id))
		for node: Node in descendants(app.screen):
			if node is ScrollContainer: node.scroll_vertical = int(node.get_v_scroll_bar().max_value)
		await capture("art_briefing_" + str(stage.id) + "_lower")
	var locked_briefing_fixture: Dictionary = fixture.duplicate(true)
	locked_briefing_fixture.cleared = []
	locked_briefing_fixture.owned = Catalog.initial_roster()
	locked_briefing_fixture.roster = ["iron_guard"]
	check(profile._commit(locked_briefing_fixture), "save isolated locked briefing visual fixture")
	app._open_briefing("stage_08")
	await capture("art_briefing_locked")
	check(profile._commit(fixture), "restore base-route fixture after read-only briefing art")
	app.show_home("编队")
	await capture("art_squad")
	scroll_to_bottom()
	await capture("art_squad_lower")
	for chapter: int in [1, 2]:
		setup_battle("stage_01" if chapter == 1 else "stage_05")
		if not is_instance_valid(app.battle): continue
		await capture("art_chapter_%d_left" % chapter)
		app._set_view_position(app.view_max)
		await capture("art_chapter_%d_right" % chapter)
	app.show_home("图鉴")
	app.set_process(true)
	await process_frame
	check(is_instance_valid(app.viewer) and app.viewer.using_spine(), "actual hero gallery preview uses native Spine")
	if is_instance_valid(app.viewer) and app.viewer.using_spine(): native_viewers += 1
	await capture("art_gallery_hero")
	app.selected_visual = "d69_094"
	app._gallery_category("enemies")
	await process_frame
	check(is_instance_valid(app.viewer) and app.viewer.using_spine(), "actual boss gallery preview uses native Spine")
	if is_instance_valid(app.viewer) and app.viewer.using_spine(): native_viewers += 1
	await capture("art_gallery_boss")
	check(FileAccess.get_sha256("res://project.godot") == project_sha256, "project configuration remains unchanged throughout art run")
	check(text_labels_audited > 0, "real Main labels received readability audits")
	await finish()

func finish() -> void:
	if is_instance_valid(app):
		check(app._stop_battle(), "art fixture cleans up actual Main battle")
		viewport.remove_child(app)
		app.queue_free()
		app = null
	if is_instance_valid(viewport):
		viewport.queue_free()
		viewport = null
	await process_frame
	var audio = root.get_node("GameAudio")
	await audio.shutdown()
	check(audio.shutdown_clean, "offscreen art run drains actual audio playback before exit")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")), "project_sha256": project_sha256, "units_sha256": FileAccess.get_sha256("res://resources/units.json"), "visuals_sha256": FileAccess.get_sha256("res://resources/visuals.json"), "stages_sha256": FileAccess.get_sha256("res://resources/stages.json"), "studies_sha256": FileAccess.get_sha256("res://resources/studies.json"), "briefings_sha256": FileAccess.get_sha256("res://resources/briefings.json"), "briefing_script_sha256": FileAccess.get_sha256("res://scripts/core/BattleBriefing.gd"), "main_sha256": FileAccess.get_sha256("res://scripts/ui/Main.gd"), "stat_badge_sha256": FileAccess.get_sha256("res://scripts/ui/StatBadge.gd"), "scope": "Hidden offscreen SubViewport rendering of actual Main.tscn: character portraits, readable UI, camp, squads, eight battle briefings including lower scroll/locked/studied states, summon cards, both chapter edges and native gallery. Uses isolated presentation fixtures; does not verify progression, foreground interaction, frame rate or performance.", "isolation": DIRECTORY, "root_visible": root.visible, "root_window_mode": root.mode, "root_focused": root.has_focus(), "rendering_adapter": RenderingServer.get_video_adapter_name(), "screenshots": captures.size(), "captures": captures, "portrait_count": portrait_records.size(), "portraits": portrait_records.values(), "text_labels_audited": text_labels_audited, "text_overflows": text_records, "native_gallery_previews": native_viewers, "native_battle_instances_audited": native_battle_instances, "audio_shutdown_clean": audio.shutdown_clean}
	var file := FileAccess.open("res://reports/art_review_local.json", FileAccess.WRITE)
	if file == null:
		push_error("cannot write offscreen art review report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ART_REVIEW_COMPLETE " + JSON.stringify(report))
	quit(0 if report.passed else 1)
