class_name SpaceStation
extends InhabitedNode
## Placeholder space station drawn entirely in code: a hub inside a ring,
## joined by spokes, with a solar panel on each side. Replace with a sprite
## later by swapping the visual, nothing else depends on how it is drawn.
## The ring's diameter comes from the InhabitedData `size`; total width is
## about 2.2x that.

const HULL_COLOR := Color(0.62, 0.68, 0.75)
const HULL_DARK := Color(0.3, 0.35, 0.42)
const PANEL_COLOR := Color(0.25, 0.4, 0.62)
const PANEL_EDGE := Color(0.55, 0.7, 0.88)
const LIGHT_COLOR := Color(0.85, 0.95, 1.0)


func _ready() -> void:
	super()
	queue_redraw()


## Radius of the station's ring in world pixels.
func _radius() -> float:
	return (data.size if data != null else 80.0) * 0.5


func _get_object_type() -> ObjectType:
	return ObjectType.STATION


func _get_target_bounds() -> Vector2:
	var r: float = _radius()
	return Vector2(r * 4.4, r * 2.2)


func _draw() -> void:
	var r: float = _radius()

	# Solar panels and the strut that carries them.
	draw_line(Vector2(-r * 2.1, 0), Vector2(r * 2.1, 0), HULL_DARK, r * 0.12)
	for side in [-1.0, 1.0]:
		var panel := Rect2(Vector2(r * 1.05 if side > 0 else -r * 2.2, -r * 0.4), Vector2(r * 1.15, r * 0.8))
		draw_rect(panel, PANEL_COLOR)
		draw_rect(panel, PANEL_EDGE, false, 2.0)

	# Spokes from hub to ring.
	for i in 4:
		var dir := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
		draw_line(dir * r * 0.35, dir * r, HULL_DARK, r * 0.1)

	# Ring, hub and a small light in the middle.
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, HULL_COLOR, r * 0.14, true)
	draw_circle(Vector2.ZERO, r * 0.38, HULL_COLOR)
	draw_circle(Vector2.ZERO, r * 0.2, HULL_DARK)
	draw_circle(Vector2.ZERO, r * 0.08, LIGHT_COLOR)
