class_name FleetSpawner
extends RefCounted
## Builds formations of NPC ships into a star system. It creates the ships, picks
## the leader, makes the Formation and snaps everyone into position. What it does
## not decide is what the group is (see FleetComposer, step 4) or when to spawn one
## (traffic, step 6, and the combat sandbox's dev panel).

const NPC_SCENE := preload("res://scenes/ships/npc_ship.tscn")


## Spawns one formation: a ship for each type in `ship_types`, in `shape`, with the
## leader at `at` facing `heading` (radians). The leader flies around the centre of
## the system within `wander_radius`, or around the points of `patrol` in order if
## given (it follows no route here; traffic gives leaders routes). Returns the
## formation. Ships belong to `faction_id` ("" = nobody).
static func spawn_formation(system: StarSystem, player: Node2D, config: TrafficConfig,
		kind: Formation.Kind, shape: FormationShape, ship_types: Array[ShipType],
		at: Vector2, heading: float, faction_id: StringName = &"",
		wander_radius: float = 700.0, tuning: FormationTuning = null,
		patrol: Array[Vector2] = []) -> Formation:
	var ships: Array[NpcShip] = []
	var no_places: Array[InhabitedNode] = []
	for type in ship_types:
		var ship: NpcShip = NPC_SCENE.instantiate()
		ship.setup(type, config, no_places, "", null, player)
		ship.combat_id = TrafficManager.new_combat_id()
		ship.faction_id = faction_id
		ship.configure_jumping(system.global_position, system.jump_radius, [])
		ships.append(ship)

	var lead := choose_lead(kind, ships)
	var formation := Formation.new()
	formation.name = "Formation"
	for ship in ships:
		if ship != lead:
			ship.join_formation(formation)
	if patrol.is_empty():
		lead.begin_wandering(system.global_position, wander_radius)
	else:
		lead.begin_patrol(patrol)

	for ship in ships:
		system.get_ships_root().add_child(ship)
	system.get_formations_root().add_child(formation)
	formation.setup(kind, shape, ships, lead, system, player, tuning, faction_id)
	formation.place_at(at, heading)
	return formation


## Who leads: the strongest ship, except that a convoy is led by its strongest
## freighter (the middle of a convoy is its freighters).
static func choose_lead(kind: Formation.Kind, ships: Array[NpcShip]) -> NpcShip:
	var best: NpcShip = null
	var best_rating := -INF
	var cargo_only := false
	if kind == Formation.Kind.CONVOY:
		for ship in ships:
			var model := ship.ship_type.stats
			if model.ship_class != null and model.ship_class.carries_cargo():
				cargo_only = true
	for ship in ships:
		var model := ship.ship_type.stats
		if cargo_only and not (model.ship_class != null and model.ship_class.carries_cargo()):
			continue
		var rating := CombatRating.of(model)
		if rating > best_rating:
			best_rating = rating
			best = ship
	return best
