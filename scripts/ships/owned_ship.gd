class_name OwnedShip
extends RefCounted
## One ship the player owns: which model it is, its own name, and its own
## installed upgrades. Models and upgrade definitions are shared static data;
## everything individual to this ship lives here. Only ShipManager changes it.

## Hides a ship from the game's view while keeping all its data. Set on the
## ship the player replaced but kept; the hangar will list such ships later.
const FLAG_PREVIOUS_SHIP := &"PREVIOUS_SHIP"
const MAX_NAME_LENGTH := 50

## Unique among the player's ships, e.g. &"ship_3". Permanent once saved.
var id: StringName = &""
var model: ShipStats
## The name the player gave it.
var ship_name: String = ""
## Installed upgrades; a stackable upgrade appears once per copy.
var upgrades: Array[UpgradeDefinition] = []
## Temporary state markers such as FLAG_PREVIOUS_SHIP.
var flags: Array[StringName] = []
## The weapons fitted, one entry per mount of the model (null = empty mount).
var weapons: Array[WeaponDefinition] = []
## Lasting damage (armour and hull). Shared with the running ship's ShipHealth.
var condition: ShipCondition = ShipCondition.new()


## Fits the model's default weapons and removes all damage: how a ship is as new.
func reset_loadout() -> void:
	weapons.clear()
	for index in model.weapon_mounts.size():
		weapons.append(model.default_loadout[index] if index < model.default_loadout.size() else null)
	condition = ShipCondition.new()


func has_flag(flag: StringName) -> bool:
	return flags.has(flag)


func set_flag(flag: StringName, on: bool) -> void:
	if on and not flags.has(flag):
		flags.append(flag)
	elif not on:
		flags.erase(flag)


## True for a ship the player has replaced but kept.
func is_previous() -> bool:
	return has_flag(FLAG_PREVIOUS_SHIP)


func get_specs() -> ShipSpecs:
	return ShipSpecs.compute(model, upgrades)


## How many copies of `weapon` are fitted.
func count_weapon(weapon: WeaponDefinition) -> int:
	var count := 0
	for fitted in weapons:
		if fitted != null and fitted.id == weapon.id:
			count += 1
	return count


## The first empty mount `weapon` fits, or -1 when there is none.
func find_free_mount(weapon: WeaponDefinition) -> int:
	for index in model.weapon_mounts.size():
		if index < weapons.size() and weapons[index] == null and weapon.fits(model.weapon_mounts[index]):
			return index
	return -1


## The last mount holding `weapon`, or -1 when none does (the copy sold first).
func find_fitted_mount(weapon: WeaponDefinition) -> int:
	for index in range(weapons.size() - 1, -1, -1):
		if weapons[index] != null and weapons[index].id == weapon.id:
			return index
	return -1


## How many mounts hold a weapon.
func mounts_used() -> int:
	var used := 0
	for fitted in weapons:
		if fitted != null:
			used += 1
	return used


func count_installed(upgrade: UpgradeDefinition) -> int:
	var count := 0
	for installed in upgrades:
		if installed.id == upgrade.id:
			count += 1
	return count


## The highest installed tier of a tiered category (0 = none).
func get_tier(category: UpgradeDefinition.Category) -> int:
	var best := 0
	for installed in upgrades:
		if installed.category == category:
			best = maxi(best, installed.tier)
	return best


## A name of 1 to MAX_NAME_LENGTH characters once trimmed; "" if not valid.
static func clean_name(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or trimmed.length() > MAX_NAME_LENGTH:
		return ""
	return trimmed
