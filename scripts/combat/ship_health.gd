class_name ShipHealth
extends Node
## The live defences and energy of one ship. Shields and energy recharge by
## themselves; armour and hull only change when the ship is hit. For a ship the
## player owns, armour and hull are mirrored into its ShipCondition so the save
## always sees them. Damage itself is worked out by DamageModel.

## Anything the HUD shows may have changed (a hit landed, a repair, a reset).
signal changed

var state: DefenceState = DefenceState.new()
var energy: float = 0.0
var max_energy: float = 0.0

var _specs: ShipSpecs
var _condition: ShipCondition
## Seconds since the ship was last hit, for the shield recharge delay.
var _since_hit: float = 1000.0


func _process(delta: float) -> void:
	tick(delta)


## Starts the ship as it is now: full shields and energy, and armour and hull as
## the saved condition says (full when it is undamaged or there is none).
func setup(specs: ShipSpecs, condition: ShipCondition = null) -> void:
	_specs = specs
	_condition = condition
	state = DefenceState.full(specs.shield_capacity, specs.armour, specs.hull)
	if condition != null:
		if condition.armour >= 0.0:
			state.armour = minf(condition.armour, specs.armour)
		if condition.hull >= 0.0:
			state.hull = clampf(condition.hull, 1.0, specs.hull)
	max_energy = specs.energy_capacity
	energy = max_energy
	_since_hit = 1000.0
	changed.emit()


## Recharges shields (after their delay) and energy. Public so tests can step time.
func tick(delta: float) -> void:
	if _specs == null:
		return
	_since_hit += delta
	if _since_hit >= _specs.shield_regen_delay and state.shield < state.max_shield:
		state.shield = minf(state.max_shield, state.shield + _specs.shield_regen * delta)
	if energy < max_energy:
		energy = minf(max_energy, energy + _specs.energy_regen * delta)


## Applies a hit and returns what it did.
func apply(hit: Hit, rules: DamageRules) -> DamageResult:
	var result := DamageModel.resolve(state, hit, rules)
	_since_hit = 0.0
	_sync_condition()
	changed.emit()
	return result


## Takes `amount` of energy if there is enough. False (and nothing taken) if not.
func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	return true


func restore_shields() -> void:
	state.shield = state.max_shield
	changed.emit()


## Armour and hull back to full (a repair).
func repair_fully() -> void:
	state.armour = state.max_armour
	state.hull = state.max_hull
	_sync_condition()
	changed.emit()


func _sync_condition() -> void:
	if _condition == null:
		return
	_condition.armour = state.armour if state.armour < state.max_armour else ShipCondition.FULL
	_condition.hull = state.hull if state.hull < state.max_hull else ShipCondition.FULL
