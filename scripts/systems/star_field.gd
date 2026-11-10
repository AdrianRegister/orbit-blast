extends Node2D
## Placeholder starfield: a fixed random scatter of dots so that ship motion
## is visible. Drawn once; Godot caches the result.

@export var star_count: int = 8000
@export var half_extent: float = 8000.0
@export var seed_value: int = 1
## Multiplies star brightness. Below 1.0 makes the layer look more distant.
@export_range(0.0, 1.0) var brightness_scale: float = 1.0
## Multiplies star size. Below 1.0 makes the layer look more distant.
@export_range(0.1, 2.0) var size_scale: float = 1.0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in star_count:
		var pos := Vector2(
			rng.randf_range(-half_extent, half_extent),
			rng.randf_range(-half_extent, half_extent))
		var size: float = rng.randf_range(1.0, 3.0) * size_scale
		var brightness: float = rng.randf_range(0.4, 1.0) * brightness_scale
		draw_rect(Rect2(pos, Vector2(size, size)), Color(brightness, brightness, brightness))
