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
	if not open:
		_release_focus()
	_update_visibility()
	toggled.emit(open)


func toggle() -> void:
	set_open(not open)


## Whether the panel can be seen right now.
func is_shown() -> bool:
	return visible


func _update_visibility() -> void:
	visible = open and _sandbox != null and _sandbox.is_flying() and not get_tree().paused


## Lets go of keyboard focus, so Space and Enter (which fire weapons and so on) cannot
## press a button in a panel that has been closed.
func _release_focus() -> void:
	if is_inside_tree():
		get_viewport().gui_release_focus()


## Makes the buttons and drop-downs under `node` unfocusable: a click does not leave
## them holding the keyboard, so Space cannot press them again. (Number boxes keep
## their focus, so they can be typed in.)
static func disable_focus(node: Node) -> void:
	if node is BaseButton:
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		disable_focus(child)
