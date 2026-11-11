class_name GalaxyMapView
extends Control
## The drawn galaxy map: a flat, dark chart with a faint grid, jump links, and a
## marker and label for every system, in the manner of Escape Velocity Nova's
## map. It only draws what the Galaxy and TravelManager say and reports clicks;
## it owns nothing but the view (pan, zoom) and which system is selected.
##
## Look: discovered systems are filled, unexplored ones hollow and dim (their
## names stay visible). The current system has double rings and "YOU ARE HERE".
## Systems linked to the current one are outlined brightly and so are their
## links. The selected system wears corner brackets. Labels keep one on-screen
## size at every zoom level.

## The player clicked a system marker.
signal system_selected(system_id: StringName)

const MIN_ZOOM := 0.4
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.15
const MARKER_RADIUS := 7.0
const PICK_RADIUS := 18.0
const DRAG_THRESHOLD := 6.0
const GRID_SPACING := 100.0
## How far past the outermost system the view may be panned, in map units.
const PAN_MARGIN := 150.0
## Names of systems the player knows nothing about are only drawn at least this
## zoomed in (or when selected), so a big galaxy does not drown in labels.
const UNEXPLORED_LABEL_ZOOM := 1.0

const BACKGROUND := Color(0.02, 0.03, 0.06)
const GRID := Color(0.1, 0.16, 0.24, 0.5)
const LINK_DIM := Color(0.2, 0.3, 0.42)
const LINK_REACHABLE := Color(0.35, 0.8, 1.0)
## Discovered systems are blue; a system that is uninhabited and has been
## scouted shows white instead. Until it is scouted an uninhabited system looks
## like any other discovered one, so scouting is a reveal.
const DISCOVERED := Color(0.35, 0.6, 1.0)
const SCOUTED_EMPTY := Color(1.0, 1.0, 1.0)
const OBJECTIVE := Color(1.0, 0.8, 0.2)
const UNEXPLORED := Color(0.4, 0.46, 0.55)
const CURRENT := Color(1.0, 0.85, 0.3)
const SELECTED := Color(0.45, 1.0, 0.6)

var zoom: float = 1.0
## The map position shown in the middle of the view.
var center: Vector2 = Vector2.ZERO
var selected_id: StringName = &""

var _galaxy: Galaxy
var _travel: TravelManager
## Callable() -> Dictionary: system id -> Array of the accepted contracts that
## point there. Marked on the map.
var _objectives: Callable
var _press_position: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragging: bool = false
## The system the view is still "fitted" around: until the player pans or zooms,
## a change of size (the first layout after opening) re-fits the view.
var _auto_focus: StringName = &""


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)


func setup(galaxy: Galaxy, travel: TravelManager, objectives: Callable = Callable()) -> void:
	_galaxy = galaxy
	_travel = travel
	_objectives = objectives
	_travel.discovery_changed.connect(queue_redraw)
	_travel.scouting_changed.connect(queue_redraw)
	_travel.destination_changed.connect(queue_redraw)


## Shows the map centred on `system_id`, at normal zoom, or zoomed out just
## enough that every system is in view when the galaxy would not otherwise fit.
func focus_on(system_id: StringName) -> void:
	_auto_focus = system_id
	center = _galaxy.get_map_position(system_id)
	zoom = 1.0
	if size.x > 0.0 and size.y > 0.0:
		var reach := Vector2.ONE
		for id in _galaxy.get_system_ids():
			var offset := (_galaxy.get_map_position(id) - center).abs()
			reach = reach.max(offset)
		var margin := Vector2(180.0, 60.0)  # room for labels
		var fit := minf((size.x * 0.5 - margin.x) / reach.x, (size.y * 0.5 - margin.y) / reach.y)
		zoom = clampf(fit, MIN_ZOOM, 1.0)
	_clamp_center()
	queue_redraw()


func _on_resized() -> void:
	if _auto_focus != &"" and _galaxy != null:
		focus_on(_auto_focus)
	queue_redraw()


## The colour a system's marker is drawn in (the current system is drawn gold on
## top of this).
func get_system_colour(system_id: StringName) -> Color:
	if not _travel.is_discovered(system_id):
		return UNEXPLORED
	if not _galaxy.is_inhabited(system_id) and _travel.is_scouted(system_id):
		return SCOUTED_EMPTY
	return DISCOVERED


## The accepted contracts that point at a system (see setup()).
func get_objectives(system_id: StringName) -> Array:
	if not _objectives.is_valid():
		return []
	return _objectives.call().get(system_id, [])


func select(system_id: StringName) -> void:
	selected_id = system_id
	queue_redraw()


# --------------------------------------------------------------- coordinates

## Where a map position is drawn, in this control's own coordinates.
func map_to_view(map_position: Vector2) -> Vector2:
	return size * 0.5 + (map_position - center) * zoom


func view_to_map(view_position: Vector2) -> Vector2:
	return center + (view_position - size * 0.5) / zoom


## Where a system's marker is drawn.
func get_marker_position(system_id: StringName) -> Vector2:
	return map_to_view(_galaxy.get_map_position(system_id))


## The system whose marker is within the pick radius of `view_position`, nearest
## first, or &"" if none.
func pick(view_position: Vector2) -> StringName:
	var best: StringName = &""
	var best_distance := PICK_RADIUS
	for id in _galaxy.get_system_ids():
		var distance := get_marker_position(id).distance_to(view_position)
		if distance <= best_distance:
			best = id
			best_distance = distance
	return best


## Zooms by `factor` keeping the map point under `anchor` (view coordinates) still.
func zoom_by(factor: float, anchor: Vector2) -> void:
	_auto_focus = &""
	var before := view_to_map(anchor)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	center += before - view_to_map(anchor)
	_clamp_center()
	queue_redraw()


func pan_by(view_delta: Vector2) -> void:
	_auto_focus = &""
	center -= view_delta / zoom
	_clamp_center()
	queue_redraw()


func _clamp_center() -> void:
	var bounds := Rect2()
	var first := true
	for id in _galaxy.get_system_ids():
		var p := _galaxy.get_map_position(id)
		bounds = Rect2(p, Vector2.ZERO) if first else bounds.expand(p)
		first = false
	bounds = bounds.grow(PAN_MARGIN)
	center = center.clamp(bounds.position, bounds.end)


# --------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			zoom_by(ZOOM_STEP, button.position)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			zoom_by(1.0 / ZOOM_STEP, button.position)
		elif button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if button.pressed:
				_pressing = true
				_dragging = false
				_press_position = button.position
			else:
				if _pressing and not _dragging and button.button_index == MOUSE_BUTTON_LEFT:
					var id := pick(button.position)
					if id != &"":
						select(id)
						system_selected.emit(id)
				_pressing = false
				_dragging = false
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _pressing:
		if not _dragging and motion.position.distance_to(_press_position) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			pan_by(motion.relative)
		accept_event()


# ------------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if _galaxy == null:
		return
	_draw_grid()
	var current := _travel.get_current_id()
	for link in _galaxy.links:
		var touches_current: bool = link.a == current or link.b == current
		draw_line(get_marker_position(link.a), get_marker_position(link.b),
				LINK_REACHABLE if touches_current else LINK_DIM, 2.0 if touches_current else 1.0, true)
	var neighbours := _galaxy.get_neighbours(current)
	for id in _galaxy.get_system_ids():
		_draw_system(id, current, neighbours.has(id))


func _draw_grid() -> void:
	var top_left := view_to_map(Vector2.ZERO)
	var bottom_right := view_to_map(size)
	var x := floorf(top_left.x / GRID_SPACING) * GRID_SPACING
	while x <= bottom_right.x:
		var view_x := map_to_view(Vector2(x, 0)).x
		draw_line(Vector2(view_x, 0), Vector2(view_x, size.y), GRID, 1.0)
		x += GRID_SPACING
	var y := floorf(top_left.y / GRID_SPACING) * GRID_SPACING
	while y <= bottom_right.y:
		var view_y := map_to_view(Vector2(0, y)).y
		draw_line(Vector2(0, view_y), Vector2(size.x, view_y), GRID, 1.0)
		y += GRID_SPACING


func _draw_system(id: StringName, current: StringName, reachable: bool) -> void:
	var at := get_marker_position(id)
	if not Rect2(Vector2(-80, -40), size + Vector2(160, 80)).has_point(at):
		return  # off screen
	var discovered := _travel.is_discovered(id)
	var colour := get_system_colour(id)
	if id == current:
		colour = CURRENT
		draw_circle(at, MARKER_RADIUS, colour)
		draw_arc(at, MARKER_RADIUS + 5.0, 0.0, TAU, 32, colour, 2.0, true)
		draw_arc(at, MARKER_RADIUS + 10.0, 0.0, TAU, 32, colour, 1.0, true)
	elif discovered:
		draw_circle(at, MARKER_RADIUS, colour)
	else:
		draw_arc(at, MARKER_RADIUS, 0.0, TAU, 24, colour, 2.0, true)
	if reachable:
		draw_arc(at, MARKER_RADIUS + 5.0, 0.0, TAU, 32, LINK_REACHABLE, 2.0, true)
	var objectives := get_objectives(id)
	if not objectives.is_empty():
		draw_arc(at, MARKER_RADIUS + 9.0, 0.0, TAU, 32, OBJECTIVE, 2.0, true)
	if id == selected_id:
		_draw_brackets(at, MARKER_RADIUS + 14.0)
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size + 2
	var label_colour := colour if (discovered or reachable or id == current) else colour.darkened(0.2)
	var known := discovered or reachable or id == current or id == selected_id or id == _travel.get_destination() or not objectives.is_empty()
	if known or zoom >= UNEXPLORED_LABEL_ZOOM:
		draw_string(font, at + Vector2(MARKER_RADIUS + 12.0, 5.0), _galaxy.get_summary(id).system_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_colour)
	if id == current:
		draw_string(font, at + Vector2(MARKER_RADIUS + 12.0, 24.0), "YOU ARE HERE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 4, CURRENT)
	elif id == _travel.get_destination():
		draw_string(font, at + Vector2(MARKER_RADIUS + 12.0, 24.0), "DESTINATION",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 4, SELECTED)
	if not objectives.is_empty():
		var exploring := false
		for contract in objectives:
			exploring = exploring or contract is ExplorationContract
		draw_string(font, at + Vector2(MARKER_RADIUS + 12.0, 24.0 if id != current and id != _travel.get_destination() else 42.0),
				"EXPLORE" if exploring else "DELIVERY", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 4, OBJECTIVE)


func _draw_brackets(at: Vector2, half: float) -> void:
	var arm := half * 0.45
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var origin: Vector2 = at + corner * half
		draw_line(origin, origin - Vector2(corner.x * arm, 0), SELECTED, 2.0)
		draw_line(origin, origin - Vector2(0, corner.y * arm), SELECTED, 2.0)
