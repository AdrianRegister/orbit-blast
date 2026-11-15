class_name WeaponSlot
extends RefCounted
## One mount on a ship and what is fitted to it right now, with its cooldown.

var mount: WeaponMount
## Null = empty mount.
var weapon: WeaponDefinition
## Seconds until the weapon may fire again.
var cooldown_left: float = 0.0


func is_armed() -> bool:
	return weapon != null


## Whether a point-defence weapon is fitted (it fires by itself, see WeaponSystem).
func is_point_defence() -> bool:
	return weapon != null and weapon.point_defence


## Whether a main weapon is fitted: one the player fires and a pilot aims.
func is_main() -> bool:
	return weapon != null and not weapon.point_defence


func is_ready() -> bool:
	return weapon != null and cooldown_left <= 0.0
