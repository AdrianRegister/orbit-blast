class_name SandboxPanel
extends CanvasLayer
## DEVELOPMENT ONLY. The combat sandbox's control panel: a small box on the left
## of the screen for spawning formations and poking at them, so formation
## features can be tried by hand. It only calls CombatSandbox; it holds no game
## logic. New controls are added here as features land.

var _sandbox: CombatSandbox
var _group: OptionButton
var _ship: OptionButton
var _count: SpinBox
var _shape: OptionButton
var _info: Label
var _custom_row: HBoxContainer
var _recipe: OptionButton
var _recipes: Array[FormationRecipe] = []
var _plan_info: Label
var _ships: Array[ShipStats] = []
var _shapes: Array[FormationShape] = []


func setup(sandbox: CombatSandbox, registry: ContentRegistry) -> void:
	_sandbox = sandbox
	_ships = registry.all_ship_stats()
	_shapes = registry.formation_shapes()
	_recipes = registry.formation_recipes()
	layer = 5
	var panel := PanelContainer.new()
	panel.theme = load("res://resources/ui/hud_theme.tres")
	panel.position = Vector2(12, 56)
	panel.custom_minimum_size = Vector2(330, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	column.add_child(_label("DEV: FORMATIONS", true))
	_group = OptionButton.new()
	for preset in CombatSandbox.GROUP_PRESETS:
		_group.add_item(preset["name"])
	_group.add_item("Custom: ship x count")
	_group.item_selected.connect(_on_group_selected)
	column.add_child(_group)

	_custom_row = HBoxContainer.new()
	_ship = OptionButton.new()
	_ship.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for model in _ships:
		_ship.add_item(model.display_name)
	_custom_row.add_child(_ship)
	_count = SpinBox.new()
	_count.min_value = 2
	_count.max_value = 12
	_count.value = 4
	_custom_row.add_child(_count)
	column.add_child(_custom_row)

	column.add_child(_label("Shape"))
	_shape = OptionButton.new()
	for shape in _shapes:
		_shape.add_item(shape.display_name)
	column.add_child(_shape)
	column.add_child(_button("SPAWN FORMATION", _on_spawn))

	column.add_child(HSeparator.new())
	column.add_child(_label("Composed unit (ships drawn from the recipe)"))
	_recipe = OptionButton.new()
	for recipe in _recipes:
		_recipe.add_item(recipe.display_name)
	column.add_child(_recipe)
	column.add_child(_button("SPAWN COMPOSED UNIT (drawn shape)", _on_spawn_composed))
	_plan_info = _label("")
	_plan_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_info.custom_minimum_size = Vector2(310, 48)
	column.add_child(_plan_info)

	column.add_child(HSeparator.new())
	_info = _label("No formation selected. Target a ship in one (T / R / click).")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(310, 64)
	column.add_child(_info)
	column.add_child(_button("APPLY SHAPE TO SELECTED", _on_apply_shape))
	column.add_child(_button("KILL ITS LEADER", _on_kill_leader))
	column.add_child(_button("KILL A MEMBER", _on_kill_member))
	column.add_child(_button("CLEAR ALL FORMATIONS", _on_clear))
	_on_group_selected(0)


func _process(_delta: float) -> void:
	# Hidden while docked or paused.
	visible = _sandbox != null and _sandbox.is_flying() and not get_tree().paused
	var formation := _sandbox.get_selected_formation() if _sandbox != null else null
	if formation == null:
		_info.text = "No formation selected. Target a ship in one (T / R / click)."
		return
	var on_station := 0
	for ship in formation.get_ships():
		if ship == formation.lead or formation.is_on_station(ship):
			on_station += 1
	var text := "%s: %s, %d ships, %d on station.\nLeader: %s. Cruise speed %d, turn %.1f rad/s." % [
			Formation.Kind.keys()[formation.kind].capitalize(), formation.shape.display_name, formation.size(), on_station,
			formation.lead.ship_type.display_name, roundi(formation.lead.formation_speed_cap), formation.lead.formation_turn_cap]
	if formation.parent != null and is_instance_valid(formation.parent):
		text += "\nPart of a %s." % Formation.Kind.keys()[formation.parent.kind].capitalize()
	var fleet: WarFleet = formation.get_root_lead().fleet if formation.has_valid_lead() else null
	if fleet != null and is_instance_valid(fleet):
		text += "\nIn a fleet of %d ships (flagship: %s)." % [fleet.get_all_ships().size(), fleet.flagship.ship_type.display_name]
	_info.text = text


func _on_group_selected(index: int) -> void:
	var custom := index >= CombatSandbox.GROUP_PRESETS.size()
	_custom_row.visible = custom
	if not custom:
		var wanted: StringName = CombatSandbox.GROUP_PRESETS[index]["shape"]
		for position in _shapes.size():
			if _shapes[position].id == wanted:
				_shape.select(position)


func _on_spawn() -> void:
	var shape := _shapes[_shape.selected]
	var index := _group.selected
	if index < CombatSandbox.GROUP_PRESETS.size():
		var preset: Dictionary = CombatSandbox.GROUP_PRESETS[index]
		_sandbox.spawn_formation(shape, preset["ships"], preset["kind"])
	else:
		var ids: Array = []
		for i in int(_count.value):
			ids.append(_ships[_ship.selected].id)
		_sandbox.spawn_formation(shape, ids, Formation.Kind.SQUADRON)


func _on_spawn_composed() -> void:
	if _recipes.is_empty():
		return
	_sandbox.spawn_composed(_recipes[_recipe.selected])
	if _sandbox.last_plan != null:
		_plan_info.text = _sandbox.last_plan.describe()


func _on_apply_shape() -> void:
	var formation := _sandbox.get_selected_formation()
	if formation != null:
		formation.set_shape(_shapes[_shape.selected])


func _on_kill_leader() -> void:
	_sandbox.kill_ship(_sandbox.get_selected_formation().lead if _sandbox.get_selected_formation() != null else null)


func _on_kill_member() -> void:
	var formation := _sandbox.get_selected_formation()
	if formation != null and not formation.get_members().is_empty():
		_sandbox.kill_ship(formation.get_members().pick_random())


func _on_clear() -> void:
	_sandbox.clear_formations()


func _label(text: String, header: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	if header:
		label.theme_type_variation = &"HeaderLabel"
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 32)
	button.pressed.connect(callback)
	return button
