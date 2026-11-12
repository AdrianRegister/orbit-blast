class_name Projectile
extends Node2D
## A shot in flight. Each physics frame it sweeps a ray along the distance it is
## about to travel and hits the first ship hurtbox on the way, so a fast shot can
## never skip over a target. It lives under the star system's Projectiles node,
## so shots disappear when the system is swapped.

var velocity: Vector2 = Vector2.ZERO
var weapon: WeaponDefinition
var shooter: Combatant

var _life_left: float = 0.0
var _color: Color = Color.WHITE


## Starts the shot at `at` with the given velocity.
func launch(definition: WeaponDefinition, from_shooter: Combatant, at: Vector2, shot_velocity: Vector2) -> void:
	weapon = definition
	shooter = from_shooter
	global_position = at
	velocity = shot_velocity
	rotation = shot_velocity.angle()
	_life_left = definition.get_lifetime()
	_color = definition.projectile_color
	queue_redraw()


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters2D.create(from, to, Hurtbox.COLLISION_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.hit_from_inside = true
	var attacker: Combatant = shooter if is_instance_valid(shooter) else null
	if attacker != null:
		query.exclude = [attacker.hurtbox.get_rid()]
	var found := get_world_2d().direct_space_state.intersect_ray(query)
	if not found.is_empty():
		var box := found["collider"] as Hurtbox
		if box != null and box.combatant != null:
			box.combatant.take_hit(Hit.from_weapon(weapon, attacker, found["position"]))
		set_physics_process(false)
		queue_free()
		return
	global_position = to
	_life_left -= delta
	if _life_left <= 0.0:
		set_physics_process(false)
		queue_free()


func _draw() -> void:
	draw_line(Vector2(-12.0, 0.0), Vector2(5.0, 0.0), _color, 3.0)
	draw_line(Vector2(-6.0, 0.0), Vector2(5.0, 0.0), Color(1.0, 1.0, 1.0, 0.9), 1.5)
