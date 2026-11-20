class_name CombatSandbox
extends Node
## DEVELOPMENT ONLY. The combat sandbox: a tiny isolated game for trying combat
## features by hand. Started from the main menu (DEV COMBAT SANDBOX).
##
## It is the normal game (main.tscn) with `Main.sandbox_mode` on and three
## things swapped in: a single made-up star system (`combat_sandbox_system.tscn`,
## not on the galaxy map and with no traffic), a starting ship and money, and a
## planet whose shipyard sells every ship and whose outfitter sells every upgrade
## and weapon. The lists are filled from the content registry when the sandbox
## starts, so new ships, upgrades and weapons appear by themselves.
##
## This node is a child of that Main. The system starts empty: ships come from the dev
## panels (formations, battles). Nothing is saved and no reputation is ever charged.
##
## To change what the sandbox contains, edit the constants below (the player's
## ship, money) or the scene `scenes/dev/combat_sandbox_system.tscn`.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const SYSTEM_SCENE := preload("res://scenes/dev/combat_sandbox_system.tscn")
const PLANET_DATA := preload("res://resources/dev/sandbox_planet.tres")
const NPC_SCENE := preload("res://scenes/ships/npc_ship.tscn")
const TRAFFIC_CONFIG := preload("res://resources/traffic/default_traffic.tres")

## What the player starts with.
const PLAYER_SHIP := preload("res://resources/ships/light_frigate_stats.tres")
const PLAYER_CREDITS := 500_000_000
## Where the player starts (the planet is at (1500, 0)).
const PLAYER_START := Vector2(900.0, 500.0)

## Formations the dev panel can spawn in one go: a name, the ship models, the
## shape to start with and the kind of group. Add a line to add a preset.
const GROUP_PRESETS := [
	{"name": "Squadron: heavy fighter + 3 fighters", "kind": Formation.Kind.SQUADRON, "shape": &"wedge",
			"ships": [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"]},
	{"name": "Battle group: cruiser, 2 frigates, 3 fighters", "kind": Formation.Kind.BATTLE_GROUP, "shape": &"screen",
			"ships": [&"federation_cruiser", &"federation_frigate", &"federation_frigate", &"federation_fighter", &"federation_fighter", &"federation_fighter"]},
	{"name": "Convoy: 2 freighters, 3 interceptors, light frigate", "kind": Formation.Kind.CONVOY, "shape": &"convoy",
			"ships": [&"bulk_freighter", &"freighter", &"interceptor", &"interceptor", &"interceptor", &"light_frigate"]},
]
## How far ahead of the player a formation appears, and how far its leader
## drifts from the system centre.
const FORMATION_SPAWN_DISTANCE := 900.0
## The faction composed units belong to (the recipes' own-faction ships are its).
const COMPOSED_FACTION := &"faction_1"
## How far ahead of the player a composed unit appears, by kind (big units are wide).
const COMPOSED_DISTANCE := {
	FormationRecipe.Unit.SQUADRON: 900.0,
	FormationRecipe.Unit.CONVOY: 1000.0,
	FormationRecipe.Unit.BATTLE_GROUP: 1500.0,
	FormationRecipe.Unit.FLEET: 2800.0,
}
const FORMATION_WANDER_RADIUS := 700.0
## The battle builder: how far apart the two sides start, how far ahead of the
## player the middle of the battle is, how far apart ships of a side are (as a
## multiple of their hit radius), and how far they drift before the AI takes over.
const BATTLE_SEPARATION := 1000.0
const BATTLE_DISTANCE := 700.0
const BATTLE_SPACING_FACTOR := 3.0
## How far behind the rank in front each rank of a mixed force starts (pixels).
const BATTLE_RANK_SPACING := 350.0
const BATTLE_DRIFT_RADIUS := 300.0
## How far behind the one before a composed unit of each kind starts, and how far apart two sides
## carrying such units must be (a fleet is wide).
const UNIT_DEPTH := {
	FormationRecipe.Unit.SQUADRON: 600.0, FormationRecipe.Unit.BATTLE_GROUP: 1500.0,
	FormationRecipe.Unit.FLEET: 3000.0, FormationRecipe.Unit.CONVOY: 900.0,
}
const UNIT_SEPARATION := {
	FormationRecipe.Unit.SQUADRON: 1500.0, FormationRecipe.Unit.BATTLE_GROUP: 3500.0,
	FormationRecipe.Unit.FLEET: 9000.0, FormationRecipe.Unit.CONVOY: 2000.0,
}
## The player's standing with a side's faction and the other's, when the stance uses reputation.
const STANCE_FRIENDLY := 60
const STANCE_HOSTILE := -80
## The ways out of the system the battle's ships know (the four directions), so a ship
## that retreats can jump out as it would in the real game.
const BATTLE_EXITS: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
## Battles the battle panel can spawn in one go (the table is in battle_presets.gd).
const BATTLE_PRESETS := BattlePresets.PRESETS

var _main: Main
var _system: StarSystem
var _registry: ContentRegistry
var _panel: SandboxPanel
var _battle_panel: BattlePanel
var _toolbar: DevToolbar
var _tracker: BattleTracker
var _readout: BattleReadout
var _overlay: BattleOverlay
## Who the player stands with in a battle (see set_player_stance).
enum Stance { NEUTRAL, SIDE_A, SIDE_B }
var _stance: Stance = Stance.NEUTRAL
var _stance_uses_reputation: bool = true
## The faction ids of the two sides of the battle spawned last ("" for none).
var _battle_factions: Array[StringName] = [&"", &""]
## The reputation values the sandbox set for the stance: faction id -> the amount it added.
var _stance_changes: Dictionary = {}
var _held: bool = false
## The ships the battle builder has spawned.
var _battle_ships: Array = []
## The formations the battle builder made (their ships are in _battle_ships too).
var _battle_formations: Array = []
## What the last composed unit was made of (for the panel to show).
var last_plan: FormationPlan


## A ready-to-add game in sandbox mode. The caller adds it to the scene tree.
static func build_main() -> Main:
	var main: Main = MAIN_SCENE.instantiate()
	main.sandbox_mode = true
	main.starting_ship_stats = PLAYER_SHIP
	main.starting_credits = PLAYER_CREDITS
	# Nothing is ever saved from the sandbox; this only keeps it away from the real save.
	main.get_node("Save").save_path = "user://dev_sandbox_unused.json"

	# Replace the first star system with the sandbox's.
	var old_system := main.get_node("StarSystem")
	main.remove_child(old_system)
	old_system.free()
	var system: StarSystem = SYSTEM_SCENE.instantiate()
	system.name = "StarSystem"
	main.add_child(system)
	main.move_child(system, 0)

	var planet := _stocked_planet()
	system.get_node("Objects/ProvingGround").data = planet
	main.fallback_respawn = planet  # a destroyed player wakes up here
	main.get_node("PlayerShip").position = PLAYER_START

	main.add_child(CombatSandbox.new())
	return main


## The sandbox planet with every ship, upgrade and weapon on sale.
static func _stocked_planet() -> PlanetData:
	var registry := ContentRegistry.new()
	var planet: PlanetData = PLANET_DATA.duplicate()
	planet.shipyard_ships = registry.all_ship_stats()
	planet.outfitter_upgrades = registry.all_upgrades()
	planet.outfitter_weapons = registry.all_weapons()
	return planet


func _ready() -> void:
	# Main finishes setting itself up after its children; start once it has.
	_start.call_deferred()


func _start() -> void:
	_main = get_parent() as Main
	_system = _main.get_system()
	_registry = ContentRegistry.new()
	_tracker = BattleTracker.new()
	_tracker.name = "BattleTracker"
	add_child(_tracker)
	_tracker.listen_to(_main.get_node("Combat") as CombatManager)
	_panel = SandboxPanel.new()
	_main.add_child(_panel)
	_panel.setup(self, _registry)
	_battle_panel = BattlePanel.new()
	_main.add_child(_battle_panel)
	_battle_panel.setup(self, _registry)
	_toolbar = DevToolbar.new()
	_main.add_child(_toolbar)
	_readout = BattleReadout.new()
	_main.add_child(_readout)
	_readout.setup(self, _registry)
	_overlay = BattleOverlay.new()
	_overlay.setup(self, _system)
	_toolbar.setup(self, [
		{"name": "FORMATIONS", "key": KEY_F2, "panel": _panel},
		{"name": "BATTLE", "key": KEY_F3, "panel": _battle_panel},
		{"name": "OVERLAY", "key": KEY_F4, "toggle": func(on: bool) -> void: _overlay.visible = on},
	])


## Whether the player is flying (not docked): the panel only shows then.
func is_flying() -> bool:
	return (_main.get_node("GameState") as GameStateManager).state == GameStateManager.State.FLYING


# ------------------------------------------------------------- formations

## Spawns a formation of the named ship models ahead of the player, in `shape`. Its
## leader drifts around the centre of the system.
func spawn_formation(shape: FormationShape, ship_ids: Array, kind: Formation.Kind, faction: StringName = &"",
		at: Variant = null, heading: float = NAN, profile: TacticalProfile = null) -> Formation:
	var types: Array[ShipType] = []
	for id in ship_ids:
		var type := ShipType.new()
		type.stats = _registry.ship_stats(id)
		types.append(type)
	var player := _main.get_player_ship()
	if at == null:
		at = player.global_position + Vector2.from_angle(player.rotation) * FORMATION_SPAWN_DISTANCE
	if is_nan(heading):
		heading = player.rotation
	return FleetSpawner.spawn_formation(_system, player, TRAFFIC_CONFIG, kind, shape, types, at,
			heading, faction, FORMATION_WANDER_RADIUS, null, [], profile)


## Composes a unit from `recipe` (who goes in is drawn at random within the recipe's
## rules) and spawns it ahead of the player: a Formation for a squadron, battle
## group or convoy, a WarFleet for a fleet. `shape` replaces the drawn shape and
## `faction` (default COMPOSED_FACTION) says whose ships they are, and `profile` (null: the
## recipe's own) how the unit fights (a pirate squadron is a squadron with the pirate profile).
func spawn_composed(recipe: FormationRecipe, shape: FormationShape = null, faction: StringName = &"",
		profile: TacticalProfile = null) -> Node:
	if faction == &"":
		faction = COMPOSED_FACTION
	var plan := FleetComposer.compose(recipe, faction, FleetComposer.all_ship_types())
	if plan == null:
		push_warning("The %s recipe cannot be built from the ships that exist." % recipe.display_name)
		return null
	last_plan = plan
	var player := _main.get_player_ship()
	var distance: float = COMPOSED_DISTANCE.get(recipe.unit, FORMATION_SPAWN_DISTANCE)
	var at := player.global_position + Vector2.from_angle(player.rotation) * distance
	return FleetSpawner.spawn_plan(_system, player, TRAFFIC_CONFIG, plan, at, player.rotation,
			faction, FORMATION_WANDER_RADIUS, null, [], shape, profile)


## The formation of the ship the player has targeted (as a member or leader).
func get_selected_formation() -> Formation:
	var target := (_main.get_node("Targeting") as TargetingManager).current_target
	var ship: NpcShip = target.get_parent() as NpcShip if target != null else null
	if ship == null:
		return null
	var found: Formation = ship.formation if ship.formation != null else ship.led_formation
	return found if found != null and is_instance_valid(found) else null


## Destroys a ship with one overwhelming hit (null does nothing).
func kill_ship(ship: NpcShip) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var hit := Hit.new()
	hit.damage = 1000000.0
	ship.get_combatant().take_hit(hit)


## Removes every formation and fleet and their ships.
func clear_formations() -> void:
	for unit in _system.get_formations_root().get_children():
		var ships: Array[NpcShip] = []
		if unit is Formation:
			ships = (unit as Formation).get_all_ships()
		elif unit is WarFleet:
			ships = (unit as WarFleet).get_all_ships()
		for ship in ships:
			ship.queue_free()
		unit.queue_free()


# ------------------------------------------------------------------ battles

## Spawns two sides facing each other ahead of the player (see BattlePresets for what a side
## can be). Returns {"a": ships, "b": ships}. The ships carry their faction, their default weapons
## and the same combat rules as any other ship, and the AI takes over at once. `options`:
##   "held": the battle starts frozen until start_battle() (default: no)
##   "anchor": the point the battle is centred on (default: ahead of the player)
## The ships are put on the BattleTracker (sides A and B), and the player's stance is applied.
func spawn_battle(side_a: Dictionary, side_b: Dictionary, options: Dictionary = {}) -> Dictionary:
	var player := _main.get_player_ship()
	var forward := Vector2.from_angle(player.rotation)
	var across := forward.rotated(PI / 2.0)
	var middle: Vector2 = options.get("anchor", player.global_position + forward * BATTLE_DISTANCE)
	var separation := maxf(BATTLE_SEPARATION, maxf(maxf(side_a.get("separation", 0.0), side_b.get("separation", 0.0)),
			maxf(_required_separation(side_a), _required_separation(side_b))))
	var ships_a := _spawn_side(side_a, middle - across * separation / 2.0, across)
	var ships_b := _spawn_side(side_b, middle + across * separation / 2.0, -across)
	_battle_factions = [side_a.get("faction", &""), side_b.get("faction", &"")]
	if _tracker != null:
		_tracker.track(0, ships_a)
		_tracker.track(1, ships_b)
	_apply_stance()
	hold_battle(options.get("held", false))
	return {"a": ships_a, "b": ships_b}


## How far apart the two sides must start for the units on side `side` (a fleet is wide).
func _required_separation(side: Dictionary) -> float:
	var needed := 0.0
	for unit in side.get("units", []):
		if unit.has("recipe"):
			var recipe := _registry.formation_recipe(unit["recipe"])
			needed = maxf(needed, UNIT_SEPARATION.get(recipe.unit, 0.0) if recipe != null else 0.0)
	return needed


# ------------------------------------------------------------ held battles and the player's side

## Freezes (or releases) every ship of the battles spawned, and the units that command them.
## While held nothing moves, thinks or fires; the battle clock stops too.
func hold_battle(held: bool) -> void:
	_held = held
	var mode := Node.PROCESS_MODE_DISABLED if held else Node.PROCESS_MODE_INHERIT
	for node in _battle_nodes():
		node.process_mode = mode
	if _tracker != null:
		_tracker.running = not held


## Releases a held battle.
func start_battle() -> void:
	hold_battle(false)


func is_battle_held() -> bool:
	return _held


## Every node that makes a battle's ships act: the ships, their formations and fleets.
func _battle_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for ship in _battle_ships:
		if not is_instance_valid(ship):
			continue
		nodes.append(ship)
		for unit in [ship.formation, ship.led_formation, ship.fleet]:
			if unit != null and is_instance_valid(unit) and not nodes.has(unit):
				nodes.append(unit)
	for unit in _battle_formations:
		if is_instance_valid(unit) and not nodes.has(unit):
			nodes.append(unit)
	return nodes


func get_tracker() -> BattleTracker:
	return _tracker


## The faction ids of the two sides of the battle spawned last ("" for none).
func get_battle_factions() -> Array[StringName]:
	return _battle_factions


func get_overlay() -> BattleOverlay:
	return _overlay


## Puts the player on a side of the battle: NEUTRAL, SIDE_A or SIDE_B. With reputation switched on
## (the default, see set_stance_uses_reputation) that sets the player's standing with the two
## sides' factions: Friendly with their own side's, Hostile with the other's, so the battle's AI
## treats them as an ally or an enemy by the real rules. Nothing the player does is ever charged.
func set_player_stance(stance: Stance) -> void:
	_stance = stance
	_apply_stance()


func get_player_stance() -> Stance:
	return _stance


## Whether the stance is carried out through reputation (on) or ignored (off: the player is
## neutral to everybody).
func set_stance_uses_reputation(enabled: bool) -> void:
	_stance_uses_reputation = enabled
	_apply_stance()


func _apply_stance() -> void:
	_restore_reputation()
	var combat := _main.get_node("Combat") as CombatManager
	if not _stance_uses_reputation or _stance == Stance.NEUTRAL:
		combat.set_standing_source(null)
		return
	var reputation := _main.get_node("Reputation") as ReputationManager
	var mine: StringName = _battle_factions[0 if _stance == Stance.SIDE_A else 1]
	var theirs: StringName = _battle_factions[1 if _stance == Stance.SIDE_A else 0]
	if mine != &"" and mine != theirs:
		_set_standing(reputation, mine, STANCE_FRIENDLY)
	if theirs != &"" and theirs != mine:
		_set_standing(reputation, theirs, STANCE_HOSTILE)
	combat.set_standing_source(reputation)


func _set_standing(reputation: ReputationManager, faction_id: StringName, value: int) -> void:
	var faction := _registry.faction(faction_id)
	if faction == null:
		return
	var before := reputation.get_reputation(faction)
	reputation.change(faction, value - before, "combat sandbox stance")
	_stance_changes[faction_id] = reputation.get_reputation(faction) - before


## Puts back the reputation the stance changed.
func _restore_reputation() -> void:
	if _stance_changes.is_empty():
		return
	var reputation := _main.get_node("Reputation") as ReputationManager
	for faction_id in _stance_changes:
		var faction := _registry.faction(faction_id)
		if faction != null:
			reputation.change(faction, -_stance_changes[faction_id], "combat sandbox stance")
	_stance_changes.clear()


## One side, all facing `facing`: each kind of ship in a rank (a column across the line
## of battle) through `centre`, the ranks one behind another, the first at the front.
func _spawn_side(side: Dictionary, centre: Vector2, facing: Vector2) -> Array[NpcShip]:
	var ships: Array[NpcShip] = []
	if side.has("units"):
		return _spawn_side_units(side, centre, facing)
	if side.has("plan"):
		return _spawn_side_plan(side, centre, facing)
	if side.has("formation"):
		return _spawn_side_formation(side, centre, facing)
	var entries: Array = side["ships"] if side.has("ships") else [{"model": side["model"], "count": side.get("count", 1)}]
	var along := facing.rotated(PI / 2.0)
	for rank in entries.size():
		var entry: Dictionary = entries[rank]
		var count: int = entry.get("count", 1)
		var type := ShipType.new()
		type.stats = _registry.ship_stats(entry["model"])
		var spacing: float = type.stats.get_hit_radius() * BATTLE_SPACING_FACTOR + 40.0
		var rank_centre := centre - facing * BATTLE_RANK_SPACING * rank
		for index in count:
			var offset := (index - (count - 1) / 2.0) * spacing
			ships.append(spawn_ship(type, side.get("faction", &""), rank_centre + along * offset, facing.angle(), BATTLE_EXITS))
	return ships


## A side made of a list of units, the first at the front, each behind the one before: ships
## in a rank ({"model", "count"}) or a unit composed from a formation recipe ({"recipe", "shape"}).
func _spawn_side_units(side: Dictionary, centre: Vector2, facing: Vector2) -> Array[NpcShip]:
	var ships: Array[NpcShip] = []
	var along := facing.rotated(PI / 2.0)
	var faction: StringName = side.get("faction", &"")
	var profile := _registry.tactical_profile(side.get("profile", &""))
	var depth := 0.0
	for entry: Dictionary in side["units"]:
		var here := centre - facing * depth
		if entry.has("recipe"):
			var recipe := _registry.formation_recipe(entry["recipe"])
			var plan := FleetComposer.compose(recipe, faction, FleetComposer.all_ship_types()) if recipe != null and faction != &"" else null
			if plan == null:
				push_warning("The %s unit cannot be built for faction '%s'." % [entry["recipe"], faction])
				continue
			var shape: FormationShape = _registry.formation_shape(entry["shape"]) if entry.has("shape") else null
			var none: Array[Vector2] = []
			var unit := FleetSpawner.spawn_plan(_system, _main.get_player_ship(), TRAFFIC_CONFIG, plan, here, facing.angle(),
					faction, FORMATION_WANDER_RADIUS, null, none, shape, profile)
			if unit == null:
				continue
			_battle_formations.append(unit)
			for ship in unit.get_all_ships():
				ship.configure_jumping(_system.global_position, _system.jump_radius, BATTLE_EXITS)
				_battle_ships.append(ship)
				ships.append(ship)
			depth += UNIT_DEPTH.get(recipe.unit, BATTLE_RANK_SPACING)
		else:
			var type := ShipType.new()
			type.stats = _registry.ship_stats(entry["model"])
			var count: int = entry.get("count", 1)
			var spacing: float = type.stats.get_hit_radius() * BATTLE_SPACING_FACTOR + 40.0
			for index in count:
				var offset := (index - (count - 1) / 2.0) * spacing
				ships.append(spawn_ship(type, faction, here + along * offset, facing.angle(), BATTLE_EXITS))
			depth += BATTLE_RANK_SPACING
	return ships


## A side that is one unit: a formation, with its commander, facing `facing`.
func _spawn_side_formation(side: Dictionary, centre: Vector2, facing: Vector2) -> Array[NpcShip]:
	var unit: Dictionary = side["formation"]
	var kind: Formation.Kind = unit.get("kind", Formation.Kind.SQUADRON)
	var formation := spawn_formation(_registry.formation_shape(unit["shape"]), unit["ships"], kind, side.get("faction", &""), centre, facing.angle(),
			_registry.tactical_profile(side.get("profile", &"")))
	_battle_formations.append(formation)
	var ships := formation.get_all_ships()
	for ship in ships:
		ship.configure_jumping(_system.global_position, _system.jump_radius, BATTLE_EXITS)
		_battle_ships.append(ship)
	return ships


## A side that is a whole battle group or fleet, built from a hand-written plan.
func _spawn_side_plan(side: Dictionary, centre: Vector2, facing: Vector2) -> Array[NpcShip]:
	var player := _main.get_player_ship()
	var none: Array[Vector2] = []
	var unit := FleetSpawner.spawn_plan(_system, player, TRAFFIC_CONFIG, _plan_from(side["plan"]), centre, facing.angle(),
			side.get("faction", &""), FORMATION_WANDER_RADIUS, null, none, null, _registry.tactical_profile(side.get("profile", &"")))
	_battle_formations.append(unit)
	var ships: Array[NpcShip] = unit.get_all_ships()
	for ship in ships:
		ship.configure_jumping(_system.global_position, _system.jump_radius, BATTLE_EXITS)
		_battle_ships.append(ship)
	return ships


func _plan_from(data: Dictionary) -> FormationPlan:
	var plan := FormationPlan.new()
	plan.recipe = _registry.formation_recipe(data["recipe"])
	for id in data["ships"]:
		var type := ShipType.new()
		type.stats = _registry.ship_stats(id)
		plan.ships.append(type)
	if data.has("shape"):
		plan.shape = _registry.formation_shape(data["shape"])
	for child in data.get("children", []):
		plan.children.append(_plan_from(child))
	return plan


## Spawns battle preset number `index` (see BATTLE_PRESETS).
func spawn_battle_preset(index: int, options: Dictionary = {}) -> Dictionary:
	var preset: Dictionary = BATTLE_PRESETS[index]
	return spawn_battle(preset["a"], preset["b"], options)


## Puts one armed NPC of `type` and `faction_id` at `position`, facing `heading`
## (radians). It drifts around where it started until something takes it over.
## `exit_bearings` are the ways out of the system it knows (none: it cannot leave, so
## a ship that runs just keeps running).
func spawn_ship(type: ShipType, faction_id: StringName, position: Vector2, heading: float,
		exit_bearings: Array[Vector2] = []) -> NpcShip:
	var ship: NpcShip = NPC_SCENE.instantiate()
	var no_places: Array[InhabitedNode] = []
	var faction := _registry.faction(faction_id)
	ship.setup(type, TRAFFIC_CONFIG, no_places, faction.display_name if faction != null else "", null, _main.get_player_ship())
	ship.combat_id = TrafficManager.new_combat_id()
	ship.faction_id = faction_id
	ship.configure_jumping(_system.global_position, _system.jump_radius, exit_bearings)
	ship.begin_wandering(position, BATTLE_DRIFT_RADIUS)
	_system.get_ships_root().add_child(ship)
	ship.global_position = position
	ship.set_heading(heading)
	_battle_ships.append(ship)
	return ship


## Removes every ship the battle builder spawned, forgets the battle's score, and gives the
## player back the reputation the stance had changed.
func clear_battle() -> void:
	_restore_reputation()
	(_main.get_node("Combat") as CombatManager).set_standing_source(null)
	if _tracker != null:
		_tracker.clear()
	_held = false
	for ship in _battle_ships:
		if is_instance_valid(ship):
			ship.queue_free()
	_battle_ships.clear()
	for formation in _battle_formations:
		if is_instance_valid(formation):
			formation.queue_free()
	_battle_formations.clear()


func get_player_combatant() -> Combatant:
	return _main.get_player_ship().combatant
