class_name TargetingManager
extends Node
## Mouse selection of Targetables. Knows nothing about planets, stations or
## ships: it only finds whichever Targetable was clicked and announces it.
## Left-click an object to select it, left-click empty space to clear.

## Emitted whenever the selection changes. `target` is null when cleared.
signal target_changed(target: Targetable)

var current_target: Targetable


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_target"):
		select_next(Targetable.LOCATION_GROUP)
		return
	if event.is_action_pressed("cycle_ship_target"):
		select_next(Targetable.SHIP_GROUP)
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	# Screen position -> world position, correct for camera position, offset and zoom.
	var world_position: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * click.position
	select(_find_targetable_at(world_position))


## Selects `target`, replacing any previous selection. Null clears it.
func select(target: Targetable) -> void:
	if target == current_target:
		return
	if current_target != null:
		current_target.set_selected(false)
		current_target.tree_exiting.disconnect(_on_target_exiting)
		current_target.became_unavailable.disconnect(_on_target_exiting)
	current_target = target
	if current_target != null:
		current_target.set_selected(true)
		current_target.tree_exiting.connect(_on_target_exiting)
		current_target.became_unavailable.connect(_on_target_exiting)
	target_changed.emit(current_target)


## Selects the next enabled Targetable of `group` in scene order, wrapping
## around at the end. With nothing (or something of another group) selected,
## selects the first one.
func select_next(group: StringName = Targetable.LOCATION_GROUP) -> void:
	var all: Array[Node] = get_tree().get_nodes_in_group(group).filter(
			func(node: Node) -> bool: return (node as Targetable).is_enabled())
	if all.is_empty():
		return
	var index: int = all.find(current_target)
	select(all[(index + 1) % all.size()] as Targetable)


func _find_targetable_at(world_position: Vector2) -> Targetable:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collision_mask = Targetable.COLLISION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hits: Array[Dictionary] = get_viewport().world_2d.direct_space_state.intersect_point(query, 8)

	# If several overlap, prefer the one whose centre is closest to the click.
	var best: Targetable = null
	var best_distance: float = INF
	for hit in hits:
		var candidate := hit["collider"] as Targetable
		if candidate == null:
			continue
		var distance: float = candidate.distance_from(world_position)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _on_target_exiting() -> void:
	select(null)
