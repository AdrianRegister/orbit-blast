class_name FactionScreen
extends CanvasLayer
## The Factions screen: a list of factions and, for the selected one, its identity
## (name, description, political identity, background, colours, military
## strength), the player's reputation and standing with it, and its territory.
## It only reads: factions, reputation and territory belong to their own classes.
## The list is built from the factions it is given, so more factions appear by
## adding their resources.

signal closed

const INFO_ROW_SCENE := preload("res://scenes/ui/info_row.tscn")
const HEADING := Color(0.55, 0.64, 0.74)

var _factions: Array[Faction] = []
var _galaxy: Galaxy
var _travel: TravelManager
var _territory: TerritoryManager
var _reputation: ReputationManager
var _registry: ContentRegistry
var _selected: Faction

@onready var _list: ItemList = %FactionList
@onready var _back_button: Button = %BackButton
@onready var _name_label: Label = %NameLabel
@onready var _rows: VBoxContainer = %DetailRows


func _ready() -> void:
	_back_button.pressed.connect(close)
	_list.item_selected.connect(_on_item_selected)


## `factions` are the factions to list. The rest is what the details read.
func setup(factions: Array[Faction], galaxy: Galaxy, travel: TravelManager, territory: TerritoryManager,
		reputation: ReputationManager, registry: ContentRegistry) -> void:
	_factions = factions
	_galaxy = galaxy
	_travel = travel
	_territory = territory
	_reputation = reputation
	_registry = registry
	_reputation.reputation_changed.connect(func(_f: StringName, _o: int, _n: int) -> void: _refresh())
	_reputation.reputation_reset.connect(_refresh)
	_territory.territory_changed.connect(_refresh)
	_travel.discovery_changed.connect(_refresh)


func open() -> void:
	visible = true
	_list.clear()
	for faction in _factions:
		_list.add_item(faction.display_name)
		_list.set_item_custom_fg_color(_list.item_count - 1, faction.primary_colour)
	if not _factions.is_empty():
		var index := maxi(_factions.find(_selected), 0)
		_list.select(index)
		_show(_factions[index])
	else:
		_name_label.text = "NO FACTIONS"


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func get_selected() -> Faction:
	return _selected


## Runs before gameplay input, and also while the game is paused.
func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("factions") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _on_item_selected(index: int) -> void:
	_show(_factions[index])


func _refresh() -> void:
	if visible and _selected != null:
		_show(_selected)


func _show(faction: Faction) -> void:
	_selected = faction
	_name_label.text = faction.display_name.to_upper()
	_name_label.add_theme_color_override("font_color", faction.primary_colour)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_add_text(faction.description)
	_add_swatches(faction)
	_add_row("STRENGTH", NumberFormat.with_commas(faction.military_strength))
	_add_heading("YOUR REPUTATION")
	_add_reputation(faction)
	if not faction.political_identity.is_empty():
		_add_heading("POLITICS")
		_add_text(faction.political_identity)
	if not faction.background.is_empty():
		_add_heading("BACKGROUND")
		_add_text(faction.background)
	_add_territory(faction)
	_add_relations(faction)


func _add_reputation(faction: Faction) -> void:
	var standings := _reputation.standings
	var value := _reputation.get_reputation(faction)
	_add_row("STANDING", "%s  (%+d)" % [_reputation.get_standing(faction).to_upper(), value])
	var bar := ReputationBar.new()
	bar.name = "ReputationBar"
	bar.set_reputation(value, standings.minimum, standings.maximum, faction.primary_colour)
	_rows.add_child(bar)


func _add_swatches(faction: Faction) -> void:
	var row := HBoxContainer.new()
	row.name = "Colours"
	row.add_theme_constant_override("separation", 6)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	caption.text = "COLOURS"
	caption.custom_minimum_size = Vector2(84, 0)
	row.add_child(caption)
	for colour in [faction.primary_colour, faction.secondary_colour]:
		var swatch := ColorRect.new()
		swatch.color = colour
		swatch.custom_minimum_size = Vector2(40, 18)
		row.add_child(swatch)
	_rows.add_child(row)


## What the faction holds, as far as the player knows: the systems it controls
## (and contests) that have been discovered, and its settlements.
func _add_territory(faction: Faction) -> void:
	var controlled := 0
	var known: Array[String] = []
	var contested: Array[String] = []
	var settlements := 0
	for system_id in _galaxy.get_system_ids():
		var control := _territory.get_control(system_id)
		var holds := control.is_controlled_by(faction)
		var disputed := control.is_contested() and control.involves(faction)
		if not holds and not disputed:
			continue
		if holds:
			controlled += 1
		var summary := _galaxy.get_summary(system_id)
		if _travel.is_discovered(system_id):
			if disputed:
				contested.append(summary.system_name)
			else:
				known.append(summary.system_name)
		for location_id in summary.location_ids:
			var place := _registry.location(location_id)
			if place != null and place.is_dockable() and place.population > 0 and _territory.owner_of(place) == faction:
				settlements += 1
	known.sort()
	contested.sort()
	_add_heading("TERRITORY")
	_add_row("SYSTEMS", "%d controlled, %d known to you" % [controlled, known.size()])
	_add_row("SETTLEMENTS", NumberFormat.with_commas(settlements))
	if not contested.is_empty():
		_add_row("CONTESTED", ", ".join(contested))
	_add_row("KNOWN", ", ".join(known) if not known.is_empty() else "None yet")


func _add_relations(faction: Faction) -> void:
	_add_heading("RELATIONS")
	var shown := 0
	for other in _factions:
		if other == faction:
			continue
		var relation := faction.get_relation(other.id)
		if relation != null:
			shown += 1
			_add_row(other.display_name.to_upper(), "%s (%+d)" % ["At war" if relation.at_war else "Attitude", relation.attitude])
	if shown == 0:
		_add_row("", "None known")


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"CaptionLabel"
	label.add_theme_color_override("font_color", HEADING)
	_rows.add_child(label)


func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(label)


func _add_row(caption: String, value: String) -> void:
	var row: InfoRow = INFO_ROW_SCENE.instantiate()
	row.caption = caption
	_rows.add_child(row)
	row.set_value(value)
