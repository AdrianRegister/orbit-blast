class_name Hud
extends CanvasLayer
## Heads-up display. Shows information; owns no gameplay state.
##
## Real data: velocity, read from the tracked ship.
## Credits: pushed in by Main from the EconomyManager.
## Placeholders: everything else, until the matching system exists. Future
## systems should call the set_* methods below rather than editing the UI.

# --- Placeholder values (no underlying system exists yet) -------------------
const PLACEHOLDER_SYSTEM_NAME := "UNKNOWN"
const PLACEHOLDER_HULL := Vector2(100, 100)    # (current, max)
const PLACEHOLDER_SHIELD := Vector2(100, 100)
const PLACEHOLDER_ENERGY := Vector2(100, 100)
const PLACEHOLDER_WEAPON := "NONE"

const INFO_ROW_SCENE := preload("res://scenes/ui/info_row.tscn")

var _ship: PlayerShip
var _target: Targetable

@onready var _system_value: Label = %SystemValue
@onready var _credits_value: Label = %CreditsValue
@onready var _hull_bar: StatBar = %HullBar
@onready var _shield_bar: StatBar = %ShieldBar
@onready var _energy_bar: StatBar = %EnergyBar
@onready var _velocity_value: Label = %VelocityValue
@onready var _weapon_value: Label = %WeaponValue
@onready var _cargo_list: CargoList = %CargoList
@onready var _nav_map: NavMap = %NavMap
@onready var _nav_destination: Label = %NavDestinationLabel
@onready var _nav_centre_row: InfoRow = %NavCentreRow
@onready var _nav_status: Label = %NavStatusLabel
@onready var _nav_message: Label = %NavMessageLabel
@onready var _target_label: Label = %TargetLabel
@onready var _target_info: VBoxContainer = %TargetInfo
@onready var _target_name: Label = %NameLabel
@onready var _target_type_row: InfoRow = %TypeRow
@onready var _target_distance_row: InfoRow = %DistanceRow
@onready var _target_detail_rows: VBoxContainer = %DetailRows
@onready var _target_message: Label = %MessageLabel

var _message_timer: Timer
var _nav_message_timer: Timer


func _ready() -> void:
	set_system_name(PLACEHOLDER_SYSTEM_NAME)
	set_credits(0)
	set_hull(PLACEHOLDER_HULL.x, PLACEHOLDER_HULL.y)
	set_shield(PLACEHOLDER_SHIELD.x, PLACEHOLDER_SHIELD.y)
	set_energy(PLACEHOLDER_ENERGY.x, PLACEHOLDER_ENERGY.y)
	set_weapon_name(PLACEHOLDER_WEAPON)
	set_cargo(0, 0, [])
	_message_timer = Timer.new()
	_message_timer.one_shot = true
	_message_timer.wait_time = 4.0
	_message_timer.timeout.connect(_clear_target_message)
	add_child(_message_timer)
	_nav_message_timer = Timer.new()
	_nav_message_timer.one_shot = true
	_nav_message_timer.wait_time = 3.0
	_nav_message_timer.timeout.connect(_nav_message.hide)
	add_child(_nav_message_timer)
	set_navigation("", 0.0, 0.0, "", Color.WHITE)


## Tells the HUD which ship's velocity to display.
func track_ship(ship: PlayerShip) -> void:
	_ship = ship
	_nav_map.set_ship(ship)


## Tells the navicomputer's map which star system to show.
func set_nav_system(system: StarSystem) -> void:
	_nav_map.set_system(system)


func get_nav_map() -> NavMap:
	return _nav_map


func _process(_delta: float) -> void:
	if _ship != null:
		_velocity_value.text = "%d" % roundi(_ship.velocity.length())
	_update_target_distance()


## Shows `target` in the target panel, or clears the panel when it is null.
## Connect this to TargetingManager.target_changed.
func set_target(target: Targetable) -> void:
	if _target != null and _target.info_changed.is_connected(_refresh_target):
		_target.info_changed.disconnect(_refresh_target)
	_target = target
	_nav_map.set_target(target)
	if _target != null:
		_target.info_changed.connect(_refresh_target)
	_clear_target_message()
	_refresh_target()


## Shows a red message inside the target panel for a few seconds.
## Ignored when nothing is targeted, since the panel is empty then.
func show_target_message(text: String) -> void:
	if _target == null:
		return
	_target_message.text = text
	_target_message.show()
	_message_timer.start()


func _clear_target_message() -> void:
	_target_message.hide()
	_message_timer.stop()


func _refresh_target() -> void:
	_target_label.visible = _target == null
	_target_info.visible = _target != null
	for row in _target_detail_rows.get_children():
		_target_detail_rows.remove_child(row)
		row.queue_free()
	if _target == null:
		return

	_target_name.text = _target.target_name
	_target_type_row.set_value(_target.target_type)
	for row_data in _target.get_detail_rows():
		var row: InfoRow = INFO_ROW_SCENE.instantiate()
		row.caption = row_data[0]
		_target_detail_rows.add_child(row)
		row.set_value(row_data[1])
	_update_target_distance()


# Distance changes every frame, so it is read here (like velocity) rather than
# pushed through a signal.
func _update_target_distance() -> void:
	if _target == null or _ship == null:
		return
	_target_distance_row.set_value("%d" % roundi(_target.distance_from(_ship.global_position)))


## Fraction of the window width covered by the HUD panel (0.2 = 20%).
func get_panel_width_fraction() -> float:
	return 1.0 - $Panel.anchor_left


func set_system_name(system_name: String) -> void:
	_system_value.text = system_name


func set_credits(credits: int) -> void:
	_credits_value.text = NumberFormat.with_commas(credits)


func set_hull(value: float, max_value: float) -> void:
	_hull_bar.set_values(value, max_value)


func set_shield(value: float, max_value: float) -> void:
	_shield_bar.set_values(value, max_value)


func set_energy(value: float, max_value: float) -> void:
	_energy_bar.set_values(value, max_value)


## `lines` is an Array of [display_name, quantity] pairs.
func set_cargo(used: int, capacity: int, lines: Array) -> void:
	_cargo_list.set_cargo(used, capacity, lines)


## Fills the navicomputer: the selected destination's name ("" for none), how
## far the ship is from the system centre, how far it must be to jump, and a
## status line with its colour.
func set_navigation(destination_name: String, distance: float, required: float,
		status: String, status_colour: Color) -> void:
	_nav_destination.text = "Selected destination: %s" % destination_name if not destination_name.is_empty() \
			else "No destination selected"
	_nav_centre_row.set_value("%s / %s" % [NumberFormat.with_commas(roundi(distance)), NumberFormat.with_commas(roundi(required))])
	_nav_status.text = status
	_nav_status.add_theme_color_override("font_color", status_colour)


## Shows a red message in the navicomputer for a few seconds (e.g. why J did nothing).
func show_navigation_message(text: String) -> void:
	_nav_message.text = text
	_nav_message.show()
	_nav_message_timer.start()


func set_weapon_name(weapon_name: String) -> void:
	_weapon_value.text = weapon_name
