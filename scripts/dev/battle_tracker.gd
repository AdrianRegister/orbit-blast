class_name BattleTracker
extends Node
## DEVELOPMENT ONLY. Keeps score of a sandbox battle between two sides (0 = A, 1 = B): how many
## ships each side has left, how strong they are (CombatRating), how many it has lost, how many
## got away, how many kills it has made, how long the battle has gone on, and who has won. The
## battle panel's readout and the headless balancing harness both read it, so there is one
## definition of "who won".
##
## A ship is IN THE FIGHT while it is alive and has not started to jump out. One that jumped out
## has WITHDRAWN (it is gone from the fight but was not destroyed). A side is beaten when it has
## no ship left in the fight. The battle is over when a side is beaten: the other side wins,
## or it is a draw if both are beaten at once.

## The battle is decided (emitted once, with the winner: &"a", &"b" or &"draw").
signal finished(winner: StringName)

const SIDE_A := 0
const SIDE_B := 1

## The time the battle has run for, in game seconds (it stops when the battle is decided or
## while `running` is off).
var elapsed: float = 0.0
## Whether the clock runs (the battle builder starts battles held, and starts the clock with them).
var running: bool = true

## side -> the ships (untyped: ships get freed), and what is known about each by its combat id.
var _ships: Array = [[], []]
var _rating_of_id: Dictionary = {}
var _side_of_id: Dictionary = {}
var _destroyed: Dictionary = {}  # combat id -> true
var _kills: Array[int] = [0, 0]
var _start_count: Array[int] = [0, 0]
var _start_rating: Array[float] = [0.0, 0.0]
var _winner: StringName = &""
var _connected_to: CombatManager


## Starts listening for ships being destroyed. Call once, with the game's CombatManager.
func listen_to(combat: CombatManager) -> void:
	if _connected_to == combat:
		return
	_connected_to = combat
	combat.ship_destroyed.connect(_on_ship_destroyed)


## Puts `ships` (NpcShips) on `side`. Call after spawning, before the battle starts.
func track(side: int, ships: Array) -> void:
	for ship in ships:
		_ships[side].append(ship)
		var id: StringName = ship.combat_id
		_side_of_id[id] = side
		_rating_of_id[id] = CombatRating.of(ship.ship_type.stats)
		_start_count[side] += 1
		_start_rating[side] += _rating_of_id[id]


## Forgets everything: a new battle begins.
func clear() -> void:
	_ships = [[], []]
	_rating_of_id.clear()
	_side_of_id.clear()
	_destroyed.clear()
	_kills = [0, 0]
	_start_count = [0, 0]
	_start_rating = [0.0, 0.0]
	_winner = &""
	elapsed = 0.0


## Whether any ship is being tracked.
func has_battle() -> bool:
	return _start_count[SIDE_A] + _start_count[SIDE_B] > 0


func _physics_process(delta: float) -> void:
	if not has_battle() or _winner != &"":
		return
	if running:
		elapsed += delta
	_decide()


# ------------------------------------------------------------------- reading

## Ships of `side` still in the fight.
func alive_count(side: int) -> int:
	var count := 0
	for ship in _ships[side]:
		if _in_the_fight(ship):
			count += 1
	return count


## The strength (CombatRating) of the ships of `side` still in the fight.
func rating_left(side: int) -> float:
	var total := 0.0
	for ship in _ships[side]:
		if _in_the_fight(ship):
			total += _rating_of_id.get(ship.combat_id, 0.0)
	return total


## How many ships of `side` were destroyed.
func lost_count(side: int) -> int:
	var count := 0
	for id in _side_of_id:
		if _side_of_id[id] == side and _destroyed.has(id):
			count += 1
	return count


## How many ships of `side` got away (jumped out, or were removed) without being destroyed.
func withdrawn_count(side: int) -> int:
	return _start_count[side] - alive_count(side) - lost_count(side)


## How many enemy ships `side`'s ships have destroyed.
func kills(side: int) -> int:
	return _kills[side]


func start_count(side: int) -> int:
	return _start_count[side]


func start_rating(side: int) -> float:
	return _start_rating[side]


## The side (0 or 1) a ship is tracked on, or -1 if it is in no battle.
func side_of(ship) -> int:
	return _side_of_id.get(ship.combat_id, -1)


## &"" while the battle goes on (or there is none), then &"a", &"b" or &"draw".
func winner() -> StringName:
	_decide()
	return _winner


## One line per side for the readout: "A: 5 of 6 ships, strength 820 of 1,000, 2 lost, 1 away, 3 kills".
func describe_side(side: int) -> String:
	return "%s: %d of %d ships, strength %d of %d, %d lost, %d away, %d kills" % [
			"AB"[side], alive_count(side), _start_count[side], roundi(rating_left(side)),
			roundi(_start_rating[side]), lost_count(side), withdrawn_count(side), _kills[side]]


# ------------------------------------------------------------------- internals

func _in_the_fight(ship) -> bool:
	if not is_instance_valid(ship) or ship.is_queued_for_deletion():
		return false
	return ship.get_combatant().is_alive() and ship.state != NpcShip.State.WARPING


func _decide() -> void:
	if _winner != &"" or not has_battle():
		return
	var a := alive_count(SIDE_A)
	var b := alive_count(SIDE_B)
	if a > 0 and b > 0:
		return
	_winner = &"draw" if a == 0 and b == 0 else (&"a" if a > 0 else &"b")
	finished.emit(_winner)


func _on_ship_destroyed(report: DestructionReport) -> void:
	if not _side_of_id.has(report.victim_id):
		return
	_destroyed[report.victim_id] = true
	var killer_side: int = _side_of_id.get(report.attacker_id, -1)
	if killer_side >= 0 and killer_side != _side_of_id[report.victim_id]:
		_kills[killer_side] += 1
