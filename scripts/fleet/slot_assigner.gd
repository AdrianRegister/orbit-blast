class_name SlotAssigner
extends RefCounted
## Decides which member holds which slot, as pure maths on SlotCandidate data:
## the leader takes the leader's place, then the shape's zone rules (FormationZoneRule)
## seat the rest zone by zone, and anyone left fills the remaining places. It is
## deterministic: the same members and shape always give the same seating, and when
## members are alike (three identical fighters) the ones that already held the
## nearest places keep them, so ranks close up when a ship is lost instead of
## shuffling.


## Returns {member key: FormationSlot}. `slots` has one slot per candidate (slot 0 is
## the leader's). `lead_key` is the member that holds slot 0. `previous` maps a member
## key to the slot index it held before (optional, only used to break ties).
static func assign(shape: FormationShape, slots: Array[FormationSlot], candidates: Array[SlotCandidate],
		lead_key: Variant, previous: Dictionary = {}) -> Dictionary:
	var result := {}
	var pool: Array[SlotCandidate] = candidates.duplicate()
	if slots.is_empty() or pool.is_empty():
		return result

	# The leader holds the leader's place.
	var leader := _find(pool, lead_key)
	if leader == null:
		push_warning("SlotAssigner: the leader is not among the members; the strongest leads.")
		leader = _pick(pool, FormationZoneRule.Filter.STRONGEST, previous)
	pool.erase(leader)
	result[leader.key] = slots[0]

	var free: Array[FormationSlot] = []
	for index in range(1, slots.size()):
		free.append(slots[index])

	# The shape's seating plan, zone by zone, places most worth holding first.
	for rule in shape.zone_rules:
		var zone_slots: Array[FormationSlot] = free.filter(
				func(slot: FormationSlot) -> bool: return slot.zone == rule.zone)
		zone_slots.sort_custom(func(a: FormationSlot, b: FormationSlot) -> bool: return a.index < b.index)
		for slot in zone_slots:
			var pick := _pick(pool, rule.filter, previous)
			if pick == null:
				break  # nobody suitable is left for this zone; the slot stays free
			result[pick.key] = slot
			pool.erase(pick)
			free.erase(slot)

	# Whoever is left fills the places that are left, strongest first, in slot order.
	free.sort_custom(func(a: FormationSlot, b: FormationSlot) -> bool: return a.index < b.index)
	for slot in free:
		var pick := _pick(pool, FormationZoneRule.Filter.ANY, previous)
		if pick == null:
			break
		result[pick.key] = slot
		pool.erase(pick)
	return result


static func _find(pool: Array[SlotCandidate], key: Variant) -> SlotCandidate:
	for candidate in pool:
		if is_same(candidate.key, key) or candidate.key == key:
			return candidate
	return null


## The best candidate for a filter, or null if none is eligible.
static func _pick(pool: Array[SlotCandidate], filter: FormationZoneRule.Filter, previous: Dictionary) -> SlotCandidate:
	var best: SlotCandidate = null
	for candidate in pool:
		if filter == FormationZoneRule.Filter.CARGO and not candidate.cargo:
			continue
		if filter == FormationZoneRule.Filter.NON_CARGO and candidate.cargo:
			continue
		if best == null or _better(candidate, best, filter, previous):
			best = candidate
	return best


## Whether `a` beats `b` for the filter. Ties are broken by the place held before
## (nearer the front first), then the original order, which `pool` preserves because
## only a strictly better candidate replaces the current best.
static func _better(a: SlotCandidate, b: SlotCandidate, filter: FormationZoneRule.Filter, previous: Dictionary) -> bool:
	if filter == FormationZoneRule.Filter.LIGHTEST:
		if a.tier != b.tier:
			return a.tier < b.tier
	if not is_equal_approx(a.rating, b.rating):
		return a.rating > b.rating
	return previous.get(a.key, 1 << 30) < previous.get(b.key, 1 << 30)
