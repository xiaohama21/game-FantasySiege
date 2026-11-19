extends SceneTree

const DIR := "res://tests/.user/study_profile"
const MODIFIERS := ["hp_mult", "damage_mult", "armor_add", "speed_mult", "range_mult", "attack_interval_mult", "hit_delay_mult", "aoe_radius_mult", "heal_amount_mult", "slow_ratio", "slow_duration_mult", "base_damage_multiplier"]
var checks := 0
var failures: Array[String] = []
var profiles: Array[SiegeProfile] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "fixture write: " + path)
		return
	file.store_string(JSON.stringify(value))
	file.close()

func create_profile(name: String) -> SiegeProfile:
	var path := DIR + "/" + name
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var profile := SiegeProfile.new()
	profile.configure_path(path)
	root.add_child(profile)
	profiles.append(profile)
	return profile

func make_eligible(profile: SiegeProfile, credits: int = 500) -> void:
	profile.data.credits = credits
	profile.data.levels.guanyu = 3
	profile.data.cleared = ["stage_01", "stage_02", "stage_03", "stage_04"]

func test_catalog() -> void:
	var config := Catalog.studies()
	check(str(config.get("unlock_stage", "")) == "stage_04", "study requires stage four")
	check(int(config.get("min_level", 0)) == 3 and int(config.get("unlock_cost", 0)) == 180, "study shared level and cost")
	check(config.get("units", {}).size() == 12, "all twelve study definitions")
	for id: String in Catalog.playable_roster():
		var definition := Catalog.study(id)
		var routes := Catalog.study_routes(id)
		check(not definition.is_empty() and routes.size() == 2, id + " has two routes")
		check(int(definition.get("unlock_cost", 0)) == 180 and int(definition.get("min_level", 0)) == 3, id + " shared eligibility")
		check(Catalog.study_route(id, "base").get("name") == "基础路线" and Catalog.study_modifiers(id, "base").is_empty(), id + " base preserves modifiers")
		var route_ids: Array[String] = []
		for route: Dictionary in routes:
			var route_id := str(route.get("id", ""))
			check(not route_id.is_empty() and route_id != "base" and not route_ids.has(route_id), id + " unique route id " + route_id)
			route_ids.append(route_id)
			check(not str(route.get("name", "")).is_empty() and not str(route.get("description", "")).is_empty(), id + " visible route explanation " + route_id)
			var modifiers: Dictionary = Catalog.study_modifiers(id, route_id)
			check(not modifiers.is_empty(), id + " route has modifiers " + route_id)
			for key: String in modifiers:
				check(MODIFIERS.has(key) and (modifiers[key] is int or modifiers[key] is float), id + " numeric modifier " + key)
				if key == "slow_ratio":
					check(float(modifiers[key]) >= 0.1 and float(modifiers[key]) <= 1.0, id + " bounded slow")
				elif key != "armor_add":
					check(float(modifiers[key]) > 0.0, id + " positive modifier " + key)
		check(Catalog.study_route(id, "unknown").is_empty(), id + " unknown route rejected")
	check(Catalog.study("riftling").is_empty() and Catalog.study_route("missing", "base").is_empty(), "enemy and missing study rejected")
	var detached := Catalog.study_modifiers("guanyu", "sweep")
	detached.aoe_radius_mult = 99.0
	check(is_equal_approx(float(Catalog.study_modifiers("guanyu", "sweep").aoe_radius_mult), 1.25), "modifier copy cannot alter catalog")
	config.unlock_cost = 1
	check(int(Catalog.studies().unlock_cost) == 180, "full config copy cannot alter catalog")
	var route_copy := Catalog.study_routes("guanyu")
	route_copy[0].name = "changed"
	check(str(Catalog.study_routes("guanyu")[0].name) == "横扫", "route list copy cannot alter catalog")

func test_unlock_and_switch() -> void:
	var profile := create_profile("switch.json")
	check(not profile.study_unlocked("guanyu") and profile.study_route("guanyu") == "base", "fresh base has no paid entitlement")
	check(profile.study_modifiers_snapshot().is_empty() and profile.study_unlock_cost() == 180, "fresh has no active modifiers")
	var before := profile.data.duplicate(true)
	check(not profile.unlock_study("guanyu") and profile.data == before, "fresh conditions reject without mutation")
	profile.data.levels.guanyu = 3
	before = profile.data.duplicate(true)
	check(not profile.unlock_study("guanyu") and profile.data == before, "level alone cannot unlock")
	make_eligible(profile)
	profile.data.levels.guanyu = 2
	before = profile.data.duplicate(true)
	check(not profile.unlock_study("guanyu") and profile.data == before, "clear alone cannot unlock below level three")
	make_eligible(profile, 179)
	before = profile.data.duplicate(true)
	check(not profile.unlock_study("guanyu") and profile.data == before, "one star short rejects without mutation")
	check(not profile.unlock_study("spirit_beast") and not profile.unlock_study("riftling") and not profile.unlock_study("missing"), "unowned enemy unknown study rejected")
	check(not profile.set_study_route("guanyu", "sweep"), "cannot choose before purchase")
	make_eligible(profile, 180)
	check(profile.unlock_study("guanyu"), "exact price unlock commits")
	check(profile.credits() == 0 and profile.study_unlocked("guanyu") and profile.study_route("guanyu") == "base", "purchase once retains base")
	before = profile.data.duplicate(true)
	check(not profile.unlock_study("guanyu") and profile.data == before, "duplicate unlock never charges")
	check(not profile.set_study_route("guanyu", "swift") and not profile.set_study_route("missing", "base") and not profile.set_study_route("zhaoyun", "swift"), "invalid and unpurchased choices rejected")
	check(profile.data == before, "rejected route selections preserve state")
	check(profile.set_study_route("guanyu", "sweep") and profile.credits() == 0, "first route free at empty wallet")
	check(profile.study_modifiers_snapshot().get("guanyu", {}) == Catalog.study_modifiers("guanyu", "sweep"), "active snapshot exact")
	var snapshot := profile.study_modifiers_snapshot()
	snapshot.guanyu.aoe_radius_mult = 99.0
	check(profile.study_modifiers_snapshot().guanyu == Catalog.study_modifiers("guanyu", "sweep"), "snapshot cannot alter profile or catalog")
	check(profile.set_study_route("guanyu", "guard") and profile.credits() == 0, "second route free")
	check(profile.set_study_route("guanyu", "guard") and profile.credits() == 0, "same route is harmless")
	check(profile.set_study_route("guanyu", "base") and profile.study_unlocked("guanyu") and profile.study_modifiers_snapshot().is_empty(), "free base retains entitlement")
	var readback := create_profile("readback_unused.json")
	readback.configure_path(profile.save_path)
	readback.load_profile()
	check(readback.study_unlocked("guanyu") and readback.study_route("guanyu") == "base" and readback.credits() == 0, "durable base and paid entitlement")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(profile.save_path)).schema) == 3, "new transactions store schema three")

func test_all_roles() -> void:
	var profile := create_profile("all_roles.json")
	profile.data.owned = Catalog.playable_roster()
	profile.data.credits = 12 * 180
	for stage: Dictionary in Catalog.stages(): profile.data.cleared.append(str(stage.id))
	for id: String in Catalog.playable_roster():
		profile.data.levels[id] = 3
	for id: String in Catalog.playable_roster():
		var wallet := profile.credits()
		check(profile.unlock_study(id) and profile.credits() == wallet - 180, id + " one exact purchase")
		check(not profile.unlock_study(id) and profile.credits() == wallet - 180, id + " duplicate purchase rejected")
		var routes := Catalog.study_routes(id)
		for route: Dictionary in routes:
			check(profile.set_study_route(id, str(route.id)) and profile.credits() == wallet - 180, id + " free route " + str(route.id))
			check(profile.study_modifiers_snapshot().get(id, {}) == route.modifiers, id + " snapshot route " + str(route.id))
	check(profile.credits() == 0 and profile.study_modifiers_snapshot().size() == 12, "all twelve active at exact total cost")
	for id: String in Catalog.playable_roster():
		check(profile.set_study_route(id, "base") and profile.study_unlocked(id), id + " free base keeps purchase")
	check(profile.study_modifiers_snapshot().is_empty() and profile.credits() == 0, "all base has no modifiers or extra fees")

func test_migration() -> void:
	for schema: int in [1, 2]:
		var profile := create_profile("legacy%d.json" % schema)
		var legacy := profile._fresh()
		legacy.schema = schema
		legacy.erase("study_routes")
		legacy.credits = 77
		legacy.levels.guanyu = 3
		legacy.cleared = ["stage_01", "stage_02"]
		legacy.roster = ["guanyu", "zhaoyun"]
		legacy.transactions = ["historical-transaction"]
		if schema == 1:
			legacy.erase("owned")
		else:
			legacy.owned.append("star_hammer")
			legacy.levels.star_hammer = 1
		write_json(profile.save_path, legacy)
		var original_bytes := FileAccess.get_file_as_string(profile.save_path)
		profile.load_profile()
		check(int(profile.data.schema) == 3 and profile.data.study_routes.is_empty(), "schema%d adds empty studies" % schema)
		check(profile.credits() == 77 and profile.data.cleared == legacy.cleared and profile.data.roster == legacy.roster and profile.data.transactions == legacy.transactions, "schema%d old progress unchanged" % schema)
		for id: String in legacy.levels:
			check(profile.level(id) == int(legacy.levels[id]), "schema%d original level %s" % [schema, id])
		check(profile.owns("star_hammer") and not profile.study_unlocked("guanyu"), "schema%d ownership migration without study grant" % schema)
		if schema == 2: check(profile.data.owned == legacy.owned, "schema2 owned set preserved")
		check(FileAccess.get_file_as_string(profile.save_path) == original_bytes, "schema%d load does not write" % schema)
		check(profile.set_roster(legacy.roster), "schema%d next transaction succeeds" % schema)
		var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(profile.save_path))
		check(int(stored.schema) == 3 and stored.study_routes.is_empty() and int(stored.credits) == 77, "schema%d durable migration no fee" % schema)
		check(FileAccess.get_file_as_string(profile.save_path + ".bak") == original_bytes, "schema%d backup exact old bytes" % schema)

func test_unknown_and_invalid() -> void:
	var profile := create_profile("validation.json")
	make_eligible(profile, 111)
	profile.data.study_routes.guanyu = "retired-route"
	write_json(profile.save_path, profile.data)
	var original_bytes := FileAccess.get_file_as_string(profile.save_path)
	profile.load_profile()
	check(profile.study_unlocked("guanyu") and profile.study_route("guanyu") == "base" and profile.credits() == 111, "unknown string route retains paid base and wallet")
	check(FileAccess.get_file_as_string(profile.save_path) == original_bytes, "unknown route load remains read only")
	check(profile.set_study_route("guanyu", "sweep") and profile.credits() == 111, "retired route can choose replacement free")
	var valid := profile.data.duplicate(true)
	write_json(profile.save_path + ".bak", valid)
	var expected_backup := profile._read(profile.save_path + ".bak")
	profile._sync_owned(expected_backup)
	var invalid_values: Array = [[], null, {"missing": "base"}, {"riftling": "base"}, {"guanyu": 3}, {"guanyu": true}, {"guanyu": []}, {"guanyu": {}}, {"guanyu": null}]
	for i in invalid_values.size():
		var invalid := valid.duplicate(true)
		invalid.study_routes = invalid_values[i]
		write_json(profile.save_path, invalid)
		check(profile._read(profile.save_path).is_empty(), "invalid study field %d rejected" % i)
		profile.load_profile()
		check(profile.data == expected_backup and profile.credits() == 111 and profile.study_route("guanyu") == "sweep", "invalid study field %d restores valid backup" % i)
	var missing_field := valid.duplicate(true)
	missing_field.erase("study_routes")
	write_json(profile.save_path, missing_field)
	check(profile._read(profile.save_path).is_empty(), "schema three missing study field rejected")
	var dormant := create_profile("dormant_entitlement.json")
	make_eligible(dormant)
	dormant.data.study_routes.spirit_beast = "guard"
	write_json(dormant.save_path, dormant.data)
	dormant.load_profile()
	check(dormant.data.study_routes.get("spirit_beast") == "guard" and not dormant.study_unlocked("spirit_beast") and dormant.study_modifiers_snapshot().is_empty(), "unowned paid key retained but not active")
	dormant.data.cleared = ["stage_01", "stage_02", "stage_03", "stage_04", "stage_05", "stage_06", "stage_07"]
	check(dormant.win(dormant.begin_run("stage_08")), "later campaign award grants dormant owner")
	check(dormant.owns("spirit_beast") and dormant.study_unlocked("spirit_beast") and dormant.study_modifiers_snapshot().get("spirit_beast", {}) == Catalog.study_modifiers("spirit_beast", "guard"), "later ownership restores retained paid route")

func test_failures_and_future() -> void:
	var unique := str(Time.get_ticks_usec())
	var failing := create_profile("missing_" + unique + "/profile.json")
	make_eligible(failing)
	var before := failing.data.duplicate(true)
	check(not failing.unlock_study("guanyu") and failing.data == before and not failing.error_message.is_empty(), "failed unlock save does not charge or grant")
	failing.save_path = DIR + "/retry_" + unique + ".json"
	check(failing.unlock_study("guanyu") and failing.credits() == 320, "failed purchase can retry once")
	check(failing.set_study_route("guanyu", "sweep"), "retry route commits")
	before = failing.data.duplicate(true)
	var durable_path := failing.save_path
	failing.save_path = DIR + "/missing_route_" + unique + "/profile.json"
	check(not failing.set_study_route("guanyu", "guard") and failing.data == before, "failed free switch preserves previous route")
	failing.save_path = durable_path
	var original_bytes := FileAccess.get_file_as_string(durable_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(durable_path + ".bak"))
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(durable_path + ".bak"))
	check(not failing.set_study_route("guanyu", "guard") and failing.data == before, "failed backup keeps study state")
	check(FileAccess.get_file_as_string(durable_path) == original_bytes, "failed backup keeps primary bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(durable_path + ".bak"))
	check(failing.set_study_route("guanyu", "guard") and failing.credits() == 320, "switch retries free after backup repair")
	var future := {"schema": 4, "new_study_layout": ["preserve-all"]}
	write_json(durable_path, future)
	original_bytes = FileAccess.get_file_as_string(durable_path)
	failing.load_profile()
	before = failing.data.duplicate(true)
	check(not failing.can_modify() and not failing.unlock_study("guanyu") and not failing.set_study_route("guanyu", "base"), "future primary forbids study mutation")
	check(failing.data == before and FileAccess.get_file_as_string(durable_path) == original_bytes, "future primary bytes and memory preserved")
	write_json(durable_path, "corrupt")
	write_json(durable_path + ".bak", future)
	original_bytes = FileAccess.get_file_as_string(durable_path)
	var backup_bytes := FileAccess.get_file_as_string(durable_path + ".bak")
	failing.load_profile()
	check(not failing.can_modify() and not failing.unlock_study("guanyu"), "future backup also blocks study writes")
	check(FileAccess.get_file_as_string(durable_path) == original_bytes and FileAccess.get_file_as_string(durable_path + ".bak") == backup_bytes, "future backup and primary untouched")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	test_catalog()
	test_unlock_and_switch()
	test_all_roles()
	test_migration()
	test_unknown_and_invalid()
	test_failures_and_future()
	for profile: SiegeProfile in profiles: profile.queue_free()
	await process_frame
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "schema": SiegeProfile.SCHEMA, "program_version": str(ProjectSettings.get_setting("application/config/version", "")), "isolated_path": DIR, "studies_sha256": FileAccess.get_sha256("res://resources/studies.json")}
	write_json("res://reports/study_profile_smoke.json", result)
	print("STUDY_PROFILE_SMOKE " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
