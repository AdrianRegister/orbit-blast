class_name ReputationBar
extends Control
## A horizontal bar for a reputation from -100 to +100: a track, a mark at the
## middle (neutral) and a fill from the middle towards the value, in the
## faction colour. Purely presentational.

const TRACK := Color(0.067, 0.09, 0.125)
const BORDER := Color(0.23, 0.29, 0.37)
const MIDDLE := Color(0.44, 0.54, 0.66)

var value: int = 0
var minimum: int = -100
var maximum: int = 100
var fill_colour: Color = Color(0.75, 0.56, 0.22)


func _init() -> void:
	custom_minimum_size = Vector2(0, 18)


func set_reputation(new_value: int, new_minimum: int, new_maximum: int, colour: Color) -> void:
	value = new_value
	minimum = new_minimum
	maximum = new_maximum
	fill_colour = colour
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TRACK)
	var span := float(maximum - minimum)
	var middle_x := size.x * (0.0 - minimum) / span
	var value_x := size.x * (value - minimum) / span
	draw_rect(Rect2(minf(middle_x, value_x), 2.0, absf(value_x - middle_x), size.y - 4.0), fill_colour)
	draw_line(Vector2(middle_x, 0.0), Vector2(middle_x, size.y), MIDDLE, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 1.0)
