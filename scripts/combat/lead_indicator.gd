class_name LeadIndicator
extends Node2D
## A small reticle in the world at the point where a shot fired now would meet
## the selected ship: aim the nose there. It follows the player's Combatant, uses
## the first armed weapon's shot speed, and hides when there is no target, no
## weapon, or the target cannot be caught. Green means the point is within the
## weapon's range, grey that it is not.

const COLOUR_IN_RANGE := Color(0.4, 0.9, 0.5, 0.9)
const COLOUR_OUT_OF_RANGE := Color(0.6, 0.66, 0.74, 0.6)
const RADIUS := 10.0

var combatant: Combatant

var _in_range: bool = false


func _ready() -> void:
	top_level = true  # positioned in world space, whatever the ship does
	z_index = 3
	visible = false


func _process(_delta: float) -> void:
	var target := combatant.get_target() if combatant != null else null
	var weapon := _first_weapon()
	if target == null or weapon == null:
		visible = false
		return
	var shooter := combatant.global_position
	var aim: Variant = Intercept.solve(shooter, combatant.get_velocity() * weapon.inherit_velocity,
			target.global_position, target.get_velocity(), weapon.projectile_speed)
	if aim == null:
		visible = false
		return
	visible = true
	global_position = aim
	var in_range := shooter.distance_to(aim) <= weapon.range
	if in_range != _in_range:
		_in_range = in_range
		queue_redraw()


func _first_weapon() -> WeaponDefinition:
	if combatant == null or combatant.weapons == null:
		return null
	for slot in combatant.weapons.slots:
		if slot.is_armed():
			return slot.weapon
	return null


func _draw() -> void:
	var colour := COLOUR_IN_RANGE if _in_range else COLOUR_OUT_OF_RANGE
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, colour, 1.5)
	draw_line(Vector2(-RADIUS - 4.0, 0.0), Vector2(-RADIUS + 3.0, 0.0), colour, 1.5)
	draw_line(Vector2(RADIUS - 3.0, 0.0), Vector2(RADIUS + 4.0, 0.0), colour, 1.5)
	draw_line(Vector2(0.0, -RADIUS - 4.0), Vector2(0.0, -RADIUS + 3.0), colour, 1.5)
	draw_line(Vector2(0.0, RADIUS - 3.0), Vector2(0.0, RADIUS + 4.0), colour, 1.5)
