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
