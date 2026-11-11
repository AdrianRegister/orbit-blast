class_name JumpFlash
extends CanvasLayer
## A full-screen white flash that tells the player a jump has happened. It
## rises almost instantly, which is when the game changes star systems behind
## it (`peak_reached`), then fades away to reveal the new system.

## The screen is fully white: the moment to swap systems.
signal peak_reached
## The flash has faded and the layer is hidden again.
signal finished

const RISE_TIME := 0.12
const FADE_TIME := 0.6

@onready var _rect: ColorRect = $Flash


func _ready() -> void:
	visible = false


func flash() -> void:
	visible = true
	_rect.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_rect, "modulate:a", 1.0, RISE_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_callback(peak_reached.emit)
	tween.tween_property(_rect, "modulate:a", 0.0, FADE_TIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(_done)


## Hides the flash immediately (used when a game is loaded mid-jump).
func cancel() -> void:
	visible = false


func _done() -> void:
	visible = false
	finished.emit()
