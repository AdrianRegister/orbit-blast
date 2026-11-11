extends SceneTree
## Writes the galaxy content from data/galaxy/galaxy_map.json (see
## tools/galaxy_generator.gd). Safe to run again: it rewrites generated files
## with identical text, and never touches hand_built or locked systems. Run with:
##   Godot --headless --path . --script res://tools/generate_galaxy.gd


func _init() -> void:
	var generator := GalaxyGenerator.new()
	var problems := generator.validate()
	if not problems.is_empty():
		for problem in problems:
			push_error("galaxy table: %s" % problem)
		quit(1)
		return
	var files := generator.build()
	var written := 0
	for path in files:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("cannot write %s" % path)
			quit(1)
			return
		file.store_string(files[path])
		file.close()
		written += 1
	print("generated %d files for %d systems" % [written, generator.get_rows().size()])
	quit(0)
