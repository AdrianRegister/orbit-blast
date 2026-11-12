class_name SlotCandidate
extends RefCounted
## What the slot assigner needs to know about one member of a formation, as plain
## data. The assigner never touches ships or nodes, so a formation's slots can be
## worked out and tested without a scene. The runtime builds one of these per
## ship (or per sub-unit) from its model.

## Whatever identifies the member to the caller (a ship, an id). The assigner
## only compares and returns it.
var key: Variant
## How strong it is (CombatRating).
var rating: float = 0.0
## Its size order (ShipClass.tier): lower is smaller and lighter.
var tier: int = 0
## Whether it carries freight (ShipClass.carries_cargo).
var cargo: bool = false
## How much room it needs around it, in pixels: a ship's hit radius, or for a
## sub-unit (a squadron inside a battle group) the unit's whole extent.
var footprint: float = 0.0


static func make(member_key: Variant, member_rating: float, member_tier: int,
		carries_cargo: bool, member_footprint: float) -> SlotCandidate:
	var candidate := SlotCandidate.new()
	candidate.key = member_key
	candidate.rating = member_rating
	candidate.tier = member_tier
	candidate.cargo = carries_cargo
	candidate.footprint = member_footprint
	return candidate


## The candidate for a ship model: rating, tier, cargo and footprint come from
## the model and its class.
static func from_model(member_key: Variant, model: ShipStats) -> SlotCandidate:
	var ship_class := model.ship_class
	return make(member_key, CombatRating.of(model),
			ship_class.tier if ship_class != null else 0,
			ship_class.carries_cargo() if ship_class != null else false,
			model.get_hit_radius())
