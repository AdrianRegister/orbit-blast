class_name SaveManager
extends Node
## The one place that saves and loads the game. It knows the shape of the file
## (version, a section per system) but not what is inside the sections: every
## system that owns persistent state registers itself as a section provider.
##
## A provider is any object with:
##   save_state() -> Dictionary                                 plain data to store
##   validate_state(data, registry, document) -> Array[String] problems, changes nothing
##   load_state(data: Dictionary, registry) -> void             replaces its state
## and optionally reset_state() for when an optional section is missing.
## Adding persistent state in a later milestone = register one more provider;
## nothing in this class changes.
##
## Loading is two phases: the whole document is validated first (nothing is
## touched), then applied section by section in registration order. Apply
## cannot fail because validation already proved the data usable.

signal saved
signal save_failed(reason: String)
signal loaded

const SAVE_PATH := "user://savegame.json"

@export var save_path: String = SAVE_PATH
## Autosaves are only written when this is true (the game turns it on when a
## session starts, so tests and tools never overwrite the player's save).
var autosave_enabled: bool = false
## At most one autosave per this many seconds.
var min_autosave_interval: float = 2.0

var _providers: Array[Dictionary] = []  # {"key", "provider", "required"}
var _registry: ContentRegistry
var _loading: bool = false
var _autosave_queued: bool = false
var _last_write_msec: int = -1000000


## `provider` is saved under `key`. Sections are applied in registration order.
func register_section(key: StringName, provider: Object, required: bool = true) -> void:
	_providers.append({"key": key, "provider": provider, "required": required})


func get_registry() -> ContentRegistry:
	if _registry == null:
		_registry = ContentRegistry.new()
	return _registry


## Replaces the content registry (used by tests that add their own systems).
func set_registry(registry: ContentRegistry) -> void:
	_registry = registry


func is_loading() -> bool:
	return _loading


## Whether any save file (or backup) exists on disk.
func has_save() -> bool:
	return SaveFile.exists(save_path)


# ------------------------------------------------------------------ saving

## The whole game as plain data. Captured in one go, so it is consistent.
func build_document() -> Dictionary:
	var document := {
		"version": SaveMigrations.CURRENT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"world": {"systems": {}},
		"extensions": {},
	}
	for entry in _providers:
		document[str(entry["key"])] = entry["provider"].save_state()
	return document


## Saves now. Returns true on success; failures are reported via save_failed.
func save_game() -> bool:
	if _loading:
		return false
	var text := JSON.stringify(build_document(), "\t")
	var error := SaveFile.write_atomic(save_path, text)
	if not error.is_empty():
		push_warning("Save failed: %s" % error)
		save_failed.emit(error)
		return false
	_last_write_msec = Time.get_ticks_msec()
	saved.emit()
	return true


## Asks for an autosave. Requests made in the same moment (one action usually
## changes several systems) become a single write at the end of the frame, and
## writes are spaced by min_autosave_interval.
func request_autosave() -> void:
	if not autosave_enabled or _loading or _autosave_queued:
		return
	_autosave_queued = true
	var wait: float = min_autosave_interval - (Time.get_ticks_msec() - _last_write_msec) / 1000.0
	if wait <= 0.0 or not is_inside_tree():
		_run_autosave.call_deferred()
	else:
		get_tree().create_timer(wait).timeout.connect(_run_autosave)


func _run_autosave() -> void:
	_autosave_queued = false
	if autosave_enabled and not _loading:
		save_game()


# ----------------------------------------------------------------- loading

## Reads, migrates and validates the save without changing the game.
## {"ok": bool, "document": Dictionary, "error": String, "used_backup": bool}
func read_save() -> Dictionary:
	var read := SaveFile.read_with_backup(save_path)
	if not read["ok"]:
		return {"ok": false, "document": {}, "error": read["error"], "used_backup": false}
	var migrated := SaveMigrations.migrate(read["data"])
	if not migrated["ok"]:
		return {"ok": false, "document": {}, "error": migrated["error"], "used_backup": false}
	var problems := validate_document(migrated["data"])
	if not problems.is_empty():
		push_warning("Save rejected: %s" % [problems])
		return {"ok": false, "document": {}, "error": "The saved game is damaged (%s)" % problems[0],
				"used_backup": false}
	return {"ok": true, "document": migrated["data"], "error": "", "used_backup": read["used_backup"]}


## Every problem found in `document`; empty when it can be applied.
func validate_document(document: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var registry := get_registry()
	problems.append_array(registry.problems)
	for entry in _providers:
		var key := str(entry["key"])
		if not document.has(key):
			if entry["required"]:
				problems.append("section '%s' is missing" % key)
			continue
		problems.append_array(entry["provider"].validate_state(document[key], registry, document))
	return problems


## Loads the save into the running game. Returns {"ok": bool, "error": String};
## on failure the game is left exactly as it was.
func load_game() -> Dictionary:
	var result := read_save()
	if not result["ok"]:
		return {"ok": false, "error": result["error"]}
	apply_document(result["document"])
	return {"ok": true, "error": ""}


## Applies an already validated document.
func apply_document(document: Dictionary) -> void:
	_loading = true
	var registry := get_registry()
	for entry in _providers:
		var key := str(entry["key"])
		var provider: Object = entry["provider"]
		if document.has(key):
			provider.load_state(document[key], registry)
		elif provider.has_method("reset_state"):
			provider.reset_state()
	_loading = false
	loaded.emit()
