class_name ShipClass
extends Resource
## A kind of ship by its role: fighter, heavy fighter, gunboat, corvette,
## frigate, cruiser, capital ship, freighter, and any others added later. One
## .tres per class in resources/ship_classes/; a ship model (ShipStats) names its
## class with `ship_class`.
##
## A class is what a ship IS, a category set by the designer, not code. Nothing
## names a class id: behaviour comes from the fields below and from recipes (see
## FormationRecipe), so a new class, or a new ship of an existing class such as the
## Hegemony gunboat, is a new data file and no code change. Classes form a
## hierarchy the same way SystemClass does: a class can name a `parent`, and
## `is_a()` asks whether a class is, or belongs to, another. The abstract parents
## (warship, cargo ship) have no ships of their own; they let a rule say "any
## cargo ship" and pick up new freighter classes by themselves.

## Permanent unique id, e.g. &"heavy_fighter". Never change it once content
## refers to it.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## The class this is a kind of (a frigate is a warship). Null for a top level class.
@export var parent: ShipClass

## Size order, smallest first: 0 light craft, 1 medium, 2 large, 3 heavy, 4 capital.
## Used to rank ships by size, for example to give the heaviest escort the front slot.
@export_range(0, 10) var tier: int = 0

## Whether ships of this class (or of a subclass) carry freight.
@export var cargo: bool = false
## Whether ships of this class are capital ships (a fleet's flagship is one).
@export var capital: bool = false
## Whether ships of this class are nimble enough to slip past medium and heavy
## weapons: every shot from a medium or large weapon passes through them, so only
## light weapons can hurt them (fighters and heavy fighters).
@export var evades_heavy_fire: bool = false


## Whether this class is `other`, or a kind of it: a frigate is_a frigate and
## is_a warship. Null is nothing.
func is_a(other: ShipClass) -> bool:
	if other == null:
		return false
	var current: ShipClass = self
	for step in 16:  # (the depth limit guards against a loop in bad data)
		if current == null:
			return false
		if current == other or (current.id != &"" and current.id == other.id):
			return true
		current = current.parent
	return false


## Whether ships of this class carry freight: its own flag or a parent's.
func carries_cargo() -> bool:
	var current: ShipClass = self
	for step in 16:
		if current == null:
			return false
		if current.cargo:
			return true
		current = current.parent
	return false


## Whether ships of this class are capital ships: its own flag or a parent's.
func is_capital() -> bool:
	var current: ShipClass = self
	for step in 16:
		if current == null:
			return false
		if current.capital:
			return true
		current = current.parent
	return false


## Whether ships of this class slip past medium and heavy weapons: its own flag or
## a parent's.
func is_evasive() -> bool:
	var current: ShipClass = self
	for step in 16:
		if current == null:
			return false
		if current.evades_heavy_fire:
			return true
		current = current.parent
	return false


## Human-readable problems with this class; empty when it is valid.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	var seen: Array[ShipClass] = []
	var current: ShipClass = parent
	while current != null:
		if current == self or seen.has(current):
			problems.append("the parent chain loops back on itself")
			break
		seen.append(current)
		current = current.parent
	return problems
