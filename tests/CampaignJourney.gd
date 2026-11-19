extends SceneTree

# Accelerated Main UI transactions plus the real 60 Hz battle. This is not a
# rendered/native Spine, input-device, audio-playback, or performance test.
# The resume phase is a separate Godot process and reads the saved profile.
const DIRECTORY := "res://tests/.user/campaign_journey"
const PROFILE_PATH := DIRECTORY + "/profile.json"
const PREFS_PATH := DIRECTORY + "/preferences.json"
const REPORT_PATH := "res://reports/campaign_journey.json"
const GDD_PATH := "res://docs/GAME_DESIGN.md"
const CORE := ["iron_guard", "ember_archer", "rune_medic", "guanyu"]
const STEP := 0.2
const MAX_TICKS := 3000

var app
var profile
var prefs
var checks := 0
var failures: Array = []
var report: Dictionary = {}
var stage_metrics: Dictionary = {}
var warning_due := -1.0
var warning_expires := -1.0
var warning_started := -1.0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _same_saved_value(a: Variant, b: Variant) -> bool:
	# JSON.parse_string represents integers as floats; Dictionary equality
	# retains their distinct types. Compare complete saved values semantically.
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _same_saved_value(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index: int in a.size():
			if not _same_saved_value(a[index], b[index]): return false
		return true
	return typeof(a) == typeof(b) and a == b

func _save_report() -> bool:
	report.checks = checks
	report.failures = failures.duplicate()
	report.passed = failures.is_empty() and str(report.get("phase", "")) == "complete"
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write CampaignJourney report")
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true

func _clean_isolated_files() -> void:
	for path: String in [PROFILE_PATH, PREFS_PATH]:
		for suffix: String in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix)) == OK, "remove isolated fixture " + path + suffix)

func _configure_session(fresh: bool) -> bool:
	profile = root.get_node_or_null("ProfileStore")
	prefs = root.get_node_or_null("UserPrefs")
	_check(profile != null, "ProfileStore autoload available")
	_check(prefs != null, "UserPrefs autoload available for isolated tutorial/settings state")
	if profile == null or prefs == null:
		return false
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY)) == OK, "isolated campaign directory available")
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports")) == OK, "report directory available")
	if fresh:
		_clean_isolated_files()
	profile.configure_path(PROFILE_PATH)
	profile.load_profile()
	prefs.configure_path(PREFS_PATH)
	# These preferences affect presentation only, never resources or combat.
	_check(prefs.set_value("tutorial_seen", true), "isolated preferences skip tutorial for accelerated transactions")
	_check(prefs.set_value("damage_numbers", false), "accelerated journey omits damage-number presentation")
	_check(prefs.set_value("master_volume", 0.0), "accelerated journey mutes playback")
	_check(prefs.flush(), "isolated preferences saved")
	_check(bool(prefs.get_value("tutorial_seen")), "tutorial preference applied before Main starts")
	app = load("res://scenes/Main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	await process_frame
	_check(app.tab == "远征", "Main opens campaign")
	return failures.is_empty()

func _gdd_metadata() -> Dictionary:
	var file := FileAccess.open(GDD_PATH, FileAccess.READ)
	if file == null: return {}
	var source := file.get_as_text()
	file.close()
	var pattern := RegEx.new()
	if pattern.compile("(?m)^> 文档 v([0-9]+\\.[0-9]+\\.[0-9]+)[ \\t]+·[^\\r\\n]*") != OK: return {}
	var header := pattern.search(source)
	var digest := FileAccess.get_sha256(GDD_PATH)
	if header == null or digest.length() != 64: return {}
	return {"gdd_version": header.get_string(1), "gdd_header": header.get_string(0), "gdd_sha256": digest}

func _fresh_report() -> Dictionary:
	var gdd := _gdd_metadata()
	_check(not gdd.is_empty(), "same-project GDD header/version/hash is readable")
	return {
		"version": str(ProjectSettings.get_setting("application/config/version")),
		"gdd_version": gdd.get("gdd_version", ""),
		"gdd_header": gdd.get("gdd_header", ""),
		"gdd_sha256": gdd.get("gdd_sha256", ""),
		"scope": "accelerated Main UI transactions and actual fixed-step battle; separate process persistence readback",
		"visuals": false, "native_spine_verified": false, "audio_playback_verified": false,
		"performance_verified": false, "manual_input_verified": false,
		"presentation": {"headless": true, "battle_render_visuals": false, "main_auto_process": false,
			"damage_numbers": false, "master_volume": 0.0, "tutorial_seen": true},
		"isolation": {"profile": PROFILE_PATH, "preferences": PREFS_PATH},
		"battle_step_seconds": STEP, "logic_step_seconds": SiegeBattle.FIXED_STEP,
		"native_acceptance": "Rendered native Spine, actual audio, clean portable package, and full-scene performance are verified separately.",
		"interfaces": ["Main.start_stage", "Main._train", "Main._toggle_roster", "Main._summon", "Main._pulse", "SiegeBattle.advance", "SiegeBattle.battle_finished → Main reward handler"],
		"forbidden_shortcuts_used": [],
		"units_sha256": FileAccess.get_sha256("res://resources/units.json"),
		"stages_sha256": FileAccess.get_sha256("res://resources/stages.json"),
		"main_sha256": FileAccess.get_sha256("res://scripts/ui/Main.gd"),
		"battle_sha256": FileAccess.get_sha256("res://scripts/combat/SiegeBattle.gd"),
		"journey_sha256": FileAccess.get_sha256("res://tests/CampaignJourney.gd"),
		"fresh_process_id": OS.get_process_id(), "phase": "fresh_running",
		"training": [], "roster_changes": [], "stages": [], "restart": {}, "audio_shutdowns": []
	}

func _all_initial_level_one() -> bool:
	for id: String in Catalog.initial_roster():
		if profile.level(id) != 1:
			return false
	return true

func _train_core_to(level: int, expected_spend: int) -> void:
	app.show_home("英魂")
	await process_frame
	var before: int = profile.credits()
	for id: String in CORE:
		var previous: int = profile.level(id)
		var cost: int = profile.training_cost(id)
		_check(previous == level - 1, "%s starts training at Lv%d" % [id, level - 1])
		_check(profile.credits() >= cost, "%s training is affordable from earned currency" % id)
		app._train(id)
		await process_frame
		_check(profile.level(id) == level, "%s Main training reaches Lv%d" % [id, level])
		report.training.append({"unit_id": id, "from": previous, "to": profile.level(id), "cost": cost, "credits_after": profile.credits()})
	_check(before - profile.credits() == expected_spend, "four-core Lv%d training spends exactly %d" % [level, expected_spend])

func _swap_roster(remove_id: String, add_id: String) -> void:
	app.show_home("编队")
	await process_frame
	var before: Array = profile.data.roster.duplicate()
	_check(before.size() == 8 and before.has(remove_id) and not before.has(add_id), "eight-slot roster is ready to replace %s with %s" % [remove_id, add_id])
	_check(profile.owns(add_id), "replacement contract is owned: " + add_id)
	app._toggle_roster(remove_id)
	await process_frame
	_check(profile.data.roster.size() == 7 and not profile.data.roster.has(remove_id), "Main saves removal of " + remove_id)
	app._toggle_roster(add_id)
	await process_frame
	_check(profile.data.roster.size() == 8 and profile.data.roster.has(add_id), "Main saves replacement " + add_id)
	_check(app.draft_roster == profile.data.roster, "UI draft matches persistent roster")
	report.roster_changes.append({"removed": remove_id, "added": add_id, "before": before, "after": profile.data.roster.duplicate()})

func _on_combat_event(kind: String, _position: Vector2, amount: float, team: int) -> void:
	stage_metrics.events[kind] = int(stage_metrics.events.get(kind, 0)) + 1
	if kind == "attack" and team == -1 and amount >= 0.7:
		var elapsed: float = app.battle.get_snapshot().elapsed
		warning_started = elapsed
		warning_due = elapsed + STEP
		warning_expires = elapsed + amount - SiegeBattle.FIXED_STEP
		stage_metrics.heavy_attack_warnings += 1

func _try_warning_pulse() -> void:
	var snapshot: Dictionary = app.battle.get_snapshot()
	var elapsed := float(snapshot.elapsed)
	if warning_due < 0 or elapsed + 0.00001 < warning_due or elapsed > warning_expires:
		return
	if app.paused or float(snapshot.energy) + 0.00001 < SiegeBattle.PULSE_COST or float(snapshot.pulse_cooldown) > 0.00001:
		return
	app._pulse()
	var after: Dictionary = app.battle.get_snapshot()
	if float(after.pulse_cooldown) > float(snapshot.pulse_cooldown):
		_check(absf(float(snapshot.energy) - float(after.energy) - SiegeBattle.PULSE_COST) < 0.0001, "Main pulse spends actual 80 energy")
		_check(elapsed + 0.00001 >= warning_started + STEP, "pulse waits at least 0.2 game seconds after real warning")
		stage_metrics.pulses.append({"elapsed": elapsed, "warning_elapsed": warning_started,
			"reaction_seconds": elapsed - warning_started, "energy_before": snapshot.energy, "energy_after": after.energy})
		warning_due = -1.0

func _autoplay() -> void:
	if app.paused:
		return
	var counts: Dictionary = {}
	var frontline := 0
	var army := 0
	for actor: Dictionary in app.battle.units:
		if bool(actor.alive) and int(actor.team) == 1:
			counts[actor.id] = int(counts.get(actor.id, 0)) + 1
			army += 1
			if float(actor.range) < 100.0:
				frontline += 1
	var choices: Array = []
	if frontline < 2: choices.append("iron_guard")
	if army >= 4 and int(counts.get("rune_medic", 0)) < 1: choices.append("rune_medic")
	if frontline < 3 and int(counts.get("star_hammer", 0)) < 1: choices.append("star_hammer")
	if int(counts.get("ember_archer", 0)) < 3: choices.append("ember_archer")
	if int(counts.get("zhugeliang", 0)) < 2: choices.append("zhugeliang")
	if int(counts.get("moon_mage", 0)) < 2: choices.append("moon_mage")
	if int(counts.get("rivet_gunner", 0)) < 2: choices.append("rivet_gunner")
	if frontline < 4: choices.append("guanyu")
	choices.append_array(["spirit_beast", "lubu", "zhaoyun", "diaochan"])
	var snapshot: Dictionary = app.battle.get_snapshot()
	if int(snapshot.active_count) >= SiegeBattle.MAX_UNITS: return
	for id: String in choices:
		if not app.draft_roster.has(id): continue
		if float(snapshot.cooldowns.get(id, 0)) > 0.00001: continue
		var cost := float(Catalog.unit(id).get("cost", 0))
		if float(snapshot.energy) + 0.00001 < cost: continue
		var size_before: int = app.battle.units.size()
		app._summon(id)
		var after: Dictionary = app.battle.get_snapshot()
		_check(app.battle.units.size() == size_before + 1, "Main summons legal roster member " + id)
		_check(absf(float(snapshot.energy) - float(after.energy) - cost) < 0.0001, "Main summon pays configured energy for " + id)
		stage_metrics.summons += 1
		stage_metrics.summon_by_id[id] = int(stage_metrics.summon_by_id.get(id, 0)) + 1
		if not stage_metrics.verified_levels.has(id):
			var actor: Dictionary = app.battle.units.back()
			var calculated := UnitStats.calculate(Catalog.unit(id), profile.level(id))
			_check(absf(float(actor.max_hp) - float(calculated.hp)) < 0.0001 and absf(float(actor.damage) - float(calculated.damage)) < 0.0001, "summoned " + id + " inherits actual profile level through UnitStats")
			stage_metrics.verified_levels[id] = profile.level(id)
		return

func _test_paused_actions() -> void:
	app.pause_button.pressed.emit()
	_check(app.paused, "real pause button pauses before journey combat")
	var before: Dictionary = app.battle.get_snapshot()
	var units_before: int = app.battle.units.size()
	app._summon("iron_guard")
	app._pulse()
	await process_frame
	var after: Dictionary = app.battle.get_snapshot()
	_check(app.battle.units.size() == units_before and after.energy == before.energy and after.elapsed == before.elapsed and after.pulse_cooldown == before.pulse_cooldown, "paused Main rejects summon/pulse without resource or time changes")
	app.pause_button.pressed.emit()
	_check(not app.paused, "real pause button restores running state")

func _play_stage(id: String, expected_balance: int, revisit: bool = false) -> bool:
	var before: Dictionary = profile.data.duplicate(true)
	var preview: Dictionary = profile.reward_preview(id)
	_check(profile.stage_unlocked(id), "campaign progression legitimately unlocks " + id)
	app.start_stage(id)
	_check(is_instance_valid(app.battle), "Main starts " + id)
	if not is_instance_valid(app.battle): return false
	app.battle.render_visuals = false
	app.battle.set_process(false)
	_check(not app.paused, "isolated tutorial preference leaves real combat unpaused")
	stage_metrics = {"id": id, "revisit": revisit, "roster": app.draft_roster.duplicate(),
		"levels": profile.data.levels.duplicate(), "credits_before": profile.credits(), "reward_preview": preview,
		"summons": 0, "summon_by_id": {}, "verified_levels": {}, "events": {}, "pulses": [],
		"heavy_attack_warnings": 0, "max_active": 0, "finished_signals": 0, "wall_started_usec": Time.get_ticks_usec()}
	warning_due = -1.0
	warning_expires = -1.0
	app.battle.combat_event.connect(_on_combat_event)
	app.battle.battle_finished.connect(func(victory: bool) -> void:
		stage_metrics.finished_signals += 1
		stage_metrics.signal_victory = victory)
	if id == "stage_01" and not revisit:
		await _test_paused_actions()
	for tick: int in MAX_TICKS:
		if str(app.battle.get_snapshot().outcome) != "running": break
		_try_warning_pulse()
		_autoplay()
		app.battle.advance(STEP)
		stage_metrics.max_active = maxi(int(stage_metrics.max_active), app.battle.active_count())
		# Queue-free UI nodes are released every group of twelve real fixed steps.
		await process_frame
	var snapshot: Dictionary = app.battle.get_snapshot()
	stage_metrics.wall_ms = (Time.get_ticks_usec() - int(stage_metrics.wall_started_usec)) / 1000.0
	stage_metrics.erase("wall_started_usec")
	stage_metrics.outcome = snapshot.outcome
	stage_metrics.elapsed = snapshot.elapsed
	stage_metrics.player_hp = snapshot.player_hp
	stage_metrics.enemy_hp = snapshot.enemy_hp
	var rendered_actors := 0
	for actor: Dictionary in app.battle.units:
		if is_instance_valid(actor.get("visual")): rendered_actors += 1
	stage_metrics.rendered_actor_count = rendered_actors
	stage_metrics.credits_after = profile.credits()
	stage_metrics.actual_award = profile.last_award.duplicate(true)
	stage_metrics.owned_after = profile.data.owned.duplicate()
	stage_metrics.cleared_after = profile.data.cleared.duplicate()
	report.stages.append(stage_metrics.duplicate(true))
	_check(str(snapshot.outcome) == "victory", "actual battle wins " + id + (" revisit" if revisit else ""))
	_check(int(stage_metrics.finished_signals) == 1 and bool(stage_metrics.get("signal_victory", false)), "exactly one real victory signal for " + id)
	_check(is_instance_valid(app.result_panel) and app.run_token.is_empty(), "Main presents result and persists reward " + id)
	_check(profile.credits() == expected_balance, "%s balance is %d after real reward" % [id, expected_balance])
	_check(profile.credits() - int(before.credits) == int(preview.credits), "Main reward matches first-clear/revisit preview " + id)
	_check(profile.last_award == preview, "saved Main award matches preview " + id)
	_check(profile.data.transactions.size() == before.transactions.size() + 1, "one persisted victory transaction " + id)
	_check(int(stage_metrics.max_active) <= SiegeBattle.MAX_UNITS, "actual battle stays within 64-unit limit " + id)
	_check(rendered_actors == 0, "accelerated journey creates no actor render instances " + id)
	_check(int(stage_metrics.events.get("attack", 0)) > 0 and int(stage_metrics.events.get("hit", 0)) > 0 and int(stage_metrics.events.get("base_hit", 0)) > 0, "real attacks, unit damage, and base damage occur " + id)
	for unit_id: String in ["star_hammer", "rivet_gunner", "moon_mage", "spirit_beast"]:
		if app.draft_roster.has(unit_id):
			_check(int(stage_metrics.summon_by_id.get(unit_id, 0)) > 0, "earned contract actually joins real battle: " + unit_id)
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	_check(disk is Dictionary and _same_saved_value(disk, profile.data), "persisted profile exactly matches reward state " + id)
	if revisit:
		_check(not bool(profile.last_award.first_clear) and int(profile.last_award.bonus_credits) == 0 and profile.last_award.unlock_units.is_empty(), "revisit grants no first-clear bonus or new contract")
		_check(profile.data.owned == before.owned and profile.data.cleared == before.cleared, "revisit preserves completed collection/chapter")
	else:
		_check(bool(profile.last_award.first_clear), "first-clear marker for " + id)
		for new_id: String in Catalog.reward_units(id):
			_check(not before.owned.has(new_id) and profile.owns(new_id) and profile.level(new_id) == 1, "actual first clear unlocks Lv1 " + new_id)
	print("CAMPAIGN_STAGE %s%s %s t=%.1f hp=%.0f balance=%d summons=%d pulses=%d" % [id, " revisit" if revisit else "", snapshot.outcome, float(snapshot.elapsed), float(snapshot.player_hp), profile.credits(), int(stage_metrics.summons), stage_metrics.pulses.size()])
	app.show_home("远征")
	await process_frame
	_check(not is_instance_valid(app.battle), "Main returns to camp and cleans battle " + id)
	return failures.is_empty()

func _dispose_app() -> void:
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	var audio := root.get_node_or_null("GameAudio")
	if audio != null:
		await audio.shutdown()
		_check(bool(audio.shutdown_clean), "GameAudio shutdown releases all pending playback before process exit")
		if not report.has("audio_shutdowns"): report.audio_shutdowns = []
		report.audio_shutdowns.append({"process_id": OS.get_process_id(), "phase": report.get("phase", ""),
			"shutdown_clean": bool(audio.shutdown_clean), "wait_seconds": float(audio.shutdown_wait_seconds)})

func _resume() -> void:
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT_PATH))
	if not loaded is Dictionary:
		push_error("Resume requires the fresh CampaignJourney checkpoint")
		quit(2)
		return
	report = loaded
	checks = int(report.get("checks", 0))
	failures = report.get("failures", []).duplicate()
	_check(str(report.get("phase", "")) == "fresh_complete", "resume follows successful full fresh journey")
	_check(int(report.fresh_process_id) != OS.get_process_id(), "readback runs in a separate Godot process")
	var gdd := _gdd_metadata()
	_check(not gdd.is_empty() and str(report.get("gdd_version", "")) == str(gdd.get("gdd_version", "")) and str(report.get("gdd_header", "")) == str(gdd.get("gdd_header", "")) and str(report.get("gdd_sha256", "")) == str(gdd.get("gdd_sha256", "")), "same-package GDD header/version/hash unchanged across restart")
	_check(str(report.units_sha256) == FileAccess.get_sha256("res://resources/units.json") and str(report.stages_sha256) == FileAccess.get_sha256("res://resources/stages.json"), "content unchanged across process restart")
	_check(str(report.restart.profile_sha256) == FileAccess.get_sha256(PROFILE_PATH), "restart reads exact fresh checkpoint bytes")
	if not failures.is_empty():
		report.phase = "resume_failed"
		await _dispose_app()
		_save_report()
		quit(1)
		return
	if not await _configure_session(false):
		_save_report()
		quit(1)
		return
	report.restart.resume_process_id = OS.get_process_id()
	report.restart.profile_reloaded = profile.data.duplicate(true)
	_check(_same_saved_value(profile.data, report.restart.profile_checkpoint), "independent process restores all levels/credits/ownership/roster/transactions")
	_check(profile.credits() == 2580 and profile.data.owned.size() == 12 and profile.data.cleared.size() == 8, "restart restores 2580 credits, twelve owned, eight cleared")
	await _swap_roster("lubu", "spirit_beast")
	_check(profile.level("spirit_beast") == 1, "new beast remains legitimately untrained Lv1")
	await _play_stage("stage_08", 2840, true)
	_check(profile.data.roster.has("spirit_beast") and not profile.data.roster.has("lubu"), "new beast roster remains saved after revisit")
	var earned := 0
	var spent := 0
	for completed: Dictionary in report.stages: earned += int(completed.actual_award.get("credits", 0))
	for training: Dictionary in report.training: spent += int(training.cost)
	_check(earned == 3500 and spent == 960 and 300 + earned - spent == profile.credits(), "whole journey economy reconciles earned 3500/trained 960/final 2840")
	report.economy = {"initial_credits": 300, "earned_credits": earned, "training_spend": spent, "final_credits": profile.credits()}
	report.final_profile = profile.data.duplicate(true)
	report.phase = "complete" if failures.is_empty() else "resume_failed"
	await _dispose_app()
	_save_report()
	print("CAMPAIGN_JOURNEY checks=%d failures=%d process_restart=true stages=%d" % [checks, failures.size(), report.stages.size()])
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("CampaignJourney is an accelerated transaction/battle check; run with --headless. Native acceptance uses separate rendered checks.")
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--journey-resume"):
		await _resume()
		return
	report = _fresh_report()
	if not failures.is_empty():
		report.phase = "fresh_failed"
		await _dispose_app()
		_save_report()
		quit(1)
		return
	if not await _configure_session(true):
		_save_report()
		quit(1)
		return
	_check(profile.credits() == 300 and profile.data.owned == Catalog.initial_roster() and profile.data.roster == Catalog.initial_roster(), "fresh isolated profile has 300 credits/eight owned/eight roster")
	_check(profile.data.cleared.is_empty() and profile.data.transactions.is_empty() and _all_initial_level_one(), "fresh profile has no clears/transactions and every initial hero Lv1")
	report.initial_profile = profile.data.duplicate(true)
	for number: int in range(1, 9):
		if number == 4:
			await _train_core_to(2, 240)
			await _swap_roster("diaochan", "star_hammer")
		elif number == 5:
			await _swap_roster("zhaoyun", "rivet_gunner")
		elif number == 6:
			await _train_core_to(3, 320)
		elif number == 7:
			await _swap_roster("zhugeliang", "moon_mage")
		elif number == 8:
			await _train_core_to(4, 400)
		if number <= 3:
			_check(profile.data.roster == Catalog.initial_roster() and _all_initial_level_one(), "first three stages use exact initial eight Lv1 heroes")
		var balances := [510, 790, 1150, 1310, 1740, 1890, 2400, 2580]
		if not await _play_stage("stage_%02d" % number, balances[number - 1]):
			report.phase = "fresh_failed"
			await _dispose_app()
			_save_report()
			quit(1)
			return
	_check(profile.credits() == 2580 and profile.data.owned.size() == 12 and profile.data.cleared.size() == 8, "fresh full campaign completes with exact earned progression")
	_check(report.training.size() == 12 and report.roster_changes.size() == 3, "fresh campaign trains four cores three times and uses three earned roster replacements")
	report.restart = {"profile_checkpoint": profile.data.duplicate(true), "profile_sha256": FileAccess.get_sha256(PROFILE_PATH)}
	report.phase = "fresh_complete"
	await _dispose_app()
	if not _save_report() or not failures.is_empty():
		quit(1)
		return
	# OS.execute waits for an entirely new runtime; no in-memory profile survives.
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/CampaignJourney.gd", "--", "--journey-resume"])
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true)
	for line: Variant in output: print(str(line))
	var final_result: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT_PATH))
	if exit_code != 0 or not final_result is Dictionary or not bool(final_result.get("passed", false)):
		push_error("CampaignJourney independent resume phase failed; exit=%d" % exit_code)
		quit(1)
		return
	print("CAMPAIGN_JOURNEY_COMPLETE separate_process=true credits=%d owned=%d cleared=%d" % [int(final_result.final_profile.credits), final_result.final_profile.owned.size(), final_result.final_profile.cleared.size()])
	quit(0)
