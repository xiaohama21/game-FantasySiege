extends SceneTree

## Real Main composition in a hidden offscreen viewport. Never measures performance.
const QA_CONTEXT = preload("res://scripts/core/QAStartupContext.gd")
const SIZE := Vector2i(1280, 720)
const DIRECTORY := "res://tests/.user/art_review"
const OUTPUT := "res://reports/runtime"
const FONT_FILE := "res://assets/fonts/NotoSansSC.ttf"
const FONT_MANIFEST := "res://assets/fonts/manifest.json"
const REQUIRED_FONT_CHARACTERS := "0123456789力量敏捷智力生命伤害护甲魔抗射程召唤冷却星砂训练研修保存敌情首领→×"
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
var settings_panel_sha256 := ""
var font_context: Dictionary = {}
var font_aliases: Array[String] = []
var font_family := ""
var font_engine_families: Dictionary = {}
var font_weights: Dictionary = {}
var font_engine_weights: Dictionary = {}
var font_engine_coordinates: Dictionary = {}
var font_contract_passed := false
var font_glyph_characters: Dictionary = {}
var font_glyph_cache: Dictionary = {}
var font_glyph_missing: Array[String] = []
var settings_navigation: Dictionary = {}
var background_first_invalid_sample: Dictionary = {}
var background_started_usec := 0
var background_monitor_started := false
var background_frame_samples := 0
var background_capture_attempts := 0
var background_host_valid_captures := 0

func font_input_context() -> Dictionary:
	return {"ui_style_sha256": FileAccess.get_sha256("res://scripts/ui/UIStyle.gd"), "font_manifest_sha256": FileAccess.get_sha256(FONT_MANIFEST), "font_binary_sha256": FileAccess.get_sha256(FONT_FILE), "font_body_sha256": FileAccess.get_sha256("res://resources/ui_font_body.tres"), "font_emphasis_sha256": FileAccess.get_sha256("res://resources/ui_font_emphasis.tres")}

func font_weight_tag() -> int:
	return TextServerManager.get_primary_interface().name_to_tag("wght")

func configured_font_weight(font: Font) -> float:
	if not font is FontVariation: return -1.0
	return float((font as FontVariation).variation_opentype.get(font_weight_tag(), -1.0))

func native_font_coordinates(font: Font) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if font == null: return result
	var server := TextServerManager.get_primary_interface()
	for rid: RID in font.get_rids():
		result.append(server.font_get_variation_coordinates(rid).duplicate(true))
	return result

func native_font_weight(font: Font) -> float:
	var coordinates := native_font_coordinates(font)
	if coordinates.is_empty(): return -1.0
	var tag := font_weight_tag()
	var observed := -1.0
	for entry: Dictionary in coordinates:
		if not entry.has(tag): return -1.0
		var weight := float(entry[tag])
		if observed >= 0.0 and weight != observed: return -1.0
		observed = weight
	return observed

func is_current_font(font: Font, expected_weight: int = -1) -> bool:
	if not font is FontVariation: return false
	var variation := font as FontVariation
	if variation.base_font == null or variation.base_font.resource_path != FONT_FILE: return false
	if not font_aliases.has(font.get_font_name()): return false
	var tag := font_weight_tag()
	var supported := variation.base_font.get_supported_variation_list()
	if not supported.has(tag): return false
	var weight := configured_font_weight(font)
	var limits: Vector3 = supported[tag]
	if weight < limits.x or weight > limits.y or native_font_weight(font) != weight: return false
	if expected_weight >= 0: return weight == float(expected_weight)
	return weight == 400.0 or weight == 600.0

func audit_font_glyphs(font: Font, value: String, context: String) -> void:
	if font == null: return
	var weight := native_font_weight(font)
	for index in value.length():
		var character := value.substr(index, 1)
		var codepoint := character.unicode_at(0)
		if codepoint <= 32: continue
		font_glyph_characters[character] = true
		var key := "%s:%d" % [str(weight), codepoint]
		if font_glyph_cache.has(key): continue
		font_glyph_cache[key] = true
		var supported := font.has_char(codepoint)
		check(supported, context + ": current font contains actual glyph " + character)
		if not supported: font_glyph_missing.append(key + ":" + character)

func audit_font_contract() -> void:
	var before := failures.size()
	font_context = font_input_context()
	for key: String in font_context: check(not str(font_context[key]).is_empty(), "current font input hash exists: " + key)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(FONT_MANIFEST))
	check(manifest is Dictionary and manifest.get("schema", 0) == 1, "current font manifest has schema1")
	if not manifest is Dictionary: return
	var active: Variant = manifest.get("active", {})
	check(active is Dictionary, "current font manifest declares its active font")
	if not active is Dictionary: return
	font_family = str(active.get("family", ""))
	check(font_family == "Noto Sans SC" and active.get("file", "") == "NotoSansSC.ttf", "new Chinese typeface has the declared production identity")
	check(active.get("sha256", "") == font_context.font_binary_sha256, "actual font bytes match source manifest")
	for alias: Variant in active.get("engine_family_aliases", []):
		font_aliases.append(str(alias))
	check(not font_aliases.is_empty(), "verified internal family aliases are retained")
	var body := SiegeStyle.body_font()
	var emphasis := SiegeStyle.emphasis_font()
	check(is_current_font(body, 400), "body uses actual Noto Sans SC FontVariation wght400")
	check(is_current_font(emphasis, 600), "emphasis uses actual Noto Sans SC FontVariation wght600")
	check(app.theme.default_font == body, "actual Main theme uses the new body variation")
	font_engine_families = {"body": body.get_font_name() if body != null else "", "emphasis": emphasis.get_font_name() if emphasis != null else ""}
	font_weights = {"body": int(configured_font_weight(body)), "emphasis": int(configured_font_weight(emphasis))}
	font_engine_weights = {"body": native_font_weight(body), "emphasis": native_font_weight(emphasis)}
	font_engine_coordinates = {"body": native_font_coordinates(body), "emphasis": native_font_coordinates(emphasis)}
	check(font_engine_weights.body == 400.0 and font_engine_weights.emphasis == 600.0, "TextServer applies actual 400/600 on every font RID")
	audit_font_glyphs(body, REQUIRED_FONT_CHARACTERS, "body glyph contract")
	audit_font_glyphs(emphasis, REQUIRED_FONT_CHARACTERS, "emphasis glyph contract")
	font_contract_passed = failures.size() == before

func audit_ui_fonts(context: String) -> void:
	for node: Node in descendants(app.screen):
		if not node is Control or not canvas_visible(node): continue
		if not node is Label and not node is Button: continue
		var value: String = str(node.get("text"))
		if value.is_empty(): continue
		var font: Font = (node as Control).get_theme_font("font")
		check(is_current_font(font, 600 if node is Button else -1), context + ": rendered control uses current typeface/weight " + str(node.name))
		audit_font_glyphs(font, value, context)

func _initialize() -> void:
	background_started_usec = Time.get_ticks_usec()
	root.mode = Window.MODE_MINIMIZED
	call_deferred("run")

func _process(_delta: float) -> bool:
	if background_monitor_started:
		background_frame_samples += 1
		_record_background_sample("process_frame", background_frame_samples)
	return false

func _record_background_sample(stage: String, sample: int, capture_name: String = "") -> void:
	if root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: return
	if background_first_invalid_sample.is_empty():
		background_first_invalid_sample = {"stage": stage, "sample": sample, "capture_name": capture_name,
			"ticks_usec": Time.get_ticks_usec(), "elapsed_usec": Time.get_ticks_usec() - background_started_usec,
			"window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode(), "cause": "unknown"}
		check(false, "background art host window was restored")

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
	await process_frame
	await process_frame
	# Battle construction keeps the previous camp tab for navigation; only an
	# actual camp list has a pending restoration that this capture may await.
	if not is_instance_valid(app.battle):
		var list_names := {"英魂": "HeroListScroll", "研修": "StudyListScroll", "编队": "SquadListScroll"}
		if list_names.has(app.tab):
			var list := app.screen.find_child(str(list_names[app.tab]), true, false) as ScrollContainer
			for frame in 8:
				if not is_instance_valid(list) or list.get_meta("list_restore_ready", false) == true: break
				await process_frame
	RenderingServer.force_draw(false)
	background_capture_attempts += 1
	var host_valid := root.mode == Window.MODE_MINIMIZED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	if host_valid: background_host_valid_captures += 1
	else: _record_background_sample("art_capture", background_capture_attempts, filename)
	check(host_valid, filename + ": actual host window stays minimized")
	audit_portraits(filename)
	audit_ui_fonts(filename)
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
	captures.append({"name": filename, "path": path, "sha256": FileAccess.get_sha256(path), "sampled_colors": colors.size(), "size": [SIZE.x, SIZE.y], "tab": app.tab, "stage": app.active_stage if is_instance_valid(app.battle) else "", "view_x": app.view_x, "navigation": audit_list_navigation(filename), "study_notice": audit_study_notice(filename), "background_host_valid": host_valid, "root_window_mode": root.mode, "display_window_mode": DisplayServer.window_get_mode()})

func rect_data(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func audit_study_notice(context: String) -> Dictionary:
	if is_instance_valid(app.battle) or app.tab != "研修": return {}
	var footer := app.screen.find_child("StudyFooterRule", true, false) as Label
	check(footer != null and canvas_visible(footer), context + ": necessary study footer rule remains visible")
	if footer == null: return {}
	var footer_rect := footer.get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(SIZE)).grow(1.0).encloses(footer_rect), context + ": footer rule fits full viewport")
	var toast_visible: bool = is_instance_valid(app.toast) and canvas_visible(app.toast)
	var result := {"footer_name": str(footer.name), "footer_text": footer.text, "footer_visible": canvas_visible(footer), "footer_rect": rect_data(footer_rect), "toast_visible": toast_visible}
	if toast_visible:
		var toast_rect: Rect2 = app.toast.get_global_rect()
		var intersects := footer_rect.intersects(toast_rect)
		check(not intersects, context + ": visible study notification cannot cover necessary footer rule")
		check(Rect2(Vector2.ZERO, Vector2(SIZE)).grow(1.0).encloses(toast_rect), context + ": study notification fits full viewport")
		result.merge({"toast_text": str(app.toast.text), "toast_rect": rect_data(toast_rect), "intersects": intersects})
	if context in ["art_study_sweep", "art_study_heal", "art_study_siege", "art_study_slow"]:
		check(toast_visible, context + ": actual route-save notification is visible during capture")
	return result

func audit_list_navigation(context: String) -> Dictionary:
	if is_instance_valid(app.battle): return {}
	var names := {"英魂": "HeroList", "研修": "StudyList", "编队": "SquadList"}
	if not names.has(app.tab): return {}
	var prefix: String = names[app.tab]
	var scroll := app.screen.find_child(prefix + "Scroll", true, false) as ScrollContainer
	var grid := app.screen.find_child(prefix + "Grid", true, false) as GridContainer
	check(scroll != null and grid != null, context + ": named real card list exists")
	if scroll == null or grid == null: return {}
	check(scroll.get_meta("list_restore_ready", false) == true, context + ": latest card-list restoration completed")
	var view := scroll.get_global_rect()
	var result := {"page": str(app.tab), "scroll_name": str(scroll.name), "grid_name": str(grid.name), "restore_ready": scroll.get_meta("list_restore_ready", false), "scroll_vertical": scroll.scroll_vertical, "view_rect": rect_data(view)}
	if app.tab in ["英魂", "研修"]:
		var id: String = str(app.selected_actor)
		var card := grid.find_child("HeroCard_" + id, true, false) as Control
		check(card != null, context + ": current selected card exists")
		if card == null: return result
		var visible := view.grow(1.0).encloses(card.get_global_rect())
		check(visible, context + ": selected character card is fully visible")
		check(card.get_meta("list_unit_id", "") == id and card.get_meta("list_selected", false) == true, context + ": selected card metadata matches actual Main selection")
		result.merge({"selected_id": id, "selected_card": str(card.name), "selected_rect": rect_data(card.get_global_rect()), "selected_visible": visible, "selected_metadata": card.get_meta("list_selected", false)})
	else:
		var roster: Array = root.get_node("ProfileStore").data.get("roster", []).duplicate()
		var records: Array[Dictionary] = []
		for id: String in Catalog.playable_roster():
			var card := grid.find_child("HeroCard_" + id, true, false) as Control
			var button := grid.find_child("RosterToggle_" + id, true, false) as Button
			check(card != null and button != null, context + ": named squad card/action exists " + id)
			if card == null or button == null: continue
			var slot := roster.find(id) + 1
			check(int(card.get_meta("roster_slot", -1)) == slot and int(button.get_meta("roster_slot", -1)) == slot, context + ": actual saved roster slot matches card and action " + id)
			if slot > 0: check(button.text == "%d号位 · 移出" % slot, context + ": summon keyboard slot is always visible " + id)
			records.append({"unit_id": id, "card_name": str(card.name), "button_name": str(button.name), "slot": card.get_meta("roster_slot", -1), "button_slot": button.get_meta("roster_slot", -1), "button_text": button.text})
		result.merge({"saved_roster": roster, "cards": records})
	return result

func settings_return_art() -> void:
	var prefs = root.get_node("UserPrefs")
	var profile = root.get_node("ProfileStore")
	var original_values: Dictionary = prefs._values.duplicate(true)
	var original_path: String = prefs.save_path
	var before_sha := FileAccess.get_sha256(original_path)
	var profile_sha := FileAccess.get_sha256(profile.save_path)
	var snapshot: Dictionary = app.battle.get_snapshot().duplicate(true)
	app.paused = false
	app.battle.set_visual_playback(1.0)
	var before_paused: bool = app.paused
	app._open_settings()
	var panel = app.settings_panel
	check(is_instance_valid(panel) and app._active_modal() == panel, "real Main owns the settings modal")
	if not is_instance_valid(panel): return
	panel.option_buttons.edge_scroll.button_pressed = not bool(original_values.edge_scroll)
	var preview_value: bool = bool(prefs.get_value("edge_scroll"))
	var temporary_path := original_path + ".tmp"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temporary_path)) == OK, "isolated empty temp directory creates a real editable settings save failure")
	check(not panel.close() and panel.visible and app._active_modal() == panel, "failed save keeps the actual settings modal open")
	var consequence: Label = panel.find_child("UnsavedConsequence", true, false)
	var leave: Button = panel.find_child("LeaveWithoutSave", true, false)
	check(consequence != null and consequence.visible and consequence.text.contains("尚未保存") and consequence.text.contains("若之后仍未保存"), "failure consequences are visible without a tooltip")
	check(leave != null and leave.visible and leave.text == "暂不保存并返回", "temporary return action names its unsaved consequence")
	settings_navigation["failed"] = {"capture": "art_settings_save_failed", "modal_active": app._active_modal() == panel, "save_failed": panel.status_label.text.contains("保存失败"), "control_names": ["SaveAndReturn", str(leave.name), str(consequence.name)], "button_text": leave.text, "consequence_text": consequence.text, "consequence_visible": consequence.visible, "runtime_preview_retained": bool(prefs.get_value("edge_scroll")) == preview_value, "dirty_retained": bool(prefs.dirty), "paused": bool(app.paused), "preferences_before_sha256": before_sha, "preferences_after_sha256": FileAccess.get_sha256(original_path)}
	await capture("art_settings_save_failed")
	leave.pressed.emit()
	await process_frame
	var cold = load("res://scripts/core/UserPrefs.gd").new()
	cold.configure_path(original_path)
	var cold_matches: bool = cold.get_value("edge_scroll") == original_values.edge_scroll
	cold.free()
	check(not is_instance_valid(app.settings_panel) and app._active_modal() == null, "temporary return releases Main settings modal")
	check(app.paused == before_paused and app.battle.get_snapshot() == snapshot, "temporary return restores actual battle pause and leaves logical battle unchanged")
	check(bool(prefs.dirty) and bool(prefs.get_value("edge_scroll")) == preview_value and cold_matches, "temporary return keeps preview dirty while a cold reader uses the saved value")
	check(FileAccess.get_sha256(original_path) == before_sha and FileAccess.get_sha256(profile.save_path) == profile_sha, "temporary return does not write preferences or character profile")
	settings_navigation["returned"] = {"capture": "art_settings_temporary_return", "modal_closed": not is_instance_valid(app.settings_panel) and app._active_modal() == null, "pause_restored": app.paused == before_paused, "battle_snapshot_unchanged": app.battle.get_snapshot() == snapshot, "runtime_preview_retained": bool(prefs.get_value("edge_scroll")) == preview_value, "dirty_retained": bool(prefs.dirty), "cold_reloaded_previous_settings": cold_matches, "preferences_before_sha256": before_sha, "preferences_after_sha256": FileAccess.get_sha256(original_path), "profile_before_sha256": profile_sha, "profile_after_sha256": FileAccess.get_sha256(profile.save_path)}
	await capture("art_settings_temporary_return")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path)) == OK, "remove only the isolated empty temporary blocker")
	check(prefs.set_value("edge_scroll", original_values.edge_scroll) and prefs.flush(), "restore original silent preferences after settings presentation fixture")
	check(prefs._values == original_values and FileAccess.get_sha256(original_path) == before_sha, "settings art leaves original isolated preferences values and bytes intact")

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

func result_battle(stage_id: String, summon: bool, fail_save: bool = false) -> void:
	app.start_stage(stage_id)
	app.set_process(false)
	check(is_instance_valid(app.battle), "result art starts actual battle " + stage_id)
	if not is_instance_valid(app.battle): return
	var profile = root.get_node("ProfileStore")
	var original_path: String = profile.save_path
	if fail_save: profile.save_path = DIRECTORY + "/missing_result/profile.json"
	for tick in 1000:
		if str(app.battle.get_snapshot().outcome) != "running": break
		if summon:
			for id: String in app.draft_roster: app._summon(id)
			if tick % 70 == 0: app._pulse()
		app.battle.advance(0.5)
	check(str(app.battle.get_snapshot().outcome) == ("victory" if summon else "defeat"), "result art follows real battle outcome " + stage_id)
	check(is_instance_valid(app.result_panel) and app.result_report.get("outcome", "") == app.battle.get_snapshot().outcome, "actual result renders frozen battle report")
	app._update_hud()
	if fail_save:
		check(not app.result_saved and not app.run_token.is_empty(), "unsaved result retains exact reward transaction")
		await capture("art_result_unsaved")
		profile.save_path = original_path
		app._retry_reward()
		check(app.result_saved and is_instance_valid(app.result_panel), "successful retry keeps same report and saved receipt")
		await capture("art_result_recovered")
	else:
		await capture("art_result_victory" if summon else "art_result_defeat")

func run() -> void:
	project_sha256 = FileAccess.get_sha256("res://project.godot")
	settings_panel_sha256 = FileAccess.get_sha256("res://scripts/ui/SettingsPanel.gd")
	check(QA_CONTEXT.enabled() and QA_CONTEXT.valid(), "offscreen art requires a valid isolated first-autoload startup")
	if not QA_CONTEXT.enabled() or not QA_CONTEXT.valid():
		await finish()
		return
	background_monitor_started = true
	_record_background_sample("run_start", 0)
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
	audit_font_contract()
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
	await settings_return_art()
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
	check(profile._commit(fixture), "restore base fixture before real result art")
	await result_battle("stage_01", true)
	await result_battle("stage_01", false)
	var result_fixture: Dictionary = fixture.duplicate(true)
	result_fixture.cleared = ["stage_01"]
	result_fixture.owned = Catalog.initial_roster()
	result_fixture.roster = Catalog.initial_roster()
	check(profile._commit(result_fixture), "save isolated first-contract receipt art fixture")
	await result_battle("stage_02", true, true)
	check(FileAccess.get_sha256("res://project.godot") == project_sha256, "project configuration remains unchanged throughout art run")
	check(text_labels_audited > 0, "real Main labels received readability audits")
	check(font_input_context() == font_context, "font binary, variants, manifest and UI theme remain frozen throughout all captures")
	check(FileAccess.get_sha256("res://scripts/ui/SettingsPanel.gd") == settings_panel_sha256, "settings panel source remains frozen throughout all captures")
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
	check(background_first_invalid_sample.is_empty() and background_host_valid_captures == background_capture_attempts and background_capture_attempts == captures.size(), "every actual art capture and monitored frame kept the host minimized")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")), "project_sha256": project_sha256, "units_sha256": FileAccess.get_sha256("res://resources/units.json"), "visuals_sha256": FileAccess.get_sha256("res://resources/visuals.json"), "stages_sha256": FileAccess.get_sha256("res://resources/stages.json"), "studies_sha256": FileAccess.get_sha256("res://resources/studies.json"), "briefings_sha256": FileAccess.get_sha256("res://resources/briefings.json"), "briefing_script_sha256": FileAccess.get_sha256("res://scripts/core/BattleBriefing.gd"), "main_sha256": FileAccess.get_sha256("res://scripts/ui/Main.gd"), "stat_badge_sha256": FileAccess.get_sha256("res://scripts/ui/StatBadge.gd"), "battle_script_sha256": FileAccess.get_sha256("res://scripts/combat/SiegeBattle.gd"), "scope": "Hidden offscreen SubViewport rendering of actual Main.tscn: character portraits, readable UI, camp, squads, eight battle briefings including lower scroll/locked/studied states, summon cards, both chapter edges, native gallery, fully visible selected card lists and actual saved summon slots, two failed-settings/temporary-return states and four actual battle-result states. Uses isolated presentation fixtures; does not verify progression, foreground interaction, frame rate or performance.", "isolation": DIRECTORY, "root_visible": root.visible, "root_window_mode": root.mode, "root_focused": root.has_focus(), "rendering_adapter": RenderingServer.get_video_adapter_name(), "screenshots": captures.size(), "captures": captures, "portrait_count": portrait_records.size(), "portraits": portrait_records.values(), "text_labels_audited": text_labels_audited, "text_overflows": text_records, "native_gallery_previews": native_viewers, "native_battle_instances_audited": native_battle_instances, "audio_shutdown_clean": audio.shutdown_clean}
	report.merge(font_context)
	report.merge({"qa_startup": QA_CONTEXT.snapshot(), "background_first_invalid_sample": background_first_invalid_sample,
		"background_window_frame_samples": background_frame_samples, "background_capture_attempts": background_capture_attempts,
		"background_host_valid_captures": background_host_valid_captures, "display_window_mode": DisplayServer.window_get_mode()})
	report.merge({"settings_panel_sha256": settings_panel_sha256, "settings_navigation": settings_navigation})
	var glyph_characters: Array = font_glyph_characters.keys()
	glyph_characters.sort()
	report.merge({"ui_font_family": font_family, "font_engine_families": font_engine_families, "font_engine_weights": font_engine_weights, "font_engine_coordinates": font_engine_coordinates, "body_weight": int(font_weights.get("body", 0)), "emphasis_weight": int(font_weights.get("emphasis", 0)), "font_glyph_check": font_contract_passed and font_glyph_missing.is_empty(), "font_glyph_characters": "".join(PackedStringArray(glyph_characters)), "font_glyph_missing": font_glyph_missing, "font_glyph_variants": [400, 600] if font_contract_passed else []})
	var file := FileAccess.open("res://reports/art_review_local.json", FileAccess.WRITE)
	if file == null:
		push_error("cannot write offscreen art review report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ART_REVIEW_COMPLETE " + JSON.stringify(report))
	quit(0 if report.passed else 1)
