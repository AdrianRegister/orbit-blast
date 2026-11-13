class_name BattlePanel
extends DevPanel
## DEVELOPMENT ONLY. The combat sandbox's battle builder: two sides, each a faction
## and a number of one ship model, spawned facing each other. It only calls
## CombatSandbox; it holds no game logic. (Presets, composed units, and the live
## battle readout come in later steps.)

var _factions: Array[Faction] = []  # index 0 of the faction lists is "no faction"
var _ships: Array[ShipStats] = []
var _side_faction: Array[OptionButton] = []
var _side_ship: Array[OptionButton] = []
var _side_count: Array[SpinBox] = []
var _info: Label
var _side_a: Array[NpcShip] = []
var _side_b: Array[NpcShip] = []


func setup(sandbox: CombatSandbox, registry: ContentRegistry) -> void:
	_sandbox = sandbox
	_factions = registry.factions()
	_ships = registry.all_ship_stats()
	layer = 5
	open = false  # the formations panel is the one open at the start
	var panel := PanelContainer.new()
	panel.theme = load("res://resources/ui/hud_theme.tres")
	panel.position = Vector2(412, 100)  # (to the right of the formations panel)
	panel.custom_minimum_size = Vector2(300, 0)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	column.add_child(_label("DEV: BATTLE", true))
	for side in 2:
		column.add_child(_label("Side %s" % ["A", "B"][side]))
		var faction := OptionButton.new()
		faction.add_item("(no faction)")
		for entry in _factions:
			faction.add_item(entry.display_name)
		faction.select(1 + side if _factions.size() > side else 0)
		column.add_child(faction)
		var row := HBoxContainer.new()
		var ship := OptionButton.new()
		ship.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for model in _ships:
			ship.add_item(model.display_name)
		row.add_child(ship)
		var count := SpinBox.new()
		count.min_value = 1
		count.max_value = 20
		count.value = 1
		row.add_child(count)
		column.add_child(row)
		_side_faction.append(faction)
		_side_ship.append(ship)
		_side_count.append(count)
	column.add_child(_button("SPAWN BATTLE", _on_spawn))
	column.add_child(_button("CLEAR BATTLE SHIPS", _on_clear))
	column.add_child(HSeparator.new())
	_info = _label("Nothing spawned.")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(280, 80)
	column.add_child(_info)
	visible = false


func _process(_delta: float) -> void:
	_update_visibility()
	if visible:
		_info.text = describe()


## The faction chosen for a side (&"" for none).
func get_side_faction(side: int) -> StringName:
	var index := _side_faction[side].selected - 1
	return _factions[index].id if index >= 0 and index < _factions.size() else &""


## What the panel says about the ships it spawned: how many are left on each side
## and whether the sides, and the player, are hostile to them.
func describe() -> String:
	var a := _alive(_side_a)
	var b := _alive(_side_b)
	if a.is_empty() and b.is_empty():
		return "Nothing spawned."
	var lines: Array[String] = ["A: %d ships, B: %d ships" % [a.size(), b.size()]]
	if not a.is_empty() and not b.is_empty():
		lines.append("A and B: %s" % _reason_text(a[0].get_combatant(), b[0].get_combatant()))
	var player := _sandbox.get_player_combatant()
	if not a.is_empty():
		lines.append("You and A: %s" % _reason_text(player, a[0].get_combatant()))
	if not b.is_empty():
		lines.append("You and B: %s" % _reason_text(player, b[0].get_combatant()))
	return "\n".join(lines)


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


func _alive(ships: Array[NpcShip]) -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in ships:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion() and ship.get_combatant().is_alive():
			result.append(ship)
	return result


func _on_spawn() -> void:
	var sides := _sandbox.spawn_battle(
			{"faction": get_side_faction(0), "model": _ships[_side_ship[0].selected].id, "count": int(_side_count[0].value)},
			{"faction": get_side_faction(1), "model": _ships[_side_ship[1].selected].id, "count": int(_side_count[1].value)})
	_side_a = sides["a"]
	_side_b = sides["b"]


func _on_clear() -> void:
	_sandbox.clear_battle()
	_side_a = []
	_side_b = []


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
