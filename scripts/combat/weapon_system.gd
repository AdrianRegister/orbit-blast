class_name WeaponSystem
extends Node
## The weapons of one ship: its mounts, what is fitted, and the firing rules
## (cooldown, energy, aim). It does not decide WHEN to fire: the player's input
## or, later, an AI calls Combatant.fire(), and fixed mounts shoot along the
## heading while turrets aim at the Combatant's current target.
##
## Point-defence weapons (WeaponDefinition.point_defence) are the exception: they are
## left out of every number here that describes the ship's guns (reach, damage per
## second, fire(), fire_at_will()) and fire by themselves at nimble hostile ships,
## each choosing its own target (fire_point_defence).

enum Status { NONE, READY, COOLDOWN, NO_ENERGY }

var slots: Array[WeaponSlot] = []
## How many shots this ship's main weapons have fired (a count for tests and for balancing).
var shots_fired: int = 0
## How many point-defence shots (counted apart, so shots_fired stays the guns' shots).
var point_defence_shots: int = 0


func _process(delta: float) -> void:
	tick(delta)


## One slot per mount of the model; `loadout` is parallel to `mounts` (null = empty).
func setup(mounts: Array[WeaponMount], loadout: Array) -> void:
	slots.clear()
	for index in mounts.size():
		var slot := WeaponSlot.new()
		slot.mount = mounts[index]
		slot.weapon = loadout[index] if index < loadout.size() else null
		slots.append(slot)


## Counts the cooldowns down. Public so tests can step time.
func tick(delta: float) -> void:
	for slot in slots:
		if slot.cooldown_left > 0.0:
			slot.cooldown_left = maxf(slot.cooldown_left - delta, 0.0)


## Whether a main weapon is fitted (point defence alone does not make a ship armed).
func has_weapons() -> bool:
	for slot in slots:
		if slot.is_main():
			return true
	return false


## How far the longest-reaching main weapon shoots, in pixels (0 = unarmed).
func get_longest_range() -> float:
	var best := 0.0
	for slot in slots:
		if slot.is_main():
			best = maxf(best, slot.weapon.range)
	return best


## Damage per second of every armed weapon, ignoring energy limits. With
## `light_only`, only the light weapons count: the ones that can hurt a nimble ship
## (see Combatant.lets_shot_pass). Point defence counts only with `with_point_defence`
## (what the ship can do to others, not what it chooses to aim).
func get_dps(light_only: bool = false, with_point_defence: bool = false) -> float:
	var total := 0.0
	for slot in slots:
		if not slot.is_armed() or slot.weapon.fire_interval <= 0.0:
			continue
		if slot.is_point_defence() and not with_point_defence:
			continue
		if light_only and slot.weapon.mount_size >= WeaponMount.Size.MEDIUM:
			continue
		total += slot.weapon.damage / slot.weapon.fire_interval
	return total


## How far the ship fights from: the reach of its weapons averaged by their damage
## (a ship that does most of its damage with long guns fights from further out).
## 0 when unarmed.
func get_effective_range() -> float:
	var weighted := 0.0
	var total := 0.0
	for slot in slots:
		if slot.is_main() and slot.weapon.fire_interval > 0.0:
			var dps := slot.weapon.damage / slot.weapon.fire_interval
			weighted += dps * slot.weapon.range
			total += dps
	return weighted / total if total > 0.0 else 0.0


## The speed of the ship's shots, averaged by damage like get_effective_range
## (what a pilot leads its aim by).
func get_effective_projectile_speed() -> float:
	var weighted := 0.0
	var total := 0.0
	for slot in slots:
		if slot.is_main() and slot.weapon.fire_interval > 0.0:
			var dps := slot.weapon.damage / slot.weapon.fire_interval
			weighted += dps * slot.weapon.projectile_speed
			total += dps
	return weighted / total if total > 0.0 else 0.0


## What the HUD shows: ready when something can fire now, no energy when
## something is ready but the ship cannot pay for it, otherwise cooling down.
func get_status(available_energy: float) -> Status:
	if not has_weapons():
		return Status.NONE
	var waiting_for_energy := false
	for slot in slots:
		if slot.is_ready() and not slot.is_point_defence():
			if available_energy >= slot.weapon.energy_per_shot:
				return Status.READY
			waiting_for_energy = true
	return Status.NO_ENERGY if waiting_for_energy else Status.COOLDOWN


## 0 (just fired) to 1 (all armed weapons ready): the average over the weapons.
func get_ready_fraction() -> float:
	var total := 0.0
	var count := 0
	for slot in slots:
		if slot.is_main():
			count += 1
			total += 1.0 - clampf(slot.cooldown_left / slot.weapon.fire_interval, 0.0, 1.0)
	return total / count if count > 0 else 1.0


## "Light Blaster x2, Pulse Cannon", or "NONE" when unarmed.
func get_summary() -> String:
	var counts := {}
	var order: Array[String] = []
	for slot in slots:
		if slot.is_armed():
			var weapon_name := slot.weapon.display_name
			if not counts.has(weapon_name):
				order.append(weapon_name)
			counts[weapon_name] = counts.get(weapon_name, 0) + 1
	if order.is_empty():
		return "NONE"
	var parts: Array[String] = []
	for weapon_name in order:
		parts.append(weapon_name if counts[weapon_name] == 1 else "%s x%d" % [weapon_name, counts[weapon_name]])
	return ", ".join(parts)


## Fires every weapon that is ready and that the ship has the energy for.
## Returns how many fired.
func fire(shooter: Combatant) -> int:
	var fired := 0
	for slot in slots:
		if slot.is_ready() and not slot.is_point_defence() and _fire_slot(shooter, slot):
			fired += 1
	return fired


## Fires only the ready weapons that would hit the shooter's target, the way a
## pilot does: a fixed gun when the nose is on the target (within `tolerance_degrees`,
## or the angle the target's size covers), a turret when the target is inside its
## arc, and only a weapon that can hurt the target (a nimble ship is not hurt by
## medium and heavy weapons) and reaches it. The same weapons, cooldowns, energy and
## shots as fire(). Returns how many fired.
func fire_at_will(shooter: Combatant, tolerance_degrees: float = 5.0) -> int:
	var target := shooter.get_target()
	if target == null:
		return 0
	var fired := 0
	for slot in slots:
		if slot.is_ready() and not slot.is_point_defence() and would_hit(shooter, slot, target, tolerance_degrees) and _fire_slot(shooter, slot):
			fired += 1
	return fired


## Whether a shot from `slot` fired now at `target` would be worth firing: see
## fire_at_will.
func would_hit(shooter: Combatant, slot: WeaponSlot, target: Combatant, tolerance_degrees: float) -> bool:
	if target.evasive and slot.weapon.mount_size >= WeaponMount.Size.MEDIUM:
		return false  # it would pass straight through
	var muzzle := shooter.get_muzzle_position(slot.mount)
	var shooter_velocity := shooter.get_velocity() * slot.weapon.inherit_velocity
	var point := CombatSteering.lead_point(muzzle, shooter_velocity, target.global_position, target.get_velocity(), slot.weapon.projectile_speed)
	if muzzle.distance_to(point) > slot.weapon.range:
		return false
	var heading := shooter.get_heading()
	if slot.mount.type == WeaponMount.Type.TURRET:
		return absf(angle_difference(heading, (point - muzzle).angle())) <= deg_to_rad(slot.mount.arc_degrees)
	return CombatSteering.is_aimed(heading, muzzle, point, target.specs.hit_radius, tolerance_degrees)


# ------------------------------------------------------------- point defence

func has_point_defence() -> bool:
	for slot in slots:
		if slot.is_point_defence():
			return true
	return false


## Whether a point-defence weapon is ready to fire now.
func has_ready_point_defence() -> bool:
	for slot in slots:
		if slot.is_point_defence() and slot.is_ready():
			return true
	return false


## The reach of the longest point-defence weapon (0 = none fitted).
func get_point_defence_range() -> float:
	var best := 0.0
	for slot in slots:
		if slot.is_point_defence():
			best = maxf(best, slot.weapon.range)
	return best


## Fires each ready point-defence weapon at the nearest of `hostiles` that is nimble
## (a fighter: the ships the main guns cannot hurt), alive, within its reach and inside
## the mount's arc, aiming ahead of it. Each weapon picks its own target, whatever the
## ship is aiming at. Returns how many fired.
func fire_point_defence(shooter: Combatant, hostiles: Array[Combatant]) -> int:
	var fired := 0
	for slot in slots:
		if not slot.is_point_defence() or not slot.is_ready():
			continue
		var target := _point_defence_target(shooter, slot, hostiles)
		if target != null and _fire_slot(shooter, slot, target):
			fired += 1
	return fired


func _point_defence_target(shooter: Combatant, slot: WeaponSlot, hostiles: Array[Combatant]) -> Combatant:
	var muzzle := shooter.get_muzzle_position(slot.mount)
	var shooter_velocity := shooter.get_velocity() * slot.weapon.inherit_velocity
	var heading := shooter.get_heading()
	var arc := deg_to_rad(slot.mount.arc_degrees)
	var best: Combatant = null
	var best_distance := INF
	for other in hostiles:
		if not is_instance_valid(other) or not other.is_alive() or not other.evasive:
			continue
		var distance := muzzle.distance_to(other.global_position)
		if distance >= best_distance:
			continue
		var point := CombatSteering.lead_point(muzzle, shooter_velocity, other.global_position, other.get_velocity(), slot.weapon.projectile_speed)
		if muzzle.distance_to(point) > slot.weapon.range or absf(angle_difference(heading, (point - muzzle).angle())) > arc:
			continue
		best = other
		best_distance = distance
	return best


## Fires one weapon: spends the energy, starts the cooldown and launches the shot.
## False (and nothing happens) when the ship cannot pay for it.
## (`aim_at` is who a turret aims at: the ship's target when null.)
func _fire_slot(shooter: Combatant, slot: WeaponSlot, aim_at: Combatant = null) -> bool:
	if not shooter.health.spend_energy(slot.weapon.energy_per_shot):
		return false
	slot.cooldown_left = slot.weapon.fire_interval
	var muzzle := shooter.get_muzzle_position(slot.mount)
	var direction := _aim_direction(shooter, slot, muzzle, aim_at if aim_at != null else shooter.get_target())
	if slot.weapon.spread_degrees > 0.0:
		direction = direction.rotated(deg_to_rad(randf_range(-slot.weapon.spread_degrees, slot.weapon.spread_degrees)))
	shooter.spawn_projectile(slot.weapon, muzzle, direction)
	if slot.is_point_defence():
		point_defence_shots += 1
	else:
		shots_fired += 1
	return true


## Fixed mounts fire along the heading. Turrets aim ahead of the target (or at it
## when it cannot be caught), swinging no further than their arc.
func _aim_direction(shooter: Combatant, slot: WeaponSlot, muzzle: Vector2, aim_at: Combatant = null) -> Vector2:
	var heading := shooter.get_heading()
	if slot.mount.type != WeaponMount.Type.TURRET:
		return Vector2.from_angle(heading)
	var target := aim_at if aim_at != null else shooter.get_target()
	if target == null:
		return Vector2.from_angle(heading)
	var shooter_velocity := shooter.get_velocity() * slot.weapon.inherit_velocity
	var aim_point: Variant = Intercept.solve(muzzle, shooter_velocity, target.global_position,
			target.get_velocity(), slot.weapon.projectile_speed)
	var point: Vector2 = aim_point if aim_point != null else target.global_position
	var wanted := (point - muzzle).angle()
	var arc := deg_to_rad(slot.mount.arc_degrees)
	var swing := clampf(angle_difference(heading, wanted), -arc, arc)
	return Vector2.from_angle(heading + swing)
