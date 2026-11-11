extends SceneTree
## Headless checks of the save file layer: atomic writes, backup fallback,
## missing/corrupt/incompatible files, migration, and autosave coalescing.
## Uses a throwaway file in user://, never the real save. Run with:
##   Godot --headless --path . --script res://scripts/tests/save_file_test.gd

const PATH := "user://save_file_test.json"

var _failures: int = 0


class Dummy:
	extends RefCounted
	var value: int = 0
	var resets: int = 0

	func save_state() -> Dictionary:
		return {"value": value}

	func validate_state(data: Variant, _registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
		var problems: Array[String] = []
		if not data is Dictionary or not SaveData.is_int(data.get("value")):
			problems.append("value is not a whole number")
		return problems

	func load_state(data: Dictionary, _registry: ContentRegistry) -> void:
		value = int(data["value"])

	func reset_state() -> void:
		resets += 1
		value = -1


func _init() -> void:
	_clean()
	var manager := SaveManager.new()
	manager.save_path = PATH
	root.add_child(manager)
	var dummy := Dummy.new()
	var optional := Dummy.new()
	manager.register_section(&"dummy", dummy)
	manager.register_section(&"optional", optional, false)

	# --- No save yet.
	_check(not manager.has_save(), "no save file to begin with")
	var result := manager.read_save()
	_check(not result["ok"] and result["error"] == SaveFile.NO_SAVE, "missing save is reported: '%s'" % result["error"])
	_check(not manager.load_game()["ok"], "loading with no save fails cleanly")

	# --- Save and load.
	dummy.value = 42
	var saved_count := [0]
	manager.saved.connect(func() -> void: saved_count[0] += 1)
	_check(manager.save_game(), "save succeeds")
	_check(manager.has_save() and FileAccess.file_exists(PATH), "save file exists")
	_check(not FileAccess.file_exists(PATH + ".tmp"), "no temporary file left behind")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_check(document["version"] == SaveMigrations.CURRENT_VERSION and document.has("saved_at"), "file has version and time")
	_check(document.has("world") and document.has("extensions"), "file has the reserved world and extensions sections")
	dummy.value = 1
	_check(manager.load_game()["ok"] and dummy.value == 42, "loading restores the saved state")
	_check(optional.resets == 0, "a section present in the file is not reset")
	var without_optional: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	without_optional.erase("optional")
	_write(PATH, JSON.stringify(without_optional))
	manager.load_game()
	_check(optional.resets == 1, "an optional section missing from the file is reset")

	# --- Second save keeps the previous one as a backup.
	dummy.value = 43
	manager.save_game()
	_check(FileAccess.file_exists(PATH + ".bak"), "the previous save is kept as .bak")
	_check(JSON.parse_string(FileAccess.get_file_as_string(PATH + ".bak"))["dummy"]["value"] == 42, ".bak holds the previous save")

	# --- Damaged main file: falls back to the backup.
	_write(PATH, '{"version": 1, "dummy": {"val')  # truncated
	result = manager.read_save()
	_check(result["ok"] and result["used_backup"], "truncated main file falls back to the backup")
	dummy.value = 0
	manager.load_game()
	_check(dummy.value == 42, "the backup's state is loaded")

	# --- Everything damaged.
	_write(PATH + ".bak", "garbage")
	for case in [
		["truncated JSON", '{"version": 1, "dummy": {"val'],
		["empty file", ""],
		["not an object", "[1, 2, 3]"],
		["plain text", "hello"],
		["no version", '{"dummy": {"value": 1}}'],
		["text version", '{"version": "one", "dummy": {"value": 1}}'],
		["zero version", '{"version": 0, "dummy": {"value": 1}}'],
		["newer version", '{"version": 999, "dummy": {"value": 1}}'],
		["missing required section", '{"version": 1}'],
		["section of the wrong type", '{"version": 1, "dummy": "no"}'],
		["bad value in section", '{"version": 1, "dummy": {"value": "x"}}'],
	]:
		_write(PATH, case[1])
		dummy.value = 7
		result = manager.load_game()
		_check(not result["ok"] and not result["error"].is_empty(), "rejected: %s (%s)" % [case[0], result["error"]])
		_check(dummy.value == 7, "game untouched after rejecting: %s" % case[0])
	_write(PATH, '{"version": 999, "dummy": {"value": 1}}')
	_check("newer version" in manager.read_save()["error"], "a newer save says so")

	# --- A leftover temporary file does not matter.
	_clean()
	_write(PATH + ".tmp", "half written")
	_check(not manager.has_save(), "a stray .tmp is not a save")
	dummy.value = 5
	_check(manager.save_game() and manager.load_game()["ok"], "saving over a stray .tmp works")

	# --- Write failure is reported and does not crash.
	var failing := SaveManager.new()
	failing.save_path = "user://no_such_folder/save.json"
	root.add_child(failing)
	failing.register_section(&"dummy", dummy)
	var reasons: Array[String] = []
	failing.save_failed.connect(func(reason: String) -> void: reasons.append(reason))
	_check(not failing.save_game() and reasons.size() == 1, "a failed write is reported: %s" % [reasons])

	# --- Migration mechanism.
	var steps := {1: func(d: Dictionary) -> Dictionary:
		d["renamed"] = d["old_name"]
		d.erase("old_name")
		return d}
	var migrated := SaveMigrations.migrate({"version": 1, "old_name": 9}, 2, steps)
	_check(migrated["ok"] and migrated["data"]["renamed"] == 9 and migrated["data"]["version"] == 2
			and not migrated["data"].has("old_name"), "an older save is migrated step by step")
	_check(not SaveMigrations.migrate({"version": 1, "old_name": 1}, 3, steps)["ok"], "a missing migration step is an error")
	_check(not SaveMigrations.migrate({"version": 5}, 2, steps)["ok"], "a newer version is not migrated")
	_check(SaveMigrations.migrate({"version": 1.0}, 1)["ok"], "a version read from JSON as 1.0 is fine")

	# --- Autosave: one write per burst, disabled by default, spaced out.
	_clean()
	saved_count[0] = 0
	manager.request_autosave()
	await process_frame
	await process_frame
	_check(saved_count[0] == 0 and not FileAccess.file_exists(PATH), "autosave is off by default")
	manager.autosave_enabled = true
	manager.min_autosave_interval = 0.4
	await create_timer(0.5).timeout  # let the interval since the last write pass
	for i in 5:
		manager.request_autosave()
	await process_frame
	await process_frame
	_check(saved_count[0] == 1, "five requests in one moment make one write (%d)" % saved_count[0])
	manager.request_autosave()
	await process_frame
	await process_frame
	_check(saved_count[0] == 1, "a request right after a write waits (%d)" % saved_count[0])
	await create_timer(0.6).timeout
	_check(saved_count[0] == 2, "...and is written once the interval has passed (%d)" % saved_count[0])

	_clean()
	manager.queue_free()
	failing.queue_free()
	await process_frame
	print("")
	if _failures == 0:
		print("SAVE FILE TESTS: all passed")
	else:
		print("SAVE FILE TESTS: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		print("FAIL  ", description)
		_failures += 1
