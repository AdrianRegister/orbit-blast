class_name FleetSpawner
extends RefCounted
## Builds formations and fleets of NPC ships into a star system. It creates the
## ships, picks the leaders, makes the Formations (a squadron's inside its battle
## group's) and the WarFleet, and puts everyone in place. What it does not decide
## is what a unit is made of (FleetComposer does, from a recipe) or when to spawn one
## (traffic, step 6, and the combat sandbox's dev panel).

const NPC_SCENE := preload("res://scenes/ships/npc_ship.tscn")
## A fleet's other parts are laid out in an arc this wide, behind the flagship.
const FLEET_ARC := deg_to_rad(200.0)


## Spawns one formation of `ship_types` (no sub-units): a ship for each type, in
## `shape`, with the leader at `at` facing `heading` (radians). The leader flies around
## the centre of the system within `wander_radius`, or around the points of `patrol`
## in order if given (it follows no route here; traffic gives leaders routes).
## Returns the formation. Ships belong to `faction_id` ("" = nobody).
static func spawn_formation(system: StarSystem, player: Node2D, config: TrafficConfig,
		kind: Formation.Kind, shape: FormationShape, ship_types: Array[ShipType],
		at: Vector2, heading: float, faction_id: StringName = &"",
		wander_radius: float = 700.0, tuning: FormationTuning = null,
		patrol: Array[Vector2] = []) -> Formation:
	var ships: Array[NpcShip] = []
	for type in ship_types:
		ships.append(_make_ship(type, system, player, config, faction_id))

	var lead := choose_lead(kind, ships)
	var formation := Formation.new()
	formation.name = "Formation"
	for ship in ships:
		if ship != lead:
			ship.join_formation(formation)
	_start_route(lead, system, wander_radius, patrol)

	for ship in ships:
		system.get_ships_root().add_child(ship)
	system.get_formations_root().add_child(formation)
	formation.setup(kind, shape, ships, lead, system, player, tuning, faction_id)
	formation.place_at(at, heading)
	return formation


## Spawns the unit a plan describes: a squadron, a battle group (its squadrons
## nested inside) or a convoy, which is returned as a Formation, or a fleet, returned
## as a WarFleet. `at` is where the (flagship or) leader appears. Its leader flies
## around the system centre, or around `patrol` if given; a fleet's parts each fly
## their own and keep to the leash. `shape` replaces the plan's shape for the
## outermost formation. Null if the plan cannot be built.
static func spawn_plan(system: StarSystem, player: Node2D, config: TrafficConfig, plan: FormationPlan,
		at: Vector2, heading: float, faction_id: StringName = &"", wander_radius: float = 700.0,
		tuning: FormationTuning = null, patrol: Array[Vector2] = [], shape: FormationShape = null) -> Node:
	if plan == null or plan.recipe == null:
		return null
	if plan.recipe.unit == FormationRecipe.Unit.FLEET:
		return _spawn_fleet(system, player, config, plan, at, heading, faction_id, wander_radius, tuning, patrol)
	var built := _build(plan, system, player, config, faction_id, shape)
	if built.is_empty():
		return null
	_start_route(built["lead"], system, wander_radius, patrol)
	_enter(built, system, player, tuning, faction_id)
	_place(built, at, heading)
	return built["formation"]


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


# ------------------------------------------------------------------ internals

static func _make_ship(type: ShipType, system: StarSystem, player: Node2D, config: TrafficConfig,
		faction_id: StringName) -> NpcShip:
	var ship: NpcShip = NPC_SCENE.instantiate()
	var no_places: Array[InhabitedNode] = []
	ship.setup(type, config, no_places, "", null, player)
	ship.combat_id = TrafficManager.new_combat_id()
	ship.faction_id = faction_id
	ship.configure_jumping(system.global_position, system.jump_radius, [])
	return ship


static func _start_route(lead: NpcShip, system: StarSystem, wander_radius: float, patrol: Array[Vector2]) -> void:
	if patrol.is_empty():
		lead.begin_wandering(system.global_position, wander_radius)
	else:
		lead.begin_patrol(patrol)


## Creates the ships and the Formation objects of a plan and its sub-units (not yet
## in the tree): {"formation", "kind", "shape", "ships" (its own), "members" (the
## ships its formation holds, a sub-unit's leader included), "lead", "subs" (the
## same for each sub-unit)}. Empty if the plan has no ships of its own to lead it.
static func _build(plan: FormationPlan, system: StarSystem, player: Node2D, config: TrafficConfig,
		faction_id: StringName, shape: FormationShape = null) -> Dictionary:
	var ships: Array[NpcShip] = []
	for type in plan.ships:
		ships.append(_make_ship(type, system, player, config, faction_id))
	if ships.is_empty():
		return {}
	var kind := plan.recipe.formation_kind()
	var lead := choose_lead(kind, ships)
	var formation := Formation.new()
	formation.name = "Formation"
	var members: Array[NpcShip] = []
	members.append_array(ships)
	var subs: Array[Dictionary] = []
	for child in plan.children:
		var inner := _build(child, system, player, config, faction_id)
		if inner.is_empty():
			continue
		subs.append(inner)
		members.append(inner["lead"])
	for ship in members:
		if ship != lead:
			ship.join_formation(formation)
	return {"formation": formation, "kind": kind, "shape": shape if shape != null else plan.shape,
			"ships": ships, "members": members, "lead": lead, "subs": subs}


## Puts a built unit in the tree, its sub-units first (a battle group sets up with
## its squadrons already in existence).
static func _enter(built: Dictionary, system: StarSystem, player: Node2D, tuning: FormationTuning,
		faction_id: StringName) -> void:
	for ship in built["ships"]:
		system.get_ships_root().add_child(ship)
	for inner in built["subs"]:
		_enter(inner, system, player, tuning, faction_id)
	var formation: Formation = built["formation"]
	system.get_formations_root().add_child(formation)
	formation.setup(built["kind"], built["shape"], built["members"], built["lead"], system, player, tuning, faction_id)


## Snaps a built unit into its shape with the leader at `at`, then each sub-unit into
## its own shape around its leader.
static func _place(built: Dictionary, at: Vector2, heading: float) -> void:
	(built["formation"] as Formation).place_at(at, heading)
	for inner in built["subs"]:
		_place(inner, (inner["lead"] as NpcShip).global_position, heading)


static func _spawn_fleet(system: StarSystem, player: Node2D, config: TrafficConfig, plan: FormationPlan,
		at: Vector2, heading: float, faction_id: StringName, wander_radius: float,
		tuning: FormationTuning, patrol: Array[Vector2]) -> WarFleet:
	var tune := tuning if tuning != null else FormationTuning.shared()
	var capitals: Array[NpcShip] = []
	for type in plan.ships:
		capitals.append(_make_ship(type, system, player, config, faction_id))
	if capitals.is_empty():
		return null
	var flagship := choose_lead(Formation.Kind.SQUADRON, capitals)
	var groups: Array[Dictionary] = []
	for child in plan.children:
		var built := _build(child, system, player, config, faction_id)
		if not built.is_empty():
			groups.append(built)

	# Every part flies its own route (the leash holds them together).
	var others: Array[NpcShip] = []
	for ship in capitals:
		_start_route(ship, system, wander_radius, patrol)
		if ship != flagship:
			others.append(ship)
	for built in groups:
		_start_route(built["lead"], system, wander_radius, patrol)

	for ship in capitals:
		system.get_ships_root().add_child(ship)
	var formations: Array[Formation] = []
	for built in groups:
		_enter(built, system, player, tuning, faction_id)
		formations.append(built["formation"])

	# Lay the parts out in an arc behind the flagship, far enough apart not to overlap.
	var extents: Array[float] = []
	for ship in others:
		extents.append(ship.get_hit_radius())
	for group in formations:
		extents.append(group.get_extent())
	var radius := _arc_radius(flagship.get_hit_radius(), extents, tune.fleet_unit_gap)
	var biggest := 0.0
	for extent in extents:
		biggest = maxf(biggest, extent)
	var fleet := WarFleet.new()
	fleet.name = "WarFleet"
	system.get_formations_root().add_child(fleet)
	fleet.setup(system, player, flagship, others, formations, maxf(tune.fleet_cohesion_radius, radius + biggest + tune.fleet_unit_gap), tune)

	flagship.global_position = at
	flagship.set_heading(heading)
	flagship.velocity = Vector2.ZERO
	var count := extents.size()
	for index in count:
		var angle := heading + PI
		if count > 1:
			angle += (float(index) / float(count - 1) - 0.5) * FLEET_ARC
		var position := at + Vector2.from_angle(angle) * radius
		if index < others.size():
			others[index].global_position = position
			others[index].set_heading(heading)
			others[index].velocity = Vector2.ZERO
		else:
			var built: Dictionary = groups[index - others.size()]
			_place(built, position, heading)
	return fleet


## How far from the flagship the other parts of a fleet stand: far enough that each
## clears the flagship and its neighbours in the arc by `gap`.
static func _arc_radius(flagship_radius: float, extents: Array[float], gap: float) -> float:
	var radius := 0.0
	for extent in extents:
		radius = maxf(radius, flagship_radius + extent + gap)
	if extents.size() >= 2:
		var half_step := FLEET_ARC / float(extents.size() - 1) * 0.5
		for index in extents.size() - 1:
			radius = maxf(radius, (extents[index] + extents[index + 1] + gap) / (2.0 * sin(half_step)))
	return radius
