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


func is_ready() -> bool:
	return weapon != null and cooldown_left <= 0.0
