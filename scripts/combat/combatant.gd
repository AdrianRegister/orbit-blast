class_name Combatant
extends Node2D
## The combat side of one ship, player or NPC: its defences, its weapons and its
## hit area. It is a child of the ship and the only thing other systems (the
## HUD, the CombatManager, later AI and formations) talk to. It holds no input or
## decision logic: whoever controls the ship calls set_target() and fire().
##
## The ship tells it how to read the ship's heading and velocity, because
## players and NPCs move differently (see setup()).

## The ship was hit. `hit.attacker` is the attacking Combatant, if any.
signal damaged(result: DamageResult, hit: Hit)
## Hull reached zero. Emitted once. `attacker` may be null.
signal destroyed(victim: Combatant, attacker: Combatant)
signal target_changed(new_target: Combatant)

const GROUP := &"combatant"
const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

## Unique per ship in play (used to count each hostile act once).
var combat_id: StringName = &""
## The faction the ship belongs to ("" = none).
var faction_id: StringName = &""
var is_player: bool = false
var model_id: StringName = &""
var display_name: String = ""
var specs: ShipSpecs
var rules: DamageRules
## Callable() -> Node: the node new shots are added to (the system's Projectiles).
var projectile_root_provider: Callable
## Who counts as an ally (set by the CombatManager when it registers the ship).
## Null: nobody is, so every shot hits.
var allegiance: Allegiance
## Whether the ship slips past medium and heavy weapons (its class says so).
var evasive: bool = false

var _target: Combatant
var _heading_provider: Callable
var _velocity_provider: Callable
var _dead: bool = false

@onready var health: ShipHealth = $Health
@onready var weapons: WeaponSystem = $Weapons
@onready var hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	add_to_group(GROUP)
	hurtbox.combatant = self


## Configures the combatant for a ship. `loadout` is parallel to the model's
## mounts (null = empty). `condition` is the ship's lasting damage (null for ships
## that do not keep any). The two callables read the ship: heading() -> float
## (radians, 0 = facing right) and velocity() -> Vector2.
func setup(model: ShipStats, ship_specs: ShipSpecs, loadout: Array, condition: ShipCondition,
		heading: Callable, velocity: Callable) -> void:
	rules = DamageRules.shared()
	specs = ship_specs
	model_id = model.id
	display_name = model.display_name
	evasive = model.ship_class != null and model.ship_class.is_evasive()
	_heading_provider = heading
	_velocity_provider = velocity
	_dead = false
	_target = null
	health.setup(ship_specs, condition)
	weapons.setup(model.weapon_mounts, loadout)
	hurtbox.set_radius(ship_specs.hit_radius)
	hurtbox.set_active(true)


func is_alive() -> bool:
	return not _dead


func get_heading() -> float:
	return _heading_provider.call() if _heading_provider.is_valid() else 0.0


func get_velocity() -> Vector2:
	return _velocity_provider.call() if _velocity_provider.is_valid() else Vector2.ZERO


## Where a shot from `mount` leaves the ship, in world space.
func get_muzzle_position(mount: WeaponMount) -> Vector2:
	return global_position + mount.offset.rotated(get_heading())


# ----------------------------------------------------------------- targeting

## The target turrets aim at (and the HUD shows). Null clears it.
func set_target(new_target: Combatant) -> void:
	if new_target == _target:
		return
	_target = new_target
	target_changed.emit(_target)


## The current target, or null when there is none or it is gone.
func get_target() -> Combatant:
	if _target != null and (not is_instance_valid(_target) or not _target.is_alive()):
		_target = null
	return _target


# ------------------------------------------------------------------- firing

## Fires every ready weapon. Returns how many fired.
func fire() -> int:
	if _dead or weapons == null:
		return 0
	return weapons.fire(self)


## Adds a shot to the world. Called by the WeaponSystem.
func spawn_projectile(weapon: WeaponDefinition, muzzle: Vector2, direction: Vector2) -> void:
	var scene: PackedScene = weapon.projectile_scene if weapon.projectile_scene != null else PROJECTILE_SCENE
	var projectile: Projectile = scene.instantiate()
	var root: Node = projectile_root_provider.call() if projectile_root_provider.is_valid() else null
	if root == null:
		root = get_tree().current_scene
	root.add_child(projectile)
	projectile.launch(weapon, self, muzzle,
			direction * weapon.projectile_speed + get_velocity() * weapon.inherit_velocity)


# ------------------------------------------------------------------- damage

## Whether a shot from `weapon` fired by `shooter` goes straight through this ship
## instead of hitting it: the shooter is an ally (no friendly fire), or this ship is
## nimble (see ShipClass.evades_heavy_fire) and the weapon is medium or large.
## Nothing happens to the shot and nothing is shown: as far as combat goes it missed.
func lets_shot_pass(weapon: WeaponDefinition, shooter: Combatant) -> bool:
	if shooter != null and allegiance != null and allegiance.are_allies(shooter, self):
		return true
	return evasive and weapon != null and weapon.mount_size >= WeaponMount.Size.MEDIUM


## Takes a hit through the layered damage rules. Destroys the ship at hull zero.
func take_hit(hit: Hit) -> DamageResult:
	if _dead:
		return DamageResult.new()
	var result := health.apply(hit, rules)
	damaged.emit(result, hit)
	if result.destroyed:
		_dead = true
		hurtbox.set_active(false)
		var attacker := hit.attacker as Combatant
		destroyed.emit(self, attacker if is_instance_valid(attacker) else null)
	return result
