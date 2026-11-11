class_name ShipManager
extends Node
## Owns the player's fleet: buying ships, installing upgrades, switching the
## active ship and naming. It is the only code that changes the Fleet and
## OwnedShips. Money goes through the EconomyManager (the sole writer of
## credits and cargo), so there is one wallet and one hold.
##
## Every operation is checked completely first (quote_* / the start of each
## method) and only then applied in one synchronous block, so a refused
## operation changes nothing and a successful one spends exactly once.
##
## It also acts as the "fleet" save section.

## The active ship changed (new game, purchase, switch, load): the flying ship
## and the cargo hold have already been updated; listeners update the view.
signal active_ship_changed(ship: OwnedShip)
## Anything about the fleet changed (also emitted with active_ship_changed).
signal fleet_changed

## A traded-in ship never reduces the price of the new one below this (or below
## the new ship's own price if that is lower), so a ship is never free and the
## shipyard never pays the player to take one.
@export var minimum_trade_in_price: int = 10000

var _economy: EconomyManager
var _player: PlayerData
## Returns the InhabitedData the player is docked at, or null in open space.
var _location_provider: Callable


func setup(economy: EconomyManager, player: PlayerData, location_provider: Callable) -> void:
	_economy = economy
	_player = player
	_location_provider = location_provider


func get_fleet() -> Fleet:
	return _player.fleet


func get_active() -> OwnedShip:
	return _player.fleet.get_active()


## Starts a fresh fleet holding one ship of `model`, named after the model until
## the player names it. Used when a new game starts.
func start_new_game(model: ShipStats) -> OwnedShip:
	_player.fleet.clear()
	var ship := _player.fleet.create_ship(model, model.display_name)
	_player.fleet.active_id = ship.id
	_apply_active()
	return ship


# ----------------------------------------------------------------- buying ships

## The ships this location's shipyard actually sells to the player: its list,
## without ships that belong to another faction (see ShipStats.faction_name).
## Ships a shipyard does not list, such as military ships, are never for sale.
func get_ships_for_sale(location: InhabitedData) -> Array[ShipStats]:
	var result: Array[ShipStats] = []
	if location == null:
		return result
	for model in location.shipyard_ships:
		if model != null and (model.faction_name.is_empty() or model.faction_name == location.faction_name):
			result.append(model)
	return result


## What buying `model` here would cost, or why it cannot be done. Changes nothing.
func quote_ship(model: ShipStats, trade_in: bool) -> ShipResult:
	var location := _get_location()
	if location == null:
		return ShipResult.refused("You must be docked to buy a ship.")
	if not get_ships_for_sale(location).has(model):
		if location.shipyard_ships.has(model):
			return ShipResult.refused("The %s is only sold by %s." % [model.display_name, model.faction_name])
		return ShipResult.refused("This shipyard does not sell the %s." % model.display_name)
	var result := ShipResult.new()
	result.trade_in_value = get_active().model.price if trade_in else 0
	result.cost = get_net_price(model, result.trade_in_value)
	if _economy.get_credits() < result.cost:
		return ShipResult.refused("Not enough credits (%s CR needed)." % NumberFormat.with_commas(result.cost))
	var capacity := model.cargo_capacity
	var used := _economy.get_cargo().get_used()
	if used > capacity:
		return ShipResult.refused(_cargo_message(model.display_name, used, capacity))
	result.ok = true
	return result


## Price after the trade-in value is taken off, never below the minimum (and
## never above the ship's own price).
func get_net_price(model: ShipStats, trade_in_value: int) -> int:
	if trade_in_value <= 0:
		return model.price
	return mini(model.price, maxi(model.price - trade_in_value, minimum_trade_in_price))


## Buys `model`, makes it the active ship and either trades the old ship in
## (it is removed) or keeps it, flagged PREVIOUS_SHIP. Cargo and contract cargo
## move to the new ship; if it cannot hold them nothing happens.
func buy_ship(model: ShipStats, trade_in: bool) -> ShipResult:
	var result := quote_ship(model, trade_in)
	if not result.ok:
		return result
	if not _economy.try_spend(result.cost):
		return ShipResult.refused("Not enough credits.")
	var old := get_active()
	var ship := _player.fleet.create_ship(model, model.display_name)
	if trade_in:
		_player.fleet.remove(old.id)
	else:
		old.set_flag(OwnedShip.FLAG_PREVIOUS_SHIP, true)
	_player.fleet.active_id = ship.id
	_apply_active()
	result.ship = ship
	return result


# ----------------------------------------------------------------- upgrades

## Whether `upgrade` can be installed on the active ship here, and what it
## costs. Changes nothing.
func quote_upgrade(upgrade: UpgradeDefinition) -> ShipResult:
	var location := _get_location()
	if location == null:
		return ShipResult.refused("You must be docked to fit upgrades.")
	if not location.outfitter_upgrades.has(upgrade):
		return ShipResult.refused("This outfitter does not offer %s." % upgrade.display_name)
	var ship := get_active()
	if ship.count_installed(upgrade) >= upgrade.max_per_ship:
		if upgrade.max_per_ship > 1:
			return ShipResult.refused("Already fitted the maximum of %d." % upgrade.max_per_ship)
		return ShipResult.refused("Already installed.")
	if upgrade.category != UpgradeDefinition.Category.CARGO and ship.get_tier(upgrade.category) != upgrade.tier - 1:
		if ship.get_tier(upgrade.category) >= upgrade.tier:
			return ShipResult.refused("A better version is already installed.")
		return ShipResult.refused("Install the previous tier first.")
	var result := ShipResult.new()
	result.cost = upgrade.price
	if _economy.get_credits() < upgrade.price:
		return ShipResult.refused("Not enough credits (%s CR needed)." % NumberFormat.with_commas(upgrade.price))
	var capacity := preview_upgrade(ship, upgrade).cargo_capacity
	var used := _economy.get_cargo().get_used()
	if used > capacity:
		return ShipResult.refused(_cargo_message(ship.ship_name, used, capacity))
	result.ok = true
	return result


## The active ship's specs as they would be with `upgrade` installed.
func preview_upgrade(ship: OwnedShip, upgrade: UpgradeDefinition) -> ShipSpecs:
	var after: Array = ship.upgrades.duplicate()
	after.append(upgrade)
	return ShipSpecs.compute(ship.model, after)


func install_upgrade(upgrade: UpgradeDefinition) -> ShipResult:
	var result := quote_upgrade(upgrade)
	if not result.ok:
		return result
	if not _economy.try_spend(result.cost):
		return ShipResult.refused("Not enough credits.")
	var ship := get_active()
	ship.upgrades.append(upgrade)
	_apply_active()
	return result


# ------------------------------------------------------- switching and naming

## Makes another owned ship the active one. Only when docked, and only if all
## cargo fits in it (cargo is never lost). Not used by the UI yet; the hangar
## will use it.
func switch_to(ship_id: StringName) -> ShipResult:
	if _get_location() == null:
		return ShipResult.refused("You can only change ships while docked.")
	var ship := _player.fleet.get_ship(ship_id)
	if ship == null:
		return ShipResult.refused("You do not own that ship.")
	var capacity := ship.get_specs().cargo_capacity
	var used := _economy.get_cargo().get_used()
	if used > capacity:
		return ShipResult.refused(_cargo_message(ship.ship_name, used, capacity))
	ship.set_flag(OwnedShip.FLAG_PREVIOUS_SHIP, false)
	_player.fleet.active_id = ship.id
	_apply_active()
	var result := ShipResult.new()
	result.ok = true
	result.ship = ship
	return result


## Names a ship (1 to 50 characters after trimming). False if not valid.
func rename(ship_id: StringName, text: String) -> bool:
	var ship := _player.fleet.get_ship(ship_id)
	var cleaned := OwnedShip.clean_name(text)
	if ship == null or cleaned.is_empty():
		return false
	ship.ship_name = cleaned
	fleet_changed.emit()
	return true


# --------------------------------------------------------------------- saving

func save_state() -> Dictionary:
	return _player.fleet.save_state()


func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	return Fleet.validate_state(data, registry)


func load_state(data: Dictionary, registry: ContentRegistry) -> void:
	_player.fleet.load_state(data, registry)
	_apply_active()


# -------------------------------------------------------------------- helpers

## Brings the hold size in line with the active ship and tells everyone.
func _apply_active() -> void:
	var ship := get_active()
	_economy.set_cargo_capacity(ship.get_specs().cargo_capacity)
	active_ship_changed.emit(ship)
	fleet_changed.emit()


func _get_location() -> InhabitedData:
	return _location_provider.call() if _location_provider.is_valid() else null


func _cargo_message(ship_name: String, used: int, capacity: int) -> String:
	return "Your cargo (%d) does not fit in the %s (capacity %d). Sell or unload %d first." % [
			used, ship_name, capacity, used - capacity]
