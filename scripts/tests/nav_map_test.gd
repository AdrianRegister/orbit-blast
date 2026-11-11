extends SceneTree
## Tests the navicomputer's system map through the real game scene: what it
## shows (planets, uninhabited bodies, stations, NPC ships), that it follows the
## ship, and the arrow towards the system centre. Run with:
##   Godot --headless --path . --script res://scripts/tests/nav_map_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var hud: Hud = main.get_node("Hud")
	var map: NavMap = hud.get_nav_map()
	var ship := main.get_player_ship()
	var system := main.get_system()
	_check(map.get_parent().get_parent().name == "NavPanel", "the map is part of the navicomputer panel")
	_check(map.size.x >= 100.0 and map.size.y >= 100.0, "it has a usable size (%s)" % map.size)

	# --- Sol from the middle: Earth, Mars (planets) and Victory I (station) are in range.
	ship.global_position = Vector2.ZERO
	var kinds := _count_kinds(map)
	_check(kinds.get(NavMap.KIND_PLANET, 0) == 2, "two planets are shown (Earth, Mars)")
	_check(kinds.get(NavMap.KIND_STATION, 0) == 1, "one station is shown (Victory I)")
	_check(kinds.get(NavMap.KIND_UNINHABITED, 0) == 0, "no uninhabited bodies in Sol")
	var npc_count := system.get_ships_root().get_child_count()
	_check(kinds.get(NavMap.KIND_SHIP, 0) > 0 and kinds.get(NavMap.KIND_SHIP, 0) <= npc_count, "NPC ships are shown as dots (%d of %d)" % [kinds.get(NavMap.KIND_SHIP, 0), npc_count])
	_check(not map.is_arrow_visible(), "no arrow while planets are in view")

	# --- It follows the ship: blips shift the other way when the ship moves.
	var earth_before := _offset_of(map, Vector2(-700, -250))
	ship.global_position = Vector2(100, 50)
	var earth_after := _offset_of(map, Vector2(-700, -250))
	_check(earth_before == Vector2(-700, -250) and earth_after == Vector2(-800, -300), "the map is centred on the ship and scrolls as it moves")

	# --- Range: objects beyond the edge are not drawn.
	ship.global_position = Vector2(0, 3000)
	_check(map.get_visible_planet_count() == 0, "far from every planet, none is shown")
	_check(map.is_arrow_visible() and map.get_arrow_direction().distance_to(Vector2.UP) < 0.01, "the arrow appears, pointing at the system centre (up)")
	ship.global_position = Vector2(-3500, 0)
	_check(map.is_arrow_visible() and map.get_arrow_direction().distance_to(Vector2.RIGHT) < 0.01, "and follows the ship round (now pointing right)")
	ship.global_position = Vector2(-700, 2000)  # Earth is 2,250 px away: in view
	_check(map.get_visible_planet_count() >= 1 and not map.is_arrow_visible(), "the arrow disappears as soon as a planet comes into view")
	ship.global_position = Vector2(0, 3000)
	_check(map.is_arrow_visible(), "and returns when the planet leaves again")
	ship.global_position = Vector2(2200, -1400)  # on top of Mars
	_check(not map.is_arrow_visible(), "no arrow with a planet in view")

	# --- The arrow blinks (drawing must not fail in any phase).
	ship.global_position = Vector2(0, 3000)
	for i in 4:
		await create_timer(map.blink_period).timeout
	_check(map.is_arrow_visible(), "the arrow stays valid while it blinks")

	# --- Colours: gas giants grey, stations yellow, planets blue (Barnard's Star).
	main._swap_system(main.galaxy.get_scene(&"barnards_star"))
	await process_frame
	ship.global_position = Vector2.ZERO
	kinds = _count_kinds(map)
	_check(kinds.get(NavMap.KIND_UNINHABITED, 0) == 1, "the gas giant is shown as uninhabited (grey)")
	_check(kinds.get(NavMap.KIND_STATION, 0) == 1 and kinds.get(NavMap.KIND_PLANET, 0) == 1, "with its station and planet")
	_check(NavMap.UNINHABITED_COLOUR.r == NavMap.UNINHABITED_COLOUR.g and NavMap.STATION_COLOUR.r > 0.9 and NavMap.STATION_COLOUR.b < 0.5 and NavMap.PLANET_COLOUR.b > 0.9, "grey, yellow and blue outlines")
	_check(NavMap.SHIP_COLOUR.b > NavMap.SHIP_COLOUR.r, "NPC ships are blue")
	_check(map.get_arrow_direction() == Vector2.ZERO or map.get_visible_planet_count() == 0, "(arrow only when no planet)")

	# --- After a jump the new system is shown, from its edge.
	main._swap_system(main.galaxy.get_scene(&"sol"))
	await process_frame
	ship.global_position = Vector2(2000, 2000)
	_check(map.get_visible_planet_count() == 0 and map.is_arrow_visible(), "arriving at the edge of a system, the arrow points back to the middle")
	_check(map.get_arrow_direction().dot((Vector2.ZERO - ship.global_position).normalized()) > 0.999, "...at the centre")
	ship.global_position = Vector2.ZERO
	_check(map.get_visible_planet_count() == 2, "and the map shows the loaded system (Sol)")

	print("")
	print("NAV MAP TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _count_kinds(map: NavMap) -> Dictionary:
	var kinds := {}
	for blip in map.get_blips():
		kinds[blip["kind"]] = kinds.get(blip["kind"], 0) + 1
	return kinds


## The offset (from the ship) of the blip at a world position, or INF if not shown.
func _offset_of(map: NavMap, world: Vector2) -> Vector2:
	for blip in map.get_blips():
		if (blip["world"] as Vector2).distance_to(world) < 1.0:
			return blip["offset"]
	return Vector2.INF


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
