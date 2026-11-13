class_name WeaponSystem
extends Node
## The weapons of one ship: its mounts, what is fitted, and the firing rules
## (cooldown, energy, aim). It does not decide WHEN to fire: the player's input
## or, later, an AI calls Combatant.fire(), and fixed mounts shoot along the
## heading while turrets aim at the Combatant's current target.

enum Status { NONE, READY, COOLDOWN, NO_ENERGY }

var slots: Array[WeaponSlot] = []


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


func has_weapons() -> bool:
	for slot in slots:
		if slot.is_armed():
			return true
	return false


## How far the longest-reaching weapon shoots, in pixels (0 = unarmed).
func get_longest_range() -> float:
	var best := 0.0
	for slot in slots:
		if slot.is_armed():
			best = maxf(best, slot.weapon.range)
	return best


## Damage per second of every armed weapon, ignoring energy limits. With
## `light_only`, only the light weapons count: the ones that can hurt a nimble ship
## (see Combatant.lets_shot_pass).
func get_dps(light_only: bool = false) -> float:
	var total := 0.0
	for slot in slots:
		if not slot.is_armed() or slot.weapon.fire_interval <= 0.0:
			continue
		if light_only and slot.weapon.mount_size >= WeaponMount.Size.MEDIUM:
			continue
		total += slot.weapon.damage / slot.weapon.fire_interval
	return total


## What the HUD shows: ready when something can fire now, no energy when
## something is ready but the ship cannot pay for it, otherwise cooling down.
func get_status(available_energy: float) -> Status:
	if not has_weapons():
		return Status.NONE
	var waiting_for_energy := false
	for slot in slots:
		if slot.is_ready():
			if available_energy >= slot.weapon.energy_per_shot:
				return Status.READY
			waiting_for_energy = true
	return Status.NO_ENERGY if waiting_for_energy else Status.COOLDOWN


## 0 (just fired) to 1 (all armed weapons ready): the average over the weapons.
func get_ready_fraction() -> float:
	var total := 0.0
	var count := 0
	for slot in slots:
		if slot.is_armed():
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
		if not slot.is_ready():
			continue
		if not shooter.health.spend_energy(slot.weapon.energy_per_shot):
			continue
		slot.cooldown_left = slot.weapon.fire_interval
		var muzzle := shooter.get_muzzle_position(slot.mount)
		var direction := _aim_direction(shooter, slot, muzzle)
		if slot.weapon.spread_degrees > 0.0:
			direction = direction.rotated(deg_to_rad(randf_range(-slot.weapon.spread_degrees, slot.weapon.spread_degrees)))
		shooter.spawn_projectile(slot.weapon, muzzle, direction)
		fired += 1
	return fired


## Fixed mounts fire along the heading. Turrets aim ahead of the target (or at it
## when it cannot be caught), swinging no further than their arc.
func _aim_direction(shooter: Combatant, slot: WeaponSlot, muzzle: Vector2) -> Vector2:
	var heading := shooter.get_heading()
	if slot.mount.type != WeaponMount.Type.TURRET:
		return Vector2.from_angle(heading)
	var target := shooter.get_target()
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
