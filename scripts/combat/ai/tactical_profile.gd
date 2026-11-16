class_name TacticalProfile
extends Resource
## How a unit's commander (UnitCommander, FleetCommander) behaves: whether it goes looking for a
## fight, how bad the odds it takes on, how far it chases, when it gives up, whom it prefers
## to shoot, how it protects what it escorts, and which shapes it uses against which enemy.
## Data only: the logic is the commanders'. The named profiles are in
## resources/combat/ai/profiles/: military_patrol, military_attack, convoy_escort, pirate and
## mercenary, and `default` for a unit given none (a FormationRecipe names its own, and the
## spawner can override it). All numbers are first guesses.

const DEFAULT_PATH := "res://resources/combat/ai/profiles/default.tres"

static var _default: TacticalProfile


## The profile a unit uses when nothing else is given (loaded once).
static func default() -> TacticalProfile:
	if _default == null:
		_default = load(DEFAULT_PATH)
	return _default


@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Awareness")
## Seconds between the commander's decisions.
@export_range(0.1, 5.0) var think_interval: float = 1.0
## It notices hostile ships this far (pixels) from its flagship: the unit closes in
## (INTERCEPTING), or a convoy's escorts get ready (DEFENDING).
@export_range(500.0, 20000.0) var sight_radius: float = 4500.0
## Hostile ships this close to any of its ships start the fight (ATTACKING).
@export_range(300.0, 10000.0) var engage_radius: float = 2500.0
## With no hostile ship in sight for this long (seconds) the unit stands down and
## re-forms.
@export_range(0.0, 60.0) var calm_seconds: float = 6.0

@export_group("Aggression")
## Whether it goes for hostile ships it merely sees. Off, it only fights ships that have
## attacked it or something it guards (a grudge), or that are targeting one of its ships:
## it retaliates, and otherwise lets the enemy be.
@export var proactive: bool = true
## The strongest the armed enemy in sight may be, as a multiple of the unit's own strength
## (CombatRating), for the unit to fight it. Above that it withdraws (0: any odds).
@export_range(0.0, 20.0) var max_odds: float = 0.0
## How far (pixels) from where the fight began the unit chases before it gives up on what it
## is chasing (and ignores it for `give_up_seconds`) and returns to its route (0: no limit,
## the sight radius is the leash).
@export_range(0.0, 30000.0) var pursuit_leash: float = 0.0
@export_range(1.0, 300.0) var give_up_seconds: float = 30.0
## Added to the score of a cargo ship as a target (a pirate wants the freight).
@export_range(0.0, 5.0) var target_bias_cargo: float = 0.0

@export_group("Caution")
## The unit withdraws when it has lost more than this share of its peak strength...
@export_range(0.0, 1.0) var withdraw_losses: float = 0.8
## ...or when its flagship's hull is below this fraction (0: never). A wounded leader
## keeps fighting until it dies and the next ship is promoted.
@export_range(0.0, 1.0) var flagship_withdraw_hull: float = 0.0

@export_group("Orders")
## An escort stays within this distance (pixels) of what it guards, and only takes
## enemies within 1.5 times it.
@export_range(200.0, 5000.0) var guard_radius: float = 900.0
## At least this many ships go for each enemy (fighters in pairs).
@export_range(1, 8) var min_attackers: int = 2

@export_group("Battle groups and fleets")
## A battle group sends this many of its squadrons to screen its big ships when the enemy
## has light craft; the others strike.
@export_range(0, 4) var screen_squadrons: int = 1
## How much a strike squadron prefers small craft (fighters, gunboats) as targets.
@export_range(0.0, 5.0) var strike_bias: float = 1.0
## A fleet notices hostile ships this far (pixels) from its flagship, and (for the
## intercept objective) has caught its target when it is within `engage_radius`.
@export_range(1000.0, 30000.0) var fleet_sight_radius: float = 6000.0
## What a fleet with this profile sets out to do (a FleetCommander.Objective): 0 offensive
## (engage what it sees), 1 defensive (hold where it first stands, and fight what comes
## within `sight_radius` of that place).
@export_enum("Offensive", "Defensive") var default_objective: int = 0

@export_group("Shapes")
## The shape on meeting an enemy that is mostly light craft (a screen), mostly big
## ships (a line), or neither (a wedge). Null keeps the unit's own shape. A convoy
## never changes shape: its freighters are the middle of it.
@export var shape_against_light: FormationShape
@export var shape_against_heavy: FormationShape
@export var shape_otherwise: FormationShape
## The share of the enemy that must be of one kind for the first two to apply.
@export_range(0.5, 1.0) var shape_majority: float = 0.5


## The hostile ships a unit with this profile takes notice of. A proactive profile takes
## notice of all of `hostiles`. Otherwise it only does when one of them has a grudge against
## `lead` (it attacked the unit or something it guards: see Hostility) or is targeting one of
## `own` (the unit's ships), and then of all of them, the whole enemy force being its business.
func filter_hostiles(lead: Combatant, own: Array[Combatant], hostiles: Array[Combatant]) -> Array[Combatant]:
	if proactive or hostiles.is_empty():
		return hostiles
	for other in hostiles:
		var grudge: bool = lead.hostility != null and lead.hostility.has_grudge(lead, other)  # (a war enemy that attacked it counts too)
		if grudge or own.has(other.get_target()):
			return hostiles
	var none: Array[Combatant] = []
	return none


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if think_interval <= 0.0:
		problems.append("think_interval must be positive")
	if fleet_sight_radius < sight_radius:
		problems.append("fleet_sight_radius cannot be less than sight_radius")
	if engage_radius > sight_radius:
		problems.append("engage_radius cannot be more than sight_radius")
	if pursuit_leash > 0.0 and pursuit_leash < engage_radius:
		problems.append("pursuit_leash cannot be less than engage_radius")
	return problems
