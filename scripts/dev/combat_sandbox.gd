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
## This node is a child of that Main. It keeps one target ship in the system: a
## freighter that drifts around the centre, never fires back, and is replaced a
## few seconds after it is destroyed. Nothing is saved and no reputation is ever
## charged.
##
## To change what the sandbox contains, edit the constants below (the player's
## ship, money, the target ship) or the scene `scenes/dev/combat_sandbox_system.tscn`.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const SYSTEM_SCENE := preload("res://scenes/dev/combat_sandbox_system.tscn")
const PLANET_DATA := preload("res://resources/dev/sandbox_planet.tres")
const NPC_SCENE := preload("res://scenes/ships/npc_ship.tscn")
const TRAFFIC_CONFIG := preload("res://resources/traffic/default_traffic.tres")

## What the player starts with.
const PLAYER_SHIP := preload("res://resources/ships/light_frigate_stats.tres")
const PLAYER_CREDITS := 500_000_000
## Where the player starts (the planet is at (1500, 0), the target near the centre).
const PLAYER_START := Vector2(900.0, 500.0)

## The target ship: which kind, how far from the centre it drifts, and how long
## until a destroyed one is replaced.
const TARGET_SHIP := preload("res://resources/ship_types/freighter.tres")
const TARGET_WANDER_RADIUS := 700.0
const TARGET_RESPAWN_DELAY := 3.0

const TARGET_ID_PREFIX := "sandbox_target_"

var _main: Main
var _system: StarSystem
var _targets_spawned: int = 0


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
	(_main.get_node("Combat") as CombatManager).ship_destroyed.connect(_on_ship_destroyed)
	spawn_target()


## Puts a new target ship in the system (the old one, if still alive, stays).
func spawn_target() -> NpcShip:
	var ship: NpcShip = NPC_SCENE.instantiate()
	var no_places: Array[InhabitedNode] = []
	ship.setup(TARGET_SHIP, TRAFFIC_CONFIG, no_places, "", null, _main.get_player_ship())
	_targets_spawned += 1
	ship.combat_id = StringName("%s%d" % [TARGET_ID_PREFIX, _targets_spawned])
	ship.faction_id = &""  # belongs to nobody
	ship.configure_jumping(_system.global_position, _system.jump_radius, [])
	ship.begin_wandering(_system.global_position, TARGET_WANDER_RADIUS)
	_system.get_ships_root().add_child(ship)
	ship.global_position = _system.global_position \
			+ Vector2.from_angle(randf() * TAU) * TARGET_WANDER_RADIUS * sqrt(randf())
	return ship


func _on_ship_destroyed(report: DestructionReport) -> void:
	if not str(report.victim_id).begins_with(TARGET_ID_PREFIX):
		return
	await get_tree().create_timer(TARGET_RESPAWN_DELAY).timeout
	if is_inside_tree() and _system != null and is_instance_valid(_system):
		spawn_target()
