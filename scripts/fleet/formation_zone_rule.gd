class_name FormationZoneRule
extends Resource
## One line of a formation shape's seating plan: which kind of ship fills the
## slots of a zone. A shape lists these in the order the zones are filled, so for
## a wedge "flanks: strongest ships" then "rear: whoever is left" puts strong ships
## on the inner ranks and the weakest at the back. Static data inside the shape's
## .tres.

## Which ships may take a slot, and which of them is picked first.
##  STRONGEST - the highest rating.
##  LIGHTEST  - the smallest class first (ties: the stronger).
##  CARGO     - only freight carriers, the strongest first.
##  NON_CARGO - only ships that do not carry freight, the strongest first.
##  ANY       - the strongest of whoever is left.
enum Filter { STRONGEST, LIGHTEST, CARGO, NON_CARGO, ANY }

@export var zone: FormationSlot.Zone = FormationSlot.Zone.FLANK
@export var filter: Filter = Filter.STRONGEST
