extends SceneTree

var checks := 0
var failures: Array[String] = []
const DIR := "res://tests/.user/progression"

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error(message)

func save_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func create_profile(file_name: String) -> SiegeProfile:
	var path := DIR + "/" + file_name
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var profile := SiegeProfile.new()
	profile.configure_path(path)
	root.add_child(profile)
	return profile

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	check(Catalog.playable_roster().size() == 12, "12 playable contracts")
	check(Catalog.stages().size() == 8, "8 campaign stages")
	var profile := create_profile("profile.json")
	var new_unit: String = Catalog.reward_units("stage_02")[0]
	var locked_unit: String = Catalog.reward_units("stage_04")[0]
	check(not profile.owns(new_unit), "new contract begins locked")
	check(not profile.stage_unlocked("stage_02") and profile.begin_run("stage_02").is_empty(), "locked stage cannot start")
	var before: int = profile.credits()
	var preview := profile.reward_preview("stage_01")
	check(profile.win(profile.begin_run("stage_01")), "first victory commits")
	check(profile.credits() == before + int(preview.credits), "first reward matches preview")
	check(int(profile.last_award.bonus_credits) > 0, "first bonus shown")
	check(profile.stage_unlocked("stage_02"), "next stage unlocks")
	before = profile.credits()
	preview = profile.reward_preview("stage_01")
	check(not bool(preview.first_clear) and int(preview.bonus_credits) == 0, "revisit excludes first bonus")
	check(profile.win(profile.begin_run("stage_01")), "revisit still rewards")
	check(profile.credits() == before + int(preview.base_credits), "revisit amount exact")
	var token := profile.begin_run("stage_02")
	preview = profile.reward_preview("stage_02")
	check(preview.unlock_units.has(new_unit), "preview includes contract")
	check(profile.win(token), "contract victory commits")
	check(profile.owns(new_unit) and profile.level(new_unit) == 1, "contract awarded at level one")
	check(profile.last_award.unlock_units.has(new_unit), "award includes new contract")
	before = profile.credits()
	check(not profile.win(token) and profile.credits() == before, "same run cannot claim twice")
	check(profile.reward_preview("stage_02").unlock_units.is_empty(), "owned contract no duplicate award")
	check(not profile.upgrade(locked_unit), "unowned training blocked")
	check(not profile.set_roster(["guanyu", locked_unit]), "mixed unowned roster rejected")
	check(not profile.set_roster(["riftling"]), "enemy roster rejected")
	check(profile.credits() == before, "rejected choices preserve wallet")
	check(profile.set_roster(["guanyu", new_unit]), "owned new contract can join")
	var readback := SiegeProfile.new()
	readback.configure_path(DIR + "/profile.json")
	root.add_child(readback)
	check(readback.owns(new_unit) and readback.data.roster.has(new_unit), "disk restores new contract and roster")
	check(int(readback.data.schema) == SiegeProfile.SCHEMA, "current schema stored")
	var legacy := create_profile("legacy.json")
	var legacy_data := legacy._fresh()
	legacy_data.schema = 1
	legacy_data.erase("owned")
	legacy_data.credits = 77
	legacy_data.cleared = ["stage_01", "stage_02"]
	legacy_data.levels.guanyu = 3
	save_json(legacy.save_path, legacy_data)
	var legacy_bytes := FileAccess.get_file_as_string(legacy.save_path)
	legacy.load_profile()
	check(legacy.credits() == 77 and legacy.level("guanyu") == 3, "legacy values preserved")
	check(legacy.owns(new_unit), "legacy clears derive new contract")
	check(FileAccess.get_file_as_string(legacy.save_path) == legacy_bytes, "load migration does not write disk")
	check(legacy.set_roster(["guanyu", new_unit]), "migration can save owned roster")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(legacy.save_path)).schema) == SiegeProfile.SCHEMA, "next transaction stores schema2")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(legacy.save_path + ".bak")).schema) == 1, "legacy backup remains recoverable")
	var failing := create_profile("missing/profile.json")
	failing.data.cleared = ["stage_01"]
	var snapshot := failing.data.duplicate(true)
	var fail_token := failing.begin_run("stage_02")
	check(not failing.win(fail_token) and failing.data == snapshot, "failed disk write grants nothing")
	failing.save_path = DIR + "/retry.json"
	check(failing.win(fail_token) and failing.owns(new_unit), "failed reward can retry atomically")
	check(not failing.win(fail_token), "retried token consumed once")
	var future := {"schema": SiegeProfile.SCHEMA + 1, "unknown": ["preserve"]}
	save_json(legacy.save_path, future)
	var future_bytes := FileAccess.get_file_as_string(legacy.save_path)
	legacy.load_profile()
	check(not legacy.upgrade("guanyu") and FileAccess.get_file_as_string(legacy.save_path) == future_bytes, "future schema cannot be overwritten")
	for node: Node in [profile, readback, legacy, failing]: node.queue_free()
	await process_frame
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "schema": SiegeProfile.SCHEMA}
	save_json("res://reports/progression_smoke.json", result)
	print("PROGRESSION_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
