class_name Hud
extends CanvasLayer
## Heads-up display. Shows information; owns no gameplay state.
##
## Real data: velocity, shield, armour, hull, energy and weapon state, read
## from the tracked ship every frame. The selected ship's defences and range
## are read the same way.
## Credits: pushed in by Main from the EconomyManager.
## Placeholder: the system name, until Main sets it. Other systems should call
## the set_* methods below rather than editing the UI.

const PLACEHOLDER_SYSTEM_NAME := "UNKNOWN"

## What the FIRE row says for each weapon state, and its colour.
const FIRE_TEXT := {
	WeaponSystem.Status.NONE: "NO WEAPONS",
	WeaponSystem.Status.READY: "READY",
	WeaponSystem.Status.COOLDOWN: "RELOADING",
	WeaponSystem.Status.NO_ENERGY: "NO ENERGY",
}
const FIRE_COLOUR := {
	WeaponSystem.Status.NONE: Color(0.44, 0.54, 0.66),
	WeaponSystem.Status.READY: Color(0.4, 0.9, 0.5),
	WeaponSystem.Status.COOLDOWN: Color(1.0, 0.85, 0.3),
	WeaponSystem.Status.NO_ENERGY: Color(1.0, 0.45, 0.4),
}
const FLASH_HULL := Color(0.9, 0.12, 0.1)
const FLASH_SHIELD := Color(0.3, 0.6, 1.0)

const INFO_ROW_SCENE := preload("res://scenes/ui/info_row.tscn")

var _ship: PlayerShip
var _target: Targetable
## The selected target's combat side, when it is a ship (else null).
var _target_combatant: Combatant
var _fire_status: int = -1
var _flash_tween: Tween

@onready var _system_value: Label = %SystemValue
@onready var _credits_value: Label = %CreditsValue
@onready var _hull_bar: StatBar = %HullBar
@onready var _shield_bar: StatBar = %ShieldBar
@onready var _armour_bar: StatBar = %ArmourBar
@onready var _energy_bar: StatBar = %EnergyBar
@onready var _velocity_value: Label = %VelocityValue
@onready var _weapon_value: Label = %WeaponValue
@onready var _fire_value: Label = %FireValue
@onready var _cooldown_bar: ProgressBar = %CooldownBar
@onready var _combat_message: Label = %CombatMessage
@onready var _damage_flash: ColorRect = %DamageFlash
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
@onready var _range_row: InfoRow = %RangeRow
@onready var _target_defences: VBoxContainer = %TargetDefences
@onready var _target_shield_bar: StatBar = %TargetShieldBar
@onready var _target_armour_bar: StatBar = %TargetArmourBar
@onready var _target_hull_bar: StatBar = %TargetHullBar

var _message_timer: Timer
var _nav_message_timer: Timer
var _combat_message_timer: Timer


func _ready() -> void:
	set_system_name(PLACEHOLDER_SYSTEM_NAME)
	set_credits(0)
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
	_combat_message_timer = Timer.new()
	_combat_message_timer.one_shot = true
	_combat_message_timer.wait_time = 3.0
	_combat_message_timer.timeout.connect(_combat_message.hide)
	add_child(_combat_message_timer)
	set_navigation("", 0.0, 0.0, "", Color.WHITE)


## Tells the HUD which ship to display: its velocity, defences and weapons.
func track_ship(ship: PlayerShip) -> void:
	_ship = ship
	_nav_map.set_ship(ship)
	if ship.combatant != null:
		ship.combatant.damaged.connect(_on_player_damaged)


## Tells the navicomputer's map which star system to show.
func set_nav_system(system: StarSystem) -> void:
	_nav_map.set_system(system)


func get_nav_map() -> NavMap:
	return _nav_map


func _process(_delta: float) -> void:
	if _ship != null:
		_velocity_value.text = "%d" % roundi(_ship.velocity.length())
		_update_player_combat()
	_update_target_live()


## The player's defences, energy and weapon readiness, read from the ship.
func _update_player_combat() -> void:
	var combatant := _ship.combatant
	if combatant == null or combatant.specs == null:
		return
	var health := combatant.health
	set_shield(health.state.shield, health.state.max_shield)
	set_armour(health.state.armour, health.state.max_armour)
	set_hull(health.state.hull, health.state.max_hull)
	set_energy(health.energy, health.max_energy)
	set_weapon_name(combatant.weapons.get_summary())
	var status := combatant.weapons.get_status(health.energy)
	if status != _fire_status:
		_fire_status = status
		_fire_value.text = FIRE_TEXT[status]
		_fire_value.add_theme_color_override("font_color", FIRE_COLOUR[status])
	_cooldown_bar.value = combatant.weapons.get_ready_fraction()


## A hit on the player: a red wash for hull or armour damage, a faint blue one
## when the shields took it all.
func _on_player_damaged(result: DamageResult, _hit: Hit) -> void:
	if result.penetrated():
		flash_damage(FLASH_HULL, 0.35)
	else:
		flash_damage(FLASH_SHIELD, 0.12)


## Washes the whole screen with `colour` at `strength` (0 to 1), fading out.
func flash_damage(colour: Color, strength: float) -> void:
	_damage_flash.color = Color(colour.r, colour.g, colour.b, 1.0)
	_damage_flash.modulate.a = strength
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "modulate:a", 0.0, 0.4)


## Shows a message under the weapon readout for a few seconds (for example
## "TARGET DESTROYED"). It does not need a target, unlike the target message.
func show_combat_message(text: String, colour: Color = Color(0.9, 0.3, 0.3)) -> void:
	_combat_message.text = text
	_combat_message.add_theme_color_override("font_color", colour)
	_combat_message.show()
	_combat_message_timer.start()


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


## Rebuilds the target panel's rows (for values that change while the target stays
## selected, such as damage).
func refresh_target() -> void:
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
	# Ships show their defences and the range; planets and stations do not.
	_target_combatant = CombatManager.find_combatant(_target)
	_target_defences.visible = _target_combatant != null
	_range_row.visible = _target_combatant != null
	if _target == null:
		return

	_target_name.text = _target.target_name
	_target_type_row.set_value(_target.target_type)
	for row_data in _target.get_detail_rows():
		var row: InfoRow = INFO_ROW_SCENE.instantiate()
		row.caption = row_data[0]
		_target_detail_rows.add_child(row)
		row.set_value(row_data[1])
	_update_target_live()


# Distance and a target ship's defences change every frame, so they are read
# here (like velocity) rather than pushed through a signal.
func _update_target_live() -> void:
	if _target == null or _ship == null:
		return
	var distance := _target.distance_from(_ship.global_position)
	_target_distance_row.set_value("%d" % roundi(distance))
	if not is_instance_valid(_target_combatant) or not _target_combatant.is_alive() \
			or _target_combatant.specs == null:
		return
	var state := _target_combatant.health.state
	_target_shield_bar.set_values(state.shield, state.max_shield)
	_target_armour_bar.set_values(state.armour, state.max_armour)
	_target_hull_bar.set_values(state.hull, state.max_hull)
	var reach := _ship.combatant.weapons.get_longest_range() if _ship.combatant != null else 0.0
	if reach <= 0.0:
		_range_row.set_value("NO WEAPONS")
	else:
		_range_row.set_value("IN RANGE" if distance <= reach else "OUT OF RANGE")


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


func set_armour(value: float, max_value: float) -> void:
	_armour_bar.set_values(value, max_value)


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
