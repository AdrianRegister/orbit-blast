class_name SaveFile
extends RefCounted
## Reads and writes the save file safely. It knows nothing about the game:
## it moves text to and from disk without ever leaving a half-written save.
##
## Writing: the new save goes to "<path>.tmp" and is read back and compared;
## only then is the current save moved to "<path>.bak" and the new one moved
## into place. A crash at any step leaves either the old save, or the new save,
## or the old save as .bak, never a broken main file.
## Reading: the main file is tried first, then the .bak.

const NO_SAVE := "No saved game"


## Writes `text` to `path` atomically. Returns "" on success, otherwise why not.
static func write_atomic(path: String, text: String) -> String:
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return "Could not write the save file (%s)" % error_string(FileAccess.get_open_error())
	file.store_string(text)
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(tmp)
		return "Could not write the save file (%s)" % error_string(write_error)
	if FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(tmp)
		return "The save file could not be verified after writing"

	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var backup_error := DirAccess.rename_absolute(path, bak)
		if backup_error != OK:
			DirAccess.remove_absolute(tmp)
			return "Could not keep the previous save (%s)" % error_string(backup_error)
	var move_error := DirAccess.rename_absolute(tmp, path)
	if move_error != OK:
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, path)  # put the old save back
		return "Could not finish saving (%s)" % error_string(move_error)
	return ""


## Reads and parses one file. {"ok": bool, "data": Dictionary, "error": String}.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "error": NO_SAVE}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return {"ok": false, "data": {}, "error": "The save file is empty"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "data": {}, "error": "The save file is damaged (line %d: %s)" % [
				json.get_error_line(), json.get_error_message()]}
	if not json.data is Dictionary:
		return {"ok": false, "data": {}, "error": "The save file is not a save"}
	return {"ok": true, "data": json.data, "error": ""}


## Reads the save, falling back to the backup if the main file is unusable.
## Adds "used_backup": bool to the result of read_json().
static func read_with_backup(path: String) -> Dictionary:
	var result := read_json(path)
	result["used_backup"] = false
	if result["ok"]:
		return result
	var backup := read_json(path + ".bak")
	if backup["ok"]:
		backup["used_backup"] = true
		return backup
	# Report the main file's problem unless there is nothing at all.
	if backup["error"] != NO_SAVE and result["error"] == NO_SAVE:
		result["error"] = backup["error"]
	return result


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")
