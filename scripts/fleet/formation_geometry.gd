class_name FormationGeometry
extends RefCounted
## The shapes' slot layouts, as pure maths: for a shape and a number of ships it
## returns the list of FormationSlot a formation of that size holds. It knows
## nothing about ships, nodes or movement, so every layout can be tested on its
## own, and movement works the same whatever the shape.
##
## Slot 0 is always the leader's place, at the origin. Offsets are in the leader's
## frame (+x ahead, +y to the right). Slots are listed in the order they should be
## filled: the most valuable places first, and a shape with an odd number of ships
## stays as symmetrical as it can.

## Row spacing of a lattice of equally spaced points (rows are sqrt(3)/2 apart).
const TRIANGLE_ROW_FACTOR := 0.8660254


## The distance to keep between neighbouring ships: the shape's own spacing, or
## wider when the two biggest members (radii in pixels) would otherwise crowd.
static func compute_spacing(shape: FormationShape, radii: Array, tuning: FormationTuning = null) -> float:
	var gap := (tuning if tuning != null else FormationTuning.shared()).spacing_gap_factor
	var biggest := 0.0
	var second := 0.0
	for radius: float in radii:
		if radius > biggest:
			second = biggest
			biggest = radius
		elif radius > second:
			second = radius
	return maxf(shape.spacing, gap * (biggest + second))


## The slots for `count` ships with `spacing` between neighbours. `inner_count` says
## how many ships belong inside (screen: the ships behind the picket line, ring:
## the ships inside the outer ring, both counting the leader); -1 lets the shape
## decide (half the ships for a screen, only the leader for a ring).
static func build_slots(shape: FormationShape, count: int, spacing: float, inner_count: int = -1) -> Array[FormationSlot]:
	count = maxi(count, 1)
	var slots: Array[FormationSlot]
	match shape.layout:
		FormationShape.Layout.WEDGE:
			slots = _wedge(shape, count, spacing)
		FormationShape.Layout.LINE:
			slots = _line(shape, count, spacing)
		FormationShape.Layout.DIAMOND:
			slots = _diamond(shape, count, spacing)
		FormationShape.Layout.SCREEN:
			slots = _screen(shape, count, spacing, inner_count)
		FormationShape.Layout.RING:
			slots = _ring(shape, count, spacing, inner_count)
	for index in slots.size():
		slots[index].index = index
	return slots


## How far the formation reaches from its leader: the farthest slot. Add a
## member's own radius for the formation's whole footprint (a sub-unit's slot in
## a larger formation needs that much room).
static func extent(slots: Array[FormationSlot]) -> float:
	var farthest := 0.0
	for slot in slots:
		farthest = maxf(farthest, slot.offset.length())
	return farthest


## The smallest distance between any two slots (for checking that ships will not
## crowd each other). Infinity for fewer than two slots.
static func min_separation(slots: Array[FormationSlot]) -> float:
	var smallest := INF
	for a in slots.size():
		for b in range(a + 1, slots.size()):
			smallest = minf(smallest, slots[a].offset.distance_to(slots[b].offset))
	return smallest


# ---------------------------------------------------------------- layouts

## A V: the leader at the tip, then ships in pairs on rank after rank behind it,
## the left one first. The last rank (when there is more than one) is the rear.
static func _wedge(shape: FormationShape, count: int, spacing: float) -> Array[FormationSlot]:
	var slots: Array[FormationSlot] = [FormationSlot.make(Vector2.ZERO, FormationSlot.Zone.LEAD)]
	var angle := deg_to_rad(shape.angle_degrees)
	var step := Vector2(-cos(angle), sin(angle)) * spacing
	var ranks := count / 2  # (ships come in pairs behind the leader)
	for i in count - 1:
		var rank := 1 + i / 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var zone := FormationSlot.Zone.REAR if ranks >= 2 and rank == ranks else FormationSlot.Zone.FLANK
		slots.append(FormationSlot.make(Vector2(step.x * rank, step.y * rank * side), zone))
	return slots


## Ships along a line through the leader. Mirrored (abreast) they alternate to
## either side, the left one first, so the leader stays in the middle; otherwise
## they all trail on one side (a column at 0 degrees, an echelon in between). The
## outermost ship or ships are the ends.
static func _line(shape: FormationShape, count: int, spacing: float) -> Array[FormationSlot]:
	var slots: Array[FormationSlot] = [FormationSlot.make(Vector2.ZERO, FormationSlot.Zone.LEAD)]
	var angle := deg_to_rad(shape.angle_degrees)
	var along := Vector2(-cos(angle), sin(angle)) * spacing
	var others := count - 1
	var last_rank := (others + 1) / 2 if shape.mirror else others
	for i in others:
		var rank: int
		var position: Vector2
		if shape.mirror:
			rank = 1 + i / 2
			var side := -1.0 if i % 2 == 0 else 1.0
			position = Vector2(along.x * rank, along.y * rank * side)
		else:
			rank = i + 1
			position = along * rank
		var zone := FormationSlot.Zone.END if rank == last_rank else FormationSlot.Zone.FLANK
		slots.append(FormationSlot.make(position, zone))
	return slots


## A diamond lattice (rows of 1, 2, 3, 2, 1 points, then 1, 2, 3, 4, 3, 2, 1, and so
## on), every point one spacing from its neighbours, using the smallest lattice
## that holds all ships. The front tip, the two ends of the widest row and the
## rear tip are filled first, so four ships make a clean diamond and five add a
## ship in the middle. The leader holds the front tip, or (lead_at_core) the
## point nearest the middle.
static func _diamond(shape: FormationShape, count: int, spacing: float) -> Array[FormationSlot]:
	var size := 2
	while size * size < count or (shape.lead_at_core and size < 3):
		size += 1
	var row_step := spacing * TRIANGLE_ROW_FACTOR
	var rows := 2 * size - 1
	var widest := size - 1
	var centroid := Vector2(-widest * row_step, 0.0)

	var cells: Array[Dictionary] = []
	for row in rows:
		var width := size - absi(row - widest)
		for j in width:
			var position := Vector2(-row * row_step, (j - (width - 1) / 2.0) * spacing)
			var zone := FormationSlot.Zone.CORE
			var group := 4  # the order cells are taken in: tip, ends of the widest row, rear tip, then the rest
			if row == 0:
				zone = FormationSlot.Zone.FRONT
				group = 0
			elif row == rows - 1:
				zone = FormationSlot.Zone.REAR
				group = 3
			elif row == widest and (j == 0 or j == width - 1):
				zone = FormationSlot.Zone.FLANK
				group = 1 if j == 0 else 2
			cells.append({"position": position, "zone": zone, "group": group, "row": row,
					"distance": position.distance_to(centroid)})

	var leader_index := 0  # the front tip
	if shape.lead_at_core:
		var best := INF
		for index in cells.size():
			var cell: Dictionary = cells[index]
			if cell["zone"] != FormationSlot.Zone.CORE:
				continue
			var score: float = cell["distance"] + absf((cell["position"] as Vector2).y) * 0.001
			if score < best:
				best = score
				leader_index = index
	var leader_cell: Dictionary = cells[leader_index]
	leader_cell["zone"] = FormationSlot.Zone.LEAD
	leader_cell["group"] = -1
	# Cells in fill order: by group, then nearest the middle, then front rows first,
	# then left first. Cells that mirror each other (same distance and row) are taken
	# together, left then right, so odd counts stay symmetrical.
	cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["group"] != b["group"]:
			return a["group"] < b["group"]
		if not is_equal_approx(a["distance"], b["distance"]):
			return a["distance"] < b["distance"]
		if a["row"] != b["row"]:
			return a["row"] < b["row"]
		return (a["position"] as Vector2).y < (b["position"] as Vector2).y)

	var origin: Vector2 = leader_cell["position"]
	var slots: Array[FormationSlot] = []
	for index in mini(count, cells.size()):
		var cell: Dictionary = cells[index]
		slots.append(FormationSlot.make((cell["position"] as Vector2) - origin, cell["zone"]))
	return slots


## A tight block holding the leader, and a picket line ahead of it. The block is
## rows of three (the leader, then one to either side, then the next row behind);
## the picket line is abreast `screen_depth_factor` spacings ahead, the centre
## picket first and then alternately to either side.
static func _screen(shape: FormationShape, count: int, spacing: float, inner_count: int) -> Array[FormationSlot]:
	var core_count := clampi(inner_count if inner_count >= 0 else count - count / 2, 1, count)
	var pickets := count - core_count
	var slots: Array[FormationSlot] = [FormationSlot.make(Vector2.ZERO, FormationSlot.Zone.LEAD)]
	var columns := [0.0, -1.0, 1.0]
	for i in range(1, core_count):
		var row := i / 3
		slots.append(FormationSlot.make(Vector2(-row * spacing, columns[i % 3] * spacing), FormationSlot.Zone.CORE))
	var depth := spacing * shape.screen_depth_factor
	for i in pickets:
		var side := -1.0 if i % 2 == 1 else 1.0
		slots.append(FormationSlot.make(Vector2(depth, ceili(i / 2.0) * spacing * side), FormationSlot.Zone.SCREEN))
	return slots


## The leader in the middle, a ring around it (the inner ships) and a wider ring
## outside (the escorts). Each ring is widened until its ships fit side by side.
## Inner ships sit symmetrically about the leader's heading; the escort ring
## starts with a ship dead ahead and is filled front first, then to the left and
## right, so the heaviest escorts take the front and a rear guard comes last.
static func _ring(shape: FormationShape, count: int, spacing: float, inner_count: int) -> Array[FormationSlot]:
	var inner := clampi(inner_count if inner_count >= 0 else 1, 1, count)
	var core_ships := inner - 1
	var escorts := count - inner
	var slots: Array[FormationSlot] = [FormationSlot.make(Vector2.ZERO, FormationSlot.Zone.LEAD)]

	var core_radius := spacing * shape.core_radius_factor
	if core_ships >= 2:
		core_radius = maxf(core_radius, spacing / (2.0 * sin(PI / core_ships)))
	for k in core_ships:
		var angle := TAU * (k + 0.5) / core_ships
		slots.append(FormationSlot.make(Vector2(cos(angle), sin(angle)) * core_radius, FormationSlot.Zone.CORE))

	if escorts > 0:
		var radius := maxf(spacing * shape.escort_radius_factor, (core_radius if core_ships > 0 else 0.0) + spacing)
		if escorts >= 2:
			radius = maxf(radius, spacing / (2.0 * sin(PI / escorts)))
		var ring: Array[Dictionary] = []
		for k in escorts:
			var angle := wrapf(TAU * k / escorts, -PI, PI)
			var zone := FormationSlot.Zone.FLANK
			if absf(angle) <= PI / 4.0 + 0.001:
				zone = FormationSlot.Zone.FRONT
			elif absf(angle) >= PI * 3.0 / 4.0 - 0.001:
				zone = FormationSlot.Zone.REAR
			ring.append({"angle": angle, "zone": zone})
		ring.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(absf(a["angle"]), absf(b["angle"])):
				return absf(a["angle"]) < absf(b["angle"])
			return a["angle"] < b["angle"])
		for entry in ring:
			var angle: float = entry["angle"]
			slots.append(FormationSlot.make(Vector2(cos(angle), sin(angle)) * radius, entry["zone"]))
	return slots
