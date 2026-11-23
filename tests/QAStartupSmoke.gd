extends SceneTree

# The launcher seeds files before this process starts. This fixture deliberately
# never reconfigures a save path: the autoload's first read is the tested event.
const QA_CONTEXT = preload("res://scripts/core/QAStartupContext.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	var found := ""
	for index: int in args.size():
		if args[index] != name: continue
		if not found.is_empty() or index + 1 >= args.size(): return ""
		found = args[index + 1]
	return found

func _run() -> void:
	var expected := _argument("--qa-expect")
	var report_path := _argument("--qa-fixture-report")
	var reports_root := ProjectSettings.globalize_path("res://reports").replace("\\", "/").simplify_path()
	var report_absolute := report_path.replace("\\", "/").simplify_path()
	if not report_absolute.is_absolute_path() or not report_absolute.to_lower().begins_with(reports_root.to_lower() + "/"):
		push_error("QAStartupSmoke requires an absolute fixture report inside this project's reports directory")
		quit(2)
		return
	_check(expected in ["normal", "future", "invalid"], "explicit startup expectation supplied")
	var prefs = root.get_node_or_null("UserPrefs")
	var profile = root.get_node_or_null("ProfileStore")
	_check(prefs != null and profile != null, "both real startup autoloads exist")
	var startup := QA_CONTEXT.snapshot()
	var initial := startup.duplicate(true)
	_check(bool(startup.get("qa_enabled", false)), "QA context was active at startup")
	var first_loads: Dictionary = startup.get("first_loads", {})
	_check(first_loads.has("preferences") and first_loads.has("profile"), "both first-load events are recorded before fixture work")
	if prefs != null and profile != null:
		if expected == "invalid":
			_check(not bool(startup.get("valid", true)), "invalid startup context is rejected")
			_check(startup.get("operations", []).is_empty(), "invalid startup performed no save I/O")
			_check(not startup.get("refused_operations", []).is_empty(), "invalid first paths were explicitly refused")
			_check(not bool(prefs.can_save()) and not bool(profile.can_modify()), "invalid startup blocks both mutation services")
			_check(not bool(prefs.set_value("master_volume", 0.61)) and not bool(prefs.flush()), "invalid preferences cannot be changed or written")
			_check(not bool(profile.upgrade("guanyu")), "invalid profile upgrade is rejected")
		else:
			_check(bool(startup.get("valid", false)), "valid QA startup context")
			_check(startup.get("refused_operations", []).is_empty(), "no save I/O was refused in valid startup")
			var save_root := str(startup.get("save_root", "")).replace("\\", "/").simplify_path()
			var prefs_load: Dictionary = first_loads.get("preferences", {})
			var profile_load: Dictionary = first_loads.get("profile", {})
			_check(str(prefs_load.get("path", "")).replace("\\", "/").simplify_path() == save_root + "/preferences.json", "preferences first read is the seeded startup file")
			_check(str(profile_load.get("path", "")).replace("\\", "/").simplify_path() == save_root + "/profile.json", "profile first read is the seeded startup file")
			_check(not startup.get("operations", []).is_empty(), "startup records actual allowed reads")
			if expected == "normal":
				_check(is_equal_approx(float(prefs.get_value("master_volume")), 0.23), "autoload initially read seeded volume")
				_check(bool(prefs.get_value("fullscreen")), "autoload initially read seeded fullscreen preference")
				_check(profile.credits() == 731 and profile.level("guanyu") == 7, "autoload initially read seeded progression")
				_check(bool(prefs.can_save()) and bool(profile.can_modify()), "supported schemas remain mutable")
				var pref_summary: Dictionary = prefs_load.get("summary", {})
				var profile_summary: Dictionary = profile_load.get("summary", {})
				_check(is_equal_approx(float(pref_summary.get("values", {}).get("master_volume", -1)), 0.23) and bool(pref_summary.get("values", {}).get("fullscreen", false)), "recorded first preference summary contains seeded values")
				_check(int(profile_summary.get("credits", -1)) == 731 and int(profile_summary.get("levels", {}).get("guanyu", -1)) == 7, "recorded first profile summary contains seeded values")
			else:
				_check(not bool(prefs.can_save()) and not bool(profile.can_modify()), "future schemas block mutation at first load")
				_check(bool(prefs_load.get("blocked", false)) and bool(profile_load.get("blocked", false)), "first-load evidence records future protection")
				_check(is_equal_approx(float(prefs.get_value("master_volume")), 0.8) and not bool(prefs.get_value("fullscreen")), "future preferences use safe in-memory defaults")
				_check(profile.credits() == 300 and profile.level("guanyu") == 1, "future profile uses browse-only in-memory defaults")
				_check(not bool(prefs.set_value("master_volume", 0.61)) and not bool(prefs.flush()), "future preferences cannot be downgraded")
				_check(not bool(profile.upgrade("guanyu")), "future profile upgrade cannot overwrite newer progress")
			_check(bool(startup.get("window_policy_skipped", false)), "headless or background startup did not apply fullscreen mode")
	var final_startup := QA_CONTEXT.snapshot()
	if expected == "invalid":
		_check(final_startup.get("operations", []).is_empty(), "rejected mutation attempts still performed no save I/O")
	var report := {"program_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"expected": expected, "process_id": OS.get_process_id(), "qa_startup": initial,
		"qa_after_attempts": final_startup, "first_load_fixture_reconfigured": false,
		"fixture_sha256": FileAccess.get_sha256("res://tests/QAStartupSmoke.gd")}
	var file := FileAccess.open(report_absolute, FileAccess.WRITE)
	if file == null:
		push_error("QAStartupSmoke could not write fixture report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if root.has_node("GameAudio"): await root.get_node("GameAudio").shutdown()
	print("QA_STARTUP_SMOKE_COMPLETE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
