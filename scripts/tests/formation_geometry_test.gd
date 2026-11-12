extends SceneTree
## Tests formation shapes: the slot layouts (FormationGeometry) and who is seated
## where (SlotAssigner). All pure maths, no scene.
##   Godot --headless --path . --script res://scripts/tests/formation_geometry_test.gd </dev/null

const Z := FormationSlot.Zone

var _failures: int = 0
var _registry: ContentRegistry


func _init() -> void:
	_registry = ContentRegistry.new()
	_test_shape_files()
	_test_layouts_never_crowd()
	_test_wedge()
	_test_line()
	_test_diamond()
	_test_screen()
	_test_ring()
	_test_symmetry()
	_test_spacing_and_extent()
	_test_assignment_wedge()
	_test_assignment_ring_and_screen()
	_test_assignment_stability()
	_test_assignment_invariants()
	_test_real_ships()

	print("FORMATION GEOMETRY TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _shape(id: StringName) -> FormationShape:
	return _registry.formation_shape(id)


func _zones(slots: Array[FormationSlot]) -> Array:
	return slots.map(func(slot: FormationSlot) -> int: return slot.zone)


# ------------------------------------------------------------------ data

func _test_shape_files() -> void:
	var shapes := _registry.formation_shapes()
	_check(shapes.size() == 6, "six formation shapes exist (%d)" % shapes.size())
	var ids := {}
	for shape in shapes:
		_check(shape.validate().is_empty(), "%s validates %s" % [shape.id, shape.validate()])
		_check(not ids.has(shape.id), "%s has a unique id" % shape.id)
		ids[shape.id] = true
		_check(not shape.zone_rules.is_empty(), "%s has a seating plan" % shape.id)
	for id in [&"wedge", &"line", &"diamond", &"screen", &"convoy", &"convoy_diamond"]:
		_check(_shape(id) != null, "the shape '%s' can be looked up" % id)
	_check(FormationTuning.shared().validate().is_empty(), "the formation tuning validates")

	var bad := FormationShape.new()
	_check(not bad.validate().is_empty(), "a shape with no id or name is invalid")
	var narrow := FormationShape.new()
	narrow.id = &"x"
	narrow.display_name = "X"
	narrow.layout = FormationShape.Layout.WEDGE
	narrow.angle_degrees = 0.0
	_check(not narrow.validate().is_empty(), "a wedge with no angle is invalid")
	var column := FormationShape.new()
	column.id = &"y"
	column.display_name = "Y"
	column.layout = FormationShape.Layout.LINE
	column.angle_degrees = 0.0
	column.mirror = true
	_check(not column.validate().is_empty(), "a mirrored column is invalid (mirror must be off for a column)")
	var tight := FormationShape.new()
	tight.id = &"z"
	tight.display_name = "Z"
	tight.layout = FormationShape.Layout.RING
	tight.core_radius_factor = 1.5
	tight.escort_radius_factor = 1.6
	_check(not tight.validate().is_empty(), "a ring whose rings are less than a spacing apart is invalid")


# --------------------------------------------------------------- layouts

## No two slots are ever closer than the spacing (a bit of slack for rounding),
## for every shape and every size a formation can have.
func _test_layouts_never_crowd() -> void:
	for shape in _registry.formation_shapes():
		var worst := INF
		var spacing := 100.0
		for count in range(1, 15):
			for inner in [-1, 1, 2, 3, count]:
				var slots := FormationGeometry.build_slots(shape, count, spacing, inner)
				if slots.size() != count:
					_check(false, "%s with %d ships makes %d slots" % [shape.id, count, slots.size()])
					return
				worst = minf(worst, FormationGeometry.min_separation(slots))
				if not (slots[0].offset == Vector2.ZERO and slots[0].zone == Z.LEAD and slots[0].index == 0):
					_check(false, "%s with %d ships: slot 0 is not the leader at the origin" % [shape.id, count])
					return
		_check(worst >= spacing * 0.999, "%s never packs ships closer than the spacing (closest %.1f of %.0f)" % [shape.id, worst, spacing])


func _test_wedge() -> void:
	var wedge := _shape(&"wedge")
	var spacing := 100.0
	var slots := FormationGeometry.build_slots(wedge, 5, spacing)
	_check(slots.size() == 5 and slots[0].offset == Vector2.ZERO, "a wedge of five has a tip at the origin")
	_check(_zones(slots) == [Z.LEAD, Z.FLANK, Z.FLANK, Z.REAR, Z.REAR], "wedge zones: tip, one rank of flanks, a rear rank")
	var behind := true
	for index in range(1, slots.size()):
		behind = behind and slots[index].offset.x < 0.0
	_check(behind, "every other ship is behind the tip")
	_check(is_equal_approx(slots[1].offset.y, -slots[2].offset.y) and slots[1].offset.y < 0.0, "a rank is a left and a right ship, the left one first")
	_check(slots[3].offset.length() > slots[1].offset.length(), "the second rank is farther back than the first")
	_check(is_equal_approx(slots[1].offset.length(), spacing), "the first rank is one spacing from the tip")
	var wide := FormationGeometry.build_slots(wedge, 3, spacing)
	_check(_zones(wide) == [Z.LEAD, Z.FLANK, Z.FLANK], "a wedge of three is a tip and one rank")
	var arrow := FormationShape.new()
	arrow.layout = FormationShape.Layout.WEDGE
	arrow.angle_degrees = 20.0
	var narrow_slots := FormationGeometry.build_slots(arrow, 5, spacing)
	_check(absf(narrow_slots[1].offset.y) < absf(slots[1].offset.y), "a smaller wedge angle makes a narrower wedge")
	_check(FormationGeometry.build_slots(wedge, 1, spacing).size() == 1, "one ship is just the leader")
	_check(FormationGeometry.build_slots(wedge, 0, spacing).size() == 1, "a count of zero still gives the leader's place")


func _test_line() -> void:
	var line := _shape(&"line")
	var spacing := 100.0
	var slots := FormationGeometry.build_slots(line, 5, spacing)
	var abreast := true
	for slot in slots:
		abreast = abreast and absf(slot.offset.x) < 0.001
	_check(abreast, "ships in a line are abreast of the leader")
	_check(_zones(slots) == [Z.LEAD, Z.FLANK, Z.FLANK, Z.END, Z.END], "line zones: leader, inner ships, both ends")
	_check(is_equal_approx(slots[1].offset.y, -spacing) and is_equal_approx(slots[2].offset.y, spacing), "the first two ships are either side of the leader")
	_check(_zones(FormationGeometry.build_slots(line, 4, spacing)) == [Z.LEAD, Z.FLANK, Z.FLANK, Z.END], "a line of four has one end ship")
	_check(_zones(FormationGeometry.build_slots(line, 2, spacing)) == [Z.LEAD, Z.END], "a line of two ends with its second ship")

	# The same layout makes a column and an echelon from different numbers.
	var column := FormationShape.new()
	column.layout = FormationShape.Layout.LINE
	column.angle_degrees = 0.0
	column.mirror = false
	var single_file := FormationGeometry.build_slots(column, 4, spacing)
	var in_file := true
	for index in 4:
		in_file = in_file and absf(single_file[index].offset.y) < 0.001 and is_equal_approx(single_file[index].offset.x, -spacing * index)
	_check(in_file, "angle 0 with mirror off is a column: single file behind the leader")
	_check(_zones(single_file) == [Z.LEAD, Z.FLANK, Z.FLANK, Z.END], "a column's last ship is its end")
	var echelon := FormationShape.new()
	echelon.layout = FormationShape.Layout.LINE
	echelon.angle_degrees = 45.0
	echelon.mirror = false
	var diagonal := FormationGeometry.build_slots(echelon, 3, spacing)
	_check(diagonal[1].offset.x < 0.0 and diagonal[1].offset.y > 0.0 and is_equal_approx(absf(diagonal[1].offset.x), absf(diagonal[1].offset.y)), "angle 45 with mirror off is a diagonal echelon")
	_check(is_equal_approx(diagonal[2].offset.length(), 2.0 * spacing), "an echelon's second ship is two spacings out")


func _test_diamond() -> void:
	var diamond := _shape(&"diamond")
	var spacing := 100.0
	var four := FormationGeometry.build_slots(diamond, 4, spacing)
	_check(_zones(four) == [Z.LEAD, Z.FLANK, Z.FLANK, Z.REAR], "four ships make a clean diamond: tip, two flanks, rear")
	_check(four[0].offset == Vector2.ZERO and four[3].offset.x < four[1].offset.x, "the rear ship is behind the flanks, which are behind the tip")
	_check(is_equal_approx(four[3].offset.y, 0.0), "the rear ship is on the centre line")
	var five := FormationGeometry.build_slots(diamond, 5, spacing)
	_check(_zones(five) == [Z.LEAD, Z.FLANK, Z.FLANK, Z.REAR, Z.CORE], "a fifth ship sits in the middle of the diamond")
	_check(is_equal_approx(five[4].offset.y, 0.0) and five[4].offset.x < five[0].offset.x and five[4].offset.x > five[3].offset.x, "the core ship is on the centre line between the tip and the rear")
	_check(is_equal_approx(FormationGeometry.min_separation(five), spacing), "the lattice points are exactly one spacing apart")

	# A convoy diamond puts the leader in the middle, the tip ahead of it.
	var convoy := _shape(&"convoy_diamond")
	var core := FormationGeometry.build_slots(convoy, 5, spacing)
	_check(core[0].offset == Vector2.ZERO and core[0].zone == Z.LEAD, "with lead_at_core the leader is still slot 0 at the origin")
	_check(_zones(core) == [Z.LEAD, Z.FRONT, Z.FLANK, Z.FLANK, Z.REAR], "a convoy diamond of five: leader in the middle, a tip ahead, flanks, a rear")
	_check(core[1].offset.x > 0.0 and core[4].offset.x < 0.0, "the front ship is ahead of the leader and the rear ship behind")
	var nine := FormationGeometry.build_slots(convoy, 9, spacing)
	var cores := nine.filter(func(slot: FormationSlot) -> bool: return slot.zone == Z.CORE)
	_check(cores.size() == 4, "a convoy diamond of nine has four sheltered core places around the leader (%d)" % cores.size())
	var sheltered := true
	for slot: FormationSlot in cores:
		sheltered = sheltered and slot.offset.length() <= spacing * 1.01
	_check(sheltered, "the core places are the ones nearest the leader")
	_check(FormationGeometry.build_slots(convoy, 2, spacing).size() == 2, "a tiny convoy diamond still works")


func _test_screen() -> void:
	var screen := _shape(&"screen")
	var spacing := 100.0
	var slots := FormationGeometry.build_slots(screen, 6, spacing)
	var pickets := slots.filter(func(slot: FormationSlot) -> bool: return slot.zone == Z.SCREEN)
	var core := slots.filter(func(slot: FormationSlot) -> bool: return slot.zone == Z.CORE or slot.zone == Z.LEAD)
	_check(pickets.size() == 3 and core.size() == 3, "six ships default to three pickets and three behind them")
	var ahead := true
	for slot: FormationSlot in pickets:
		ahead = ahead and slot.offset.x > spacing
	_check(ahead, "pickets are ahead of the leader")
	var held := true
	for slot: FormationSlot in core:
		held = held and slot.offset.x <= 0.001
	_check(held, "the block holding the leader is not ahead of it")
	_check(is_equal_approx(pickets[0].offset.x, spacing * screen.screen_depth_factor), "the picket line is screen_depth_factor spacings ahead")
	var by_hand := FormationGeometry.build_slots(screen, 6, spacing, 5)
	_check(by_hand.filter(func(slot: FormationSlot) -> bool: return slot.zone == Z.SCREEN).size() == 1, "inner_count sets how many ships stay behind the pickets")
	var no_pickets := FormationGeometry.build_slots(screen, 4, spacing, 4)
	_check(no_pickets.filter(func(slot: FormationSlot) -> bool: return slot.zone == Z.SCREEN).is_empty(), "with every ship inner there is no picket line")
	var alone := FormationGeometry.build_slots(screen, 4, spacing, 0)
	_check(alone.filter(func(slot: FormationSlot) -> bool: return slot.zone == Z.SCREEN).size() == 3, "the leader always stays behind the pickets")
	var centre := pickets[0] as FormationSlot
	_check(is_equal_approx(centre.offset.y, 0.0) and is_equal_approx(pickets[1].offset.y, -spacing) and is_equal_approx(pickets[2].offset.y, spacing), "pickets fill from the centre of the line, left then right")


func _test_ring() -> void:
	var ring := _shape(&"convoy")
	var spacing := 100.0
	var slots := FormationGeometry.build_slots(ring, 7, spacing, 3)
	_check(slots.size() == 7 and slots[0].offset == Vector2.ZERO, "a ring of seven has the leader in the middle")
	_check(_zones(slots) == [Z.LEAD, Z.CORE, Z.CORE, Z.FRONT, Z.FLANK, Z.FLANK, Z.REAR], "ring zones: leader, inner ring, then escorts front first and the rear guard last")
	var inner_radius := slots[1].offset.length()
	_check(is_equal_approx(slots[2].offset.length(), inner_radius), "the inner ring is a circle around the leader")
	var escort_radius := slots[3].offset.length()
	_check(escort_radius >= inner_radius + spacing * 0.999, "the escorts ring is a spacing outside the inner ring")
	_check(slots[3].offset.x > 0.0 and absf(slots[3].offset.y) < 0.001, "the first escort is dead ahead")
	_check(slots[6].offset.x < 0.0, "the last escort is behind")
	var even := true
	for index in range(3, 7):
		even = even and is_equal_approx(slots[index].offset.length(), escort_radius)
	_check(even, "the escorts all sit on one ring")
	var only_leader := FormationGeometry.build_slots(ring, 5, spacing, 1)
	_check(_zones(only_leader).filter(func(zone: int) -> bool: return zone == Z.CORE).is_empty(), "with only the leader inside, every other ship is an escort")
	# With very many escorts the outer ring grows past its set radius so they fit side by side.
	var crowded := FormationGeometry.build_slots(ring, 20, spacing, 1)
	_check(crowded[1].offset.length() > ring.escort_radius_factor * spacing, "a ring with very many escorts widens until they fit (%.0f px)" % crowded[1].offset.length())
	_check(FormationGeometry.min_separation(crowded) >= spacing * 0.999, "and the widened ring keeps them apart")
	var full_convoy := FormationGeometry.build_slots(ring, 11, spacing, 5)
	_check(FormationGeometry.min_separation(full_convoy) >= spacing * 0.999, "the largest convoy (five freighters, six escorts) keeps every ship clear")


## Odd-sized formations of symmetrical shapes mirror left and right.
func _test_symmetry() -> void:
	for id in [&"wedge", &"line", &"diamond"]:
		for count in [3, 5, 7, 9]:
			var slots := FormationGeometry.build_slots(_shape(id), count, 100.0)
			var mirrored := true
			for slot in slots:
				var twin := false
				for other in slots:
					if absf(other.offset.x - slot.offset.x) < 0.01 and absf(other.offset.y + slot.offset.y) < 0.01:
						twin = true
				mirrored = mirrored and twin
			_check(mirrored, "%s of %d ships is symmetrical" % [id, count])


func _test_spacing_and_extent() -> void:
	var wedge := _shape(&"wedge")
	var tuning := FormationTuning.shared()
	_check(FormationGeometry.compute_spacing(wedge, [24.0, 24.0, 28.0], tuning) == wedge.spacing, "small ships use the shape's own spacing")
	var big := FormationGeometry.compute_spacing(wedge, [160.0, 120.0, 24.0], tuning)
	_check(is_equal_approx(big, tuning.spacing_gap_factor * 280.0) and big > wedge.spacing, "a capital ship and a cruiser widen the spacing (%.0f)" % big)
	_check(FormationGeometry.compute_spacing(wedge, [], tuning) == wedge.spacing, "no members: the shape's spacing")
	_check(FormationGeometry.compute_spacing(wedge, [200.0], tuning) >= tuning.spacing_gap_factor * 200.0, "a lone giant still gets room")
	var slots := FormationGeometry.build_slots(wedge, 5, 100.0)
	_check(FormationGeometry.extent(slots) == slots[3].offset.length() or FormationGeometry.extent(slots) == slots[4].offset.length(), "extent is the farthest slot from the leader")
	_check(FormationGeometry.extent(FormationGeometry.build_slots(wedge, 1, 100.0)) == 0.0, "a lone leader has no extent")
	_check(FormationGeometry.min_separation(FormationGeometry.build_slots(wedge, 1, 100.0)) == INF, "min_separation of one slot is infinite")


# ------------------------------------------------------------- assignment

func _candidate(key: Variant, rating: float, tier: int = 0, cargo: bool = false) -> SlotCandidate:
	return SlotCandidate.make(key, rating, tier, cargo, 30.0)


func _slot_index(seating: Dictionary, key: Variant) -> int:
	return (seating[key] as FormationSlot).index if seating.has(key) else -1


func _test_assignment_wedge() -> void:
	var wedge := _shape(&"wedge")
	var slots := FormationGeometry.build_slots(wedge, 5, 100.0)
	var members: Array[SlotCandidate] = [
		_candidate("d", 60.0), _candidate("lead", 100.0), _candidate("b", 80.0), _candidate("c", 70.0), _candidate("a", 90.0)]
	var seating := SlotAssigner.assign(wedge, slots, members, "lead")
	_check(_slot_index(seating, "lead") == 0, "the leader holds the tip")
	_check(_slot_index(seating, "a") == 1 and _slot_index(seating, "b") == 2, "the strongest ships take the inner rank (a, b)")
	_check(_slot_index(seating, "c") == 3 and _slot_index(seating, "d") == 4, "the rest take the rear rank, strongest first")
	_check(seating.size() == 5, "everyone is seated")


func _test_assignment_ring_and_screen() -> void:
	# A convoy: freighters inside, the strongest escort in front, the next at the rear.
	var ring := _shape(&"convoy")
	var slots := FormationGeometry.build_slots(ring, 7, 130.0, 3)
	var members: Array[SlotCandidate] = [
		_candidate("freight_lead", 30.0, 2, true), _candidate("freight_b", 25.0, 2, true), _candidate("freight_c", 20.0, 3, true),
		_candidate("escort_4", 60.0), _candidate("escort_1", 150.0), _candidate("escort_3", 80.0), _candidate("escort_2", 100.0)]
	var seating := SlotAssigner.assign(ring, slots, members, "freight_lead")
	_check(_slot_index(seating, "freight_lead") == 0, "the lead freighter is in the middle")
	_check((seating["freight_b"] as FormationSlot).zone == Z.CORE and (seating["freight_c"] as FormationSlot).zone == Z.CORE, "the other freighters ride in the inner ring")
	_check(_slot_index(seating, "escort_1") == 3 and (seating["escort_1"] as FormationSlot).zone == Z.FRONT, "the strongest escort takes the front")
	_check((seating["escort_2"] as FormationSlot).zone == Z.REAR, "the next strongest is the rear guard")
	_check((seating["escort_3"] as FormationSlot).zone == Z.FLANK and (seating["escort_4"] as FormationSlot).zone == Z.FLANK, "the weaker escorts take the flanks")

	# Without enough cargo ships the inner ring is filled with whoever is left.
	var no_cargo: Array[SlotCandidate] = [
		_candidate("lead", 50.0), _candidate("x", 40.0), _candidate("y", 30.0), _candidate("z", 20.0), _candidate("w", 10.0)]
	var thin := SlotAssigner.assign(ring, FormationGeometry.build_slots(ring, 5, 130.0, 3), no_cargo, "lead")
	_check(thin.size() == 5, "a convoy short of freighters still seats everyone")

	# A screen: the lightest ships are the pickets, the rest stay behind them.
	var screen := _shape(&"screen")
	var screen_slots := FormationGeometry.build_slots(screen, 6, 110.0)
	var fleet: Array[SlotCandidate] = [
		_candidate("cruiser", 400.0, 3), _candidate("frigate_a", 240.0, 2), _candidate("frigate_b", 230.0, 2),
		_candidate("fighter_a", 100.0, 0), _candidate("fighter_b", 95.0, 0), _candidate("heavy", 170.0, 1)]
	var picket_seating := SlotAssigner.assign(screen, screen_slots, fleet, "cruiser")
	var picket_keys := ["fighter_a", "fighter_b", "heavy"]
	var all_pickets := true
	for key in picket_keys:
		all_pickets = all_pickets and (picket_seating[key] as FormationSlot).zone == Z.SCREEN
	_check(all_pickets, "the three lightest ships are the pickets")
	_check((picket_seating["frigate_a"] as FormationSlot).zone == Z.CORE and (picket_seating["frigate_b"] as FormationSlot).zone == Z.CORE, "the frigates stay behind the screen")
	_check(_slot_index(picket_seating, "fighter_a") < _slot_index(picket_seating, "fighter_b"), "the stronger of two equal-class pickets holds the centre of the line")

	# Diamond: strong ships on the flanks and rear, the weakest sheltered in the core.
	var diamond := _shape(&"diamond")
	var diamond_seating := SlotAssigner.assign(diamond, FormationGeometry.build_slots(diamond, 5, 100.0),
			[_candidate("lead", 500.0), _candidate("a", 400.0), _candidate("b", 300.0), _candidate("c", 200.0), _candidate("weak", 10.0)], "lead")
	_check((diamond_seating["weak"] as FormationSlot).zone == Z.CORE, "the weakest ship is sheltered in the diamond's core")
	_check((diamond_seating["a"] as FormationSlot).zone == Z.FLANK and (diamond_seating["b"] as FormationSlot).zone == Z.FLANK, "the strongest ships hold the flanks")
	_check((diamond_seating["c"] as FormationSlot).zone == Z.REAR, "the next holds the rear")


func _test_assignment_stability() -> void:
	var wedge := _shape(&"wedge")
	var slots := FormationGeometry.build_slots(wedge, 4, 100.0)
	# Three identical fighters: the one that held the nearer place keeps it.
	var members: Array[SlotCandidate] = [_candidate("lead", 100.0), _candidate("k1", 50.0), _candidate("k2", 50.0), _candidate("k3", 50.0)]
	var seating := SlotAssigner.assign(wedge, slots, members, "lead", {"k1": 2, "k2": 1, "k3": 3})
	_check(_slot_index(seating, "k2") == 1 and _slot_index(seating, "k1") == 2 and _slot_index(seating, "k3") == 3, "equal ships keep the order they held (nearest place first)")
	var again := SlotAssigner.assign(wedge, slots, members, "lead", {"k1": 2, "k2": 1, "k3": 3})
	_check(_slot_index(again, "k2") == _slot_index(seating, "k2") and _slot_index(again, "k3") == _slot_index(seating, "k3"), "the same input gives the same seating")
	# Without history the input order decides, and is stable.
	var plain := SlotAssigner.assign(wedge, slots, members, "lead")
	_check(_slot_index(plain, "k1") == 1 and _slot_index(plain, "k2") == 2 and _slot_index(plain, "k3") == 3, "with no history, equal ships keep the order they were given")

	# A ship is lost: the ones behind move up one place each.
	var smaller := FormationGeometry.build_slots(wedge, 3, 100.0)
	var survivors: Array[SlotCandidate] = [_candidate("lead", 100.0), _candidate("k1", 50.0), _candidate("k3", 50.0)]
	var closed := SlotAssigner.assign(wedge, smaller, survivors, "lead", {"k1": 2, "k3": 3, "lead": 0})
	_check(_slot_index(closed, "k1") == 1 and _slot_index(closed, "k3") == 2, "ranks close up when a ship is lost")


func _test_assignment_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for shape in _registry.formation_shapes():
		var ok := true
		for trial in 40:
			var count := rng.randi_range(1, 12)
			var inner := rng.randi_range(1, count)
			var slots := FormationGeometry.build_slots(shape, count, 100.0, inner)
			var members: Array[SlotCandidate] = []
			for i in count:
				members.append(_candidate(i, rng.randf_range(10.0, 500.0), rng.randi_range(0, 4), rng.randf() < 0.4))
			var seating := SlotAssigner.assign(shape, slots, members, rng.randi_range(0, count - 1))
			var used := {}
			for key in seating:
				used[(seating[key] as FormationSlot).index] = true
			ok = ok and seating.size() == count and used.size() == count
		_check(ok, "%s: over 40 random formations, everyone is seated once in a different slot" % shape.id)
	_check(SlotAssigner.assign(_shape(&"wedge"), [], [], 0).is_empty(), "no slots or no members seats nobody")


func _test_real_ships() -> void:
	# A squadron: two fighters and a heavy fighter in a wedge. The heavy fighter is the strongest, so it leads at the tip.
	var heavy := _registry.ship_stats(&"federation_heavy_fighter")
	var fighter := _registry.ship_stats(&"federation_fighter")
	var members: Array[SlotCandidate] = [
		SlotCandidate.from_model("f1", fighter), SlotCandidate.from_model("h", heavy), SlotCandidate.from_model("f2", fighter)]
	var strongest: SlotCandidate = members[0]
	for candidate in members:
		if candidate.rating > strongest.rating:
			strongest = candidate
	_check(strongest.key == "h", "the heavy fighter is the squadron's strongest ship")
	var radii: Array = members.map(func(c: SlotCandidate) -> float: return c.footprint)
	var wedge := _shape(&"wedge")
	var spacing := FormationGeometry.compute_spacing(wedge, radii)
	var seating := SlotAssigner.assign(wedge, FormationGeometry.build_slots(wedge, 3, spacing), members, strongest.key)
	_check(_slot_index(seating, "h") == 0, "the heavy fighter takes the tip of the spear")

	# A convoy: freighters in the middle, the light frigate (stronger than the interceptors) at the front.
	var convoy_ships := [
		["bulk", &"bulk_freighter"], ["f1", &"freighter"], ["i1", &"interceptor"], ["i2", &"interceptor"], ["i3", &"interceptor"], ["lf", &"light_frigate"]]
	var convoy: Array[SlotCandidate] = []
	for entry in convoy_ships:
		convoy.append(SlotCandidate.from_model(entry[0], _registry.ship_stats(entry[1])))
	var shape := _shape(&"convoy")
	var convoy_radii: Array = convoy.map(func(c: SlotCandidate) -> float: return c.footprint)
	var convoy_spacing := FormationGeometry.compute_spacing(shape, convoy_radii)
	var convoy_seating := SlotAssigner.assign(shape, FormationGeometry.build_slots(shape, 6, convoy_spacing, 2), convoy, "bulk")
	_check(_slot_index(convoy_seating, "bulk") == 0 and (convoy_seating["f1"] as FormationSlot).zone == Z.CORE, "the freighters hold the middle of the convoy")
	_check((convoy_seating["lf"] as FormationSlot).zone == Z.FRONT, "the light frigate is the front guard")
	_check((convoy_seating["i1"] as FormationSlot).zone != Z.CORE and (convoy_seating["i2"] as FormationSlot).zone != Z.CORE, "interceptors ride outside the freighters")
	var clear := FormationGeometry.min_separation(FormationGeometry.build_slots(shape, 6, convoy_spacing, 2))
	_check(clear >= convoy_spacing * 0.999 and convoy_spacing >= shape.spacing, "the convoy's slots keep the biggest ships clear (%.0f px)" % clear)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
