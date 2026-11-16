extends SceneTree
## Tests what the outfitters show about weapon mounts: the "needs mount" column for every
## weapon, and the panel listing the active ship's mounts with what is fitted and whether the
## selected weapon would go there. Uses the real game scene. Run with:
##   Godot --headless --path . --script res://scripts/tests/outfitters_mounts_test.gd </dev/null
## (Set the SHOT environment variable and run it with a window to save a screenshot.)

var _failures: int = 0


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ship: PlayerShip = main.get_node("PlayerShip")
	var targeting: TargetingManager = main.get_node("Targeting")
	var docking: DockingManager = main.get_node("Docking")
	var settlement: SettlementScreen = main.get_node("SettlementScreen")
	var outfitters: OutfittersScreen = main.get_node("OutfittersScreen")
	var earth: Targetable
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == "Earth":
			earth = t
	ship.global_position = earth.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	targeting.select(earth)
	docking.try_dock()
	await process_frame
	settlement.get_node("%OutfitterButton").pressed.emit()
	await process_frame
	_check(outfitters.visible, "the outfitters open at Earth")

	var table: Tree = outfitters.get_node("%Table")
	var grid: GridContainer = outfitters.get_node("%MountsGrid")
	var title: Label = outfitters.get_node("%MountsTitle")
	var rows := {}
	var item := table.get_root().get_first_child()
	while item != null:
		rows[item.get_text(OutfittersScreen.Column.UPGRADE)] = item
		item = item.get_next()
	_check(rows.has("Light Blaster") and rows.has("Pulse Cannon"), "Earth sells the light blaster and the pulse cannon")
	var light: WeaponDefinition = load("res://resources/weapons/light_blaster.tres")
	var pulse: WeaponDefinition = load("res://resources/weapons/pulse_cannon.tres")
	_check(rows["Light Blaster"].get_text(OutfittersScreen.Column.MOUNT) == light.get_mount_text() and light.get_mount_text().begins_with("Small"), "each weapon row says what mount it needs: light blaster '%s'" % rows["Light Blaster"].get_text(OutfittersScreen.Column.MOUNT))
	_check(rows["Pulse Cannon"].get_text(OutfittersScreen.Column.MOUNT).begins_with("Medium"), "...pulse cannon '%s'" % rows["Pulse Cannon"].get_text(OutfittersScreen.Column.MOUNT))
	var first_row := table.get_root().get_first_child()
	_check(first_row.get_text(OutfittersScreen.Column.MOUNT) == "-" or first_row.get_metadata(OutfittersScreen.Column.UPGRADE) is WeaponDefinition, "upgrades need no mount")

	# The ship's mounts are listed (the shuttle has one small mount, with a light blaster).
	var model: ShipStats = main.get_player_data().fleet.get_active().model
	var texts := _texts(grid)
	_check(title.text.contains("MOUNTS") and title.text.contains("1 OF 1"), "the mounts panel says how many mounts are in use (%s)" % title.text)
	_check(texts.has("Small") and texts.has("Fixed") and texts.has("Light Blaster"), "...and lists the mount's size, type and what is fitted (%s)" % [texts])
	_check(model.weapon_mounts.size() == 1, "(setup) the starting ship has one mount")

	# Selecting a weapon adds a column saying whether it would go in each mount.
	rows["Pulse Cannon"].select(OutfittersScreen.Column.UPGRADE)
	table.item_selected.emit()
	await process_frame
	texts = _texts(grid)
	_check(grid.columns == 5 and texts.has("Mount too small"), "a pulse cannon is too big for the shuttle's small mount, and the panel says so (%s)" % [texts])
	rows["Light Blaster"].select(OutfittersScreen.Column.UPGRADE)
	table.item_selected.emit()
	await process_frame
	texts = _texts(grid)
	_check(texts.has("Fits, in use"), "a light blaster fits the small mount but it is taken (%s)" % [texts])
	var description: Label = outfitters.get_node("%DescriptionLabel")
	_check(description.text.contains("Needs a mount: Small"), "the weapon's details say which mount it needs")

	# Sell the fitted blaster: the mount shows empty and a blaster would now go there.
	outfitters.get_node("%SellButton").pressed.emit()
	await process_frame
	texts = _texts(grid)
	_check(texts.has("empty") and texts.has("Yes: free"), "with the mount empty, the panel shows it free for the light blaster (%s)" % [texts])

	# The mount descriptions used by the panel.
	var capital := WeaponMount.new()
	capital.type = WeaponMount.Type.TURRET
	capital.size = WeaponMount.Size.CAPITAL
	_check(capital.describe() == "Capital turret", "a mount describes itself ('%s')" % capital.describe())
	var long_gun: WeaponDefinition = load("res://resources/weapons/long_range_blaster.tres")
	_check(long_gun.get_mount_text() == "Capital", "the long-range blaster needs a 'Capital' mount ('%s')" % long_gun.get_mount_text())
	_check(load("res://resources/weapons/point_defence.tres").get_mount_text().ends_with("turret only"), "point defence is turret only")
	_check(pulse.get_misfit_reason(capital) == "" and long_gun.get_misfit_reason(WeaponMount.new()) == "Mount too small", "misfit reasons: none when it fits, too small otherwise")

	var path := OS.get_environment("SHOT")
	if not path.is_empty():
		rows["Pulse Cannon"].select(OutfittersScreen.Column.UPGRADE)
		table.item_selected.emit()
		for i in 5:
			await process_frame
		root.get_texture().get_image().save_png(path)

	print("OUTFITTERS MOUNTS TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _texts(grid: GridContainer) -> Array[String]:
	var result: Array[String] = []
	for child in grid.get_children():
		if child is Label and not child.is_queued_for_deletion():
			result.append((child as Label).text)
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
