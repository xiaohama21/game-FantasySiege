extends SceneTree

var failures: Array[String] = []
var checks := 0
var directory := "res://tests/.user/profile_smoke"

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error(message)

func write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/profile.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var profile := SiegeProfile.new()
	profile.configure_path(path)
	root.add_child(profile)
	check(profile.credits() == 300, "new profile credits")
	check(profile.level("guanyu") == 1, "new hero level")
	check(profile.upgrade("guanyu"), "upgrade commits")
	check(profile.level("guanyu") == 2 and profile.credits() == 240, "upgrade level/cost match")
	check(not profile.upgrade("missing"), "unknown hero rejected")
	check(not profile.set_roster([]), "empty roster rejected")
	check(profile.set_roster(["guanyu", "guanyu", "zhaoyun"]), "roster de-duplicates")
	check(profile.data.roster == ["guanyu", "zhaoyun"], "saved roster exact")
	var stage_id := str(Catalog.stages()[0].id)
	var token := profile.begin_run(stage_id)
	check(not token.is_empty(), "valid battle session")
	check(profile.win(token), "reward commits")
	var after_reward := profile.credits()
	check(not profile.win(token) and profile.credits() == after_reward, "duplicate reward rejected")
	check(profile.data.cleared.has(stage_id), "clear progress commits")
	var abandon := profile.begin_run(stage_id)
	profile.abandon(abandon)
	check(not profile.win(abandon), "abandoned run cannot reward")
	var recovered := SiegeProfile.new()
	recovered.configure_path(path)
	root.add_child(recovered)
	check(recovered.credits() == after_reward and recovered.level("guanyu") == 2, "disk readback")
	# The previous commit makes a valid backup before corrupting the primary.
	check(recovered.set_roster(["guanyu"]), "second durable commit")
	var expected_backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
	write_json(path, "corrupt")
	recovered.load_profile()
	check(recovered.credits() == int(expected_backup.credits), "valid backup restores corrupt primary")
	check(recovered.upgrade("zhaoyun"), "commit after recovery")
	check(JSON.parse_string(FileAccess.get_file_as_string(path + ".bak")) is Dictionary, "recovery preserves valid backup")
	var future := {"schema": 2, "new_fields": ["unknown-layout"]}
	write_json(path, future)
	var future_bytes := FileAccess.get_file_as_string(path)
	recovered.load_profile()
	check(not recovered.upgrade("guanyu"), "future schema blocks mutation")
	check(FileAccess.get_file_as_string(path) == future_bytes, "future bytes remain unchanged")
	var failed := SiegeProfile.new()
	failed.configure_path(directory + "/does_not_exist/profile.json")
	root.add_child(failed)
	var before := failed.data.duplicate(true)
	check(not failed.upgrade("guanyu") and failed.data == before, "write failure leaves memory unchanged")
	check(not failed.error_message.is_empty(), "write failure is visible")
	var failed_token := failed.begin_run(stage_id)
	check(not failed.win(failed_token) and failed.data == before, "failed reward no false clear")
	profile.queue_free()
	recovered.queue_free()
	failed.queue_free()
	await process_frame
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "isolated_path": directory}
	write_json("res://reports/profile_smoke.json", result)
	print("PROFILE_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
