class_name DevPanel
extends CanvasLayer
## DEVELOPMENT ONLY. A panel of the combat sandbox that the DevToolbar (or its key)
## can open and close. It shows only while the player is flying with no menu open.

## The panel was opened or closed.
signal toggled(is_open: bool)

var open: bool = true
var _sandbox: CombatSandbox


func _init() -> void:
	# Keeps running while the game is paused, so it can hide itself behind menus.
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_open(value: bool) -> void:
	if value == open:
		return
	open = value
	_update_visibility()
	toggled.emit(open)


func toggle() -> void:
	set_open(not open)


## Whether the panel can be seen right now.
func is_shown() -> bool:
	return visible


func _update_visibility() -> void:
	visible = open and _sandbox != null and _sandbox.is_flying() and not get_tree().paused
