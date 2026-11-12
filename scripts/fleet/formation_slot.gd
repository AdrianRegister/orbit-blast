class_name FormationSlot
extends RefCounted
## One place in a formation: where a ship holds station relative to the leader,
## and what kind of place it is. A formation's shape makes a list of these for
## however many ships it has (see FormationGeometry); the first (index 0) is
## always the leader's own place, at the origin.
##
## Offsets are in the leader's frame: +x is straight ahead of the leader, +y is
## to its right (the same as the ship's heading frame, where 0 radians faces
## right and +y is clockwise on screen). A slot's world position is
## `leader_position + offset.rotated(leader_heading)`.

## What kind of place a slot is. Shapes say which ships suit which zone (see
## FormationZoneRule), and later each zone can carry its own tactical bonuses.
##  LEAD   - the leader's own place (index 0).
##  FRONT  - ahead of the main body (a diamond's tip, a convoy's front guard).
##  FLANK  - to the side of the body.
##  CORE   - inside the formation, protected by the ships around it.
##  REAR   - behind the body (the last rank of a wedge, a rear guard).
##  SCREEN - a forward picket line placed to meet threats before they reach the rest.
##  END    - the outermost ends of a line.
enum Zone { LEAD, FRONT, FLANK, CORE, REAR, SCREEN, END }

## Where the ship holds station, in the leader's frame (see above).
var offset: Vector2 = Vector2.ZERO
var zone: Zone = Zone.FLANK
## Position in the slot list, which is also the order slots are filled within a
## zone (lower first): the places most worth holding come first. 0 is the leader.
var index: int = 0


static func make(slot_offset: Vector2, slot_zone: Zone) -> FormationSlot:
	var slot := FormationSlot.new()
	slot.offset = slot_offset
	slot.zone = slot_zone
	return slot


static func zone_name(slot_zone: Zone) -> String:
	return Zone.keys()[slot_zone].capitalize()
