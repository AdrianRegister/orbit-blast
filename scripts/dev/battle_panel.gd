class_name BattlePanel
extends DevPanel
## DEVELOPMENT ONLY. The combat sandbox's battle builder. For each of two sides you choose a faction,
## a tactical profile (or the unit's own) and a list of units: ships of one model (times a count) or
## a unit composed from a formation recipe (squadron, battle group, fleet, convoy, patrol, with its
## commander). Options: start the battle held until START, and which side the player stands on
## (through reputation, with a switch to turn that off). Or spawn a preset. It only calls
## CombatSandbox and reads its BattleTracker; it holds no game logic. The score is on screen in the
## BattleReadout, which stays up when this panel is replaced.

const UNIT_KINDS := ["Ships", "Unit (recipe)"]
const NO_PROFILE := "Profile: the unit's own"

var _factions: Array[Faction] = []  # index 0 of the faction lists is "no faction"
var _ships: Array[ShipStats] = []
var _recipes: Array[FormationRecipe] = []
var _profiles: Array[TacticalProfile] = []
var _side_faction: Array[OptionButton] = []
var _side_profile: Array[OptionButton] = []
var _side_list: Array[ItemList] = []
## For each side the units it has: [{"model": id, "count": n} or {"recipe": id}, ...].
var _side_units: Array = [[], []]
var _kind: Array[OptionButton] = []
var _choice: Array[OptionButton] = []
var _count: Array[SpinBox] = []
var _paused_box: CheckBox
var _stance: OptionButton
var _stance_box: CheckBox
var _start_button: Button
var _info: Label
var _preset: OptionButton


func setup(sandbox: CombatSandbox, registry: ContentRegistry) -> void:
	_sandbox = sandbox
	_factions = registry.factions()
	_ships = registry.all_ship_stats()
	_recipes = registry.formation_recipes()
	_profiles = registry.tactical_profiles()
	layer = 5
	open = false  # the formations panel is the one open at the start
	var scroll := ScrollContainer.new()
	scroll.theme = load("res://resources/ui/hud_theme.tres")
	scroll.position = Vector2(12, 100)
	scroll.custom_minimum_size = Vector2(370, 0)
	scroll.size = Vector2(370, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_scroll = scroll
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.custom_minimum_size = Vector2(340, 0)
	margin.add_child(column)

	column.add_child(_label("DEV: BATTLE", true))
	_preset = OptionButton.new()
	_preset.fit_to_longest_item = false  # (long preset names must not stretch the panel)
	_preset.clip_text = true
	for preset in CombatSandbox.BATTLE_PRESETS:
		_preset.add_item(preset["name"])
	column.add_child(_preset)
	column.add_child(_button("SPAWN PRESET", _on_spawn_preset))
	column.add_child(HSeparator.new())
	for side in 2:
		_build_side(column, side)
	column.add_child(HSeparator.new())
	_paused_box = CheckBox.new()
	_paused_box.text = "Start paused (START releases it)"
	_paused_box.button_pressed = true
	column.add_child(_paused_box)
	var stance_row := HBoxContainer.new()
	stance_row.add_child(_label("Player:"))
	_stance = OptionButton.new()
	for stance_name in ["Neutral", "With side A", "With side B"]:
		_stance.add_item(stance_name)
	_stance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stance.item_selected.connect(func(index: int) -> void: _sandbox.set_player_stance(index as CombatSandbox.Stance))
	stance_row.add_child(_stance)
	column.add_child(stance_row)
	_stance_box = CheckBox.new()
	_stance_box.text = "Stance sets reputation (off: neutral)"
	_stance_box.button_pressed = true
	_stance_box.toggled.connect(func(on: bool) -> void: _sandbox.set_stance_uses_reputation(on))
	column.add_child(_stance_box)
	column.add_child(_button("SPAWN BATTLE", _on_spawn))
	_start_button = _button("START", _on_start_pressed)
	column.add_child(_start_button)
	column.add_child(_button("CLEAR BATTLE SHIPS", _on_clear))
	column.add_child(HSeparator.new())
	_info = _label("Nothing spawned.")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(320, 70)
	column.add_child(_info)
	# A fresh builder has one ship of the first model on each side.
	for side in 2:
		set_side_units(side, [{"model": _ships[0].id, "count": 1}] if not _ships.is_empty() else [])
	DevPanel.disable_focus(self)
	visible = false


var _scroll: ScrollContainer


## One side's controls: faction, profile, the list of units, and a row to add and remove them.
func _build_side(column: VBoxContainer, side: int) -> void:
	column.add_child(_label("Side %s" % ["A", "B"][side]))
	var faction := OptionButton.new()
	faction.add_item("(no faction)")
	for entry in _factions:
		faction.add_item(entry.display_name)
	faction.select(1 + side if _factions.size() > side else 0)
	column.add_child(faction)
	var profile := OptionButton.new()
	profile.fit_to_longest_item = false
	profile.add_item(NO_PROFILE)
	for entry in _profiles:
		profile.add_item("Profile: %s" % entry.display_name)
	column.add_child(profile)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 84)
	list.select_mode = ItemList.SELECT_SINGLE
	column.add_child(list)
	var kind := OptionButton.new()
	for entry in UNIT_KINDS:
		kind.add_item(entry)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.fit_to_longest_item = false
	choice.clip_text = true
	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 20
	count.value = 1
	var row := HBoxContainer.new()
	row.add_child(kind)
	row.add_child(choice)
	row.add_child(count)
	column.add_child(row)
	var buttons := HBoxContainer.new()
	var add := _button("ADD", func() -> void: _on_add(side))
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var remove := _button("REMOVE SELECTED", func() -> void: _on_remove(side))
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(add)
	buttons.add_child(remove)
	column.add_child(buttons)
	_side_faction.append(faction)
	_side_profile.append(profile)
	_side_list.append(list)
	_kind.append(kind)
	_choice.append(choice)
	_count.append(count)
	kind.item_selected.connect(func(_index: int) -> void: _fill_choice(side))
	_fill_choice(side)


## Fills the model or recipe list of a side's add row to match the kind chosen.
func _fill_choice(side: int) -> void:
	var choice := _choice[side]
	choice.clear()
	if _kind[side].selected == 0:
		for model in _ships:
			choice.add_item(model.display_name)
		_count[side].editable = true
	else:
		for recipe in _recipes:
			choice.add_item(recipe.display_name)
		_count[side].editable = false


func _process(_delta: float) -> void:
	_update_visibility()
	if _scroll != null:
		# As tall as the screen allows below the toolbar, never more than the content needs.
		var room := get_viewport().get_visible_rect().size.y - _scroll.position.y - 12.0
		_scroll.size = Vector2(370, minf(room, 900.0))
	if visible:
		_info.text = describe()
		_start_button.text = "START" if _sandbox.is_battle_held() else "HOLD"
		_start_button.disabled = not _sandbox.get_tracker().has_battle()


# ------------------------------------------------------------------ what the builder holds

func get_side_faction(side: int) -> StringName:
	var index := _side_faction[side].selected - 1
	return _factions[index].id if index >= 0 and index < _factions.size() else &""


func get_side_profile(side: int) -> StringName:
	var index := _side_profile[side].selected - 1
	return _profiles[index].id if index >= 0 and index < _profiles.size() else &""


## The units of a side, as the sandbox spawns them: [{"model", "count"} or {"recipe"}].
func get_side_units(side: int) -> Array:
	return _side_units[side].duplicate(true)


func set_side_units(side: int, units: Array) -> void:
	_side_units[side] = units.duplicate(true)
	_refresh_list(side)


## The side as a battle spec (see BattlePresets).
func get_side_spec(side: int) -> Dictionary:
	var spec := {"faction": get_side_faction(side), "units": get_side_units(side)}
	if get_side_profile(side) != &"":
		spec["profile"] = get_side_profile(side)
	return spec


func _refresh_list(side: int) -> void:
	var list := _side_list[side]
	list.clear()
	for unit: Dictionary in _side_units[side]:
		if unit.has("recipe"):
			var recipe := _recipe(unit["recipe"])
			list.add_item("Unit: %s" % (recipe.display_name if recipe != null else str(unit["recipe"])))
		else:
			var model := _model(unit["model"])
			list.add_item("%d x %s" % [unit.get("count", 1), model.display_name if model != null else str(unit["model"])])


func _recipe(id: StringName) -> FormationRecipe:
	for recipe in _recipes:
		if recipe.id == id:
			return recipe
	return null


func _model(id: StringName) -> ShipStats:
	for model in _ships:
		if model.id == id:
			return model
	return null


func _on_add(side: int) -> void:
	var index := _choice[side].selected
	if index < 0:
		return
	if _kind[side].selected == 0:
		_side_units[side].append({"model": _ships[index].id, "count": int(_count[side].value)})
	else:
		_side_units[side].append({"recipe": _recipes[index].id})
	_refresh_list(side)


func _on_remove(side: int) -> void:
	var selected := _side_list[side].get_selected_items()
	if selected.is_empty():
		return
	_side_units[side].remove_at(selected[0])
	_refresh_list(side)


# ---------------------------------------------------------------------------- what it says

## What the panel says about the battle: how many ships each side has in the fight, and whether the
## sides, and the player, are hostile and why.
func describe() -> String:
	var tracker := _sandbox.get_tracker()
	if not tracker.has_battle():
		return "Nothing spawned."
	var a := _alive_ships(0)
	var b := _alive_ships(1)
	var lines: Array[String] = ["A: %d ships, B: %d ships" % [a.size(), b.size()]]
	if not a.is_empty() and not b.is_empty():
		lines.append("A and B: %s" % _reason_text(a[0].get_combatant(), b[0].get_combatant()))
	var player := _sandbox.get_player_combatant()
	if not a.is_empty():
		lines.append("You and A: %s" % _reason_text(player, a[0].get_combatant()))
	if not b.is_empty():
		lines.append("You and B: %s" % _reason_text(player, b[0].get_combatant()))
	return "\n".join(lines)


func _alive_ships(side: int) -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in _sandbox.get_tracker()._ships[side]:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion() and ship.get_combatant().is_alive():
			result.append(ship)
	return result


func _reason_text(first: Combatant, second: Combatant) -> String:
	if first.hostility == null:
		return "(not registered yet)"
	match first.hostility.get_reason(first, second):
		Hostility.REASON_WAR:
			return "HOSTILE (at war)"
		Hostility.REASON_PIRATES:
			return "HOSTILE (pirates attack everyone)"
		Hostility.REASON_REPUTATION:
			return "HOSTILE (bad reputation)"
		Hostility.REASON_GRUDGE:
			return "HOSTILE (a grudge)"
	return "not hostile"


# ------------------------------------------------------------------------------- actions

func _options() -> Dictionary:
	_sandbox.set_stance_uses_reputation(_stance_box.button_pressed)
	_sandbox.set_player_stance(_stance.selected as CombatSandbox.Stance)
	return {"held": _paused_box.button_pressed}


func _on_spawn() -> void:
	_sandbox.get_tracker().clear()  # (the panel keeps the score of the battle it spawned last)
	_sandbox.spawn_battle(get_side_spec(0), get_side_spec(1), _options())


func _on_spawn_preset() -> void:
	_sandbox.get_tracker().clear()
	_sandbox.spawn_battle_preset(_preset.selected, _options())


func _on_start_pressed() -> void:
	if _sandbox.is_battle_held():
		_sandbox.start_battle()
	else:
		_sandbox.hold_battle(true)


func _on_clear() -> void:
	_sandbox.clear_battle()


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
