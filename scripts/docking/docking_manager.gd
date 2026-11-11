class_name DockingManager
extends Node
## Decides whether the player may dock with the current target, and handles
## docking and departing. It uses only the Targetable interface (is_dockable,
## dock_range, distance_from), so it contains nothing specific to planets,
## stations or any other object. It reports through signals and changes the
## game state; it does not touch the UI or the ship's controls.

## Emitted when docking succeeds.
signal docked(target: Targetable)
## Emitted after departing, once the ship is back in open space.
signal undocked(target: Targetable)
## Emitted when docking is refused, with a message for the player.
signal docking_denied(message: String)

## Docking is refused above this speed (pixels per second).
@export var max_dock_speed: float = 100.0

## After departing, docking is blocked for this long (milliseconds).
const REDOCK_COOLDOWN_MSEC := 1500
## How far beyond the docking range the ship is placed when departing.
const DEPARTURE_CLEARANCE := 60.0

var docked_target: Targetable

var _targeting: TargetingManager
var _ship: PlayerShip
var _state: GameStateManager
var _last_undock_msec: int = -REDOCK_COOLDOWN_MSEC


func setup(targeting: TargetingManager, ship: PlayerShip, state: GameStateManager) -> void:
	_targeting = targeting
	_ship = ship
	_state = state


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dock") and not event.is_echo():
		try_dock()


func try_dock() -> void:
	if _state.state != GameStateManager.State.FLYING:
		return
	if Time.get_ticks_msec() - _last_undock_msec < REDOCK_COOLDOWN_MSEC:
		return
	var target: Targetable = _targeting.current_target
	if target == null:
		return
	if not target.is_dockable():
		docking_denied.emit("CANNOT DOCK WITH THIS TARGET")
		return
	var distance: float = target.distance_from(_ship.global_position)
	if distance > target.dock_range:
		docking_denied.emit("OUT OF DOCKING RANGE\nMove within %d to dock"
				% [roundi(target.dock_range)])
		return
	var speed: float = _ship.velocity.length()
	if speed > max_dock_speed:
		docking_denied.emit("MOVING TOO FAST TO DOCK\nSlow below %d"
				% [roundi(max_dock_speed)])
		return

	docked_target = target
	_state.change_state(GameStateManager.State.DOCKED)
	docked.emit(target)


## Leaves the docked object: places the ship just outside its docking range,
## on the side the ship approached from, and returns to normal flight.
func undock() -> void:
	if docked_target == null:
		return
	var target: Targetable = docked_target
	docked_target = null

	var offset: Vector2 = _ship.global_position - target.global_position
	var direction: Vector2 = offset.normalized() if offset.length() > 1.0 else Vector2.UP
	_ship.global_position = target.global_position + direction * (target.dock_range + DEPARTURE_CLEARANCE)

	_last_undock_msec = Time.get_ticks_msec()
	_state.change_state(GameStateManager.State.FLYING)
	undocked.emit(target)


## Puts the player back in the docked state after loading a save. Unlike
## try_dock() it does not emit `docked`, so nothing that happens on arrival
## (deliveries, autosave) happens a second time.
func restore_docked(target: Targetable) -> void:
	docked_target = target
	_state.change_state(GameStateManager.State.DOCKED)


## Forgets any docking without announcing it (used when loading a save).
func reset() -> void:
	docked_target = null
