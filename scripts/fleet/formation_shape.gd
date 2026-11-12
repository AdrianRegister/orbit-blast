class_name FormationShape
extends Resource
## A formation shape: the pattern ships hold around their leader (wedge, line,
## diamond, defensive screen, convoy circle). One .tres per shape in
## resources/formations/shapes/.
##
## A shape is not movement code. It only says how to lay out slots for any number
## of ships (`layout` plus the numbers below, see FormationGeometry) and which
## kinds of ships belong in which zone (`zone_rules`, see SlotAssigner). The same
## movement then works for every shape, and a new shape (an echelon, a column, a
## wider wedge) is usually just a new file with different numbers.
##
## Nothing names a shape id in code: recipes and traffic rules refer to shapes by
## the resource.

## How the slots are laid out.
##  WEDGE   - a V with the leader at the tip.
##  LINE    - ships side by side along a line through the leader.
##  DIAMOND - a diamond lattice, leader at the front tip (or in the middle).
##  SCREEN  - a picket line ahead of a tight block holding the leader.
##  RING    - the leader in the middle, a ring around it, a wider ring outside.
enum Layout { WEDGE, LINE, DIAMOND, SCREEN, RING }

## Permanent unique id, e.g. &"wedge". Never change it once content refers to it.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var layout: Layout = Layout.WEDGE

## Base distance between neighbouring ships, in pixels. The formation widens it
## when its ships are big (see FormationGeometry.compute_spacing).
@export var spacing: float = 100.0

## WEDGE: how far the arms swing out from the line straight behind the leader
## (small is narrow, 90 would be a line abreast).
## LINE: the line's direction, 0 = single file behind the leader (a column),
## 90 = side by side (abreast), 45 = diagonal (an echelon).
@export_range(0.0, 90.0) var angle_degrees: float = 40.0

## LINE: alternate ships to either side of the leader (abreast). Off puts them
## all on one side of the line (single file or echelon).
@export var mirror: bool = true

## DIAMOND: the leader holds the middle of the diamond instead of its front tip
## (for a convoy, which protects whoever is in the middle).
@export var lead_at_core: bool = false

## SCREEN: how far ahead of the leader the picket line is, in spacings.
@export var screen_depth_factor: float = 3.0

## RING: radius of the inner ring (the ships nearest the leader), in spacings,
## and of the outer ring (the escorts). A ring is also widened until its ships
## fit side by side.
@export var core_radius_factor: float = 1.2
@export var escort_radius_factor: float = 2.4

## The formation breaks up when fewer ships than this are left.
@export var min_members: int = 2

## Which ships fill which zone, in the order the zones are filled. Zones with no
## rule are filled last with whoever is left.
@export var zone_rules: Array[FormationZoneRule] = []


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if spacing <= 0.0:
		problems.append("spacing must be above zero")
	if layout == Layout.LINE and mirror and angle_degrees < 10.0:
		problems.append("a mirrored line needs an angle of at least 10 degrees (0 is a column; turn mirror off)")
	if layout == Layout.WEDGE and (angle_degrees <= 0.0 or angle_degrees >= 90.0):
		problems.append("a wedge needs an angle between 0 and 90 degrees")
	if layout == Layout.SCREEN and screen_depth_factor <= 1.0:
		problems.append("screen_depth_factor must be above 1 so the screen clears the leader")
	if layout == Layout.RING and (core_radius_factor < 1.0 or escort_radius_factor < core_radius_factor + 0.9):
		problems.append("ring radii must keep one spacing between the leader, the inner ring and the outer ring")
	if min_members < 2:
		problems.append("min_members must be at least 2")
	for rule in zone_rules:
		if rule == null:
			problems.append("zone_rules has an empty entry")
	return problems
