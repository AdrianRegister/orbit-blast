extends SceneTree
## Tests the view zoom (mouse wheel: three levels, normal, 25% and 50% zoomed out) in the real
## game scene (the combat sandbox). Run with:
##   Godot --headless --path . --script res://scripts/tests/camera_zoom_test.gd </dev/null

var _failures: int = 0
var _main: Main
var _camera: Camera2D


func _init() -> void:
	_main = CombatSandbox.build_main()
	root.add_child(_main)
	for i in 5:
		await process_frame
	_camera = _main.get_node("Camera2D")

	_check(_main.get_zoom_level() == 0 and is_equal_approx(_camera.zoom.x, 1.0), "the view starts at normal zoom")
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(_main.get_zoom_level() == 0, "scrolling up at normal zoom does nothing")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check(_main.get_zoom_level() == 1 and is_equal_approx(_camera.zoom.x, 0.75), "scrolling down once zooms out 25%% (zoom %.3f)" % _camera.zoom.x)
	var offset_medium := _camera.offset.x
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check(_main.get_zoom_level() == 2 and is_equal_approx(_camera.zoom.x, 0.5), "scrolling down again zooms out to 50%% (zoom %.3f)" % _camera.zoom.x)
	_check(_camera.offset.x > offset_medium, "the HUD shift grows in world units as the view zooms out, so the ship stays centred in the play area")
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check(_main.get_zoom_level() == 2, "scrolling down at the furthest level does nothing")
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(_main.get_zoom_level() == 1 and is_equal_approx(_camera.zoom.x, 0.75), "scrolling up zooms in one level")
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(_main.get_zoom_level() == 0 and is_equal_approx(_camera.zoom.x, 1.0), "...and back to normal")

	# A click on a ship still finds it when zoomed out (targeting uses the canvas transform).
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	var point: Vector2 = root.get_viewport().get_canvas_transform().affine_inverse() * Vector2(100.0, 100.0)
	_check(point.distance_to(_camera.get_screen_center_position()) > 0.0, "(screen to world still goes through the zoomed view)")

	# Other buttons are left alone, and nothing zooms while a menu is open.
	var before := _main.get_zoom_level()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_main._unhandled_input(click)
	_check(_main.get_zoom_level() == before, "other mouse buttons do not zoom")
	var pause: CanvasLayer = _main.get_node("PauseMenu")
	pause.visible = true
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check(_main.get_zoom_level() == before, "the wheel does not zoom while a menu is open")
	pause.visible = false

	print("CAMERA ZOOM TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## Scrolls the wheel one notch and lets the camera settle.
func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	_main._unhandled_input(event)
	for i in 90:
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
