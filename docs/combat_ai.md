# NPC combat AI (Phase 3.3)

How NPC ships decide who to fight and how to fight them. Built in steps; this document grows with each. Read it, [combat.md](combat.md), [formations.md](formations.md) and [wars_system.md](../wars_system.md) before changing anything here.

**Built so far:** hostility and awareness (step 2): who is hostile to whom, what a ship can see, how it ranks targets, the doctrines that tune that, and the sandbox's toolbar and battle builder; and what the player is told about it (the navicomputer's colours and **V**, section 11); pilots (step 3, section 6): ships that fight, run and jump out; squadron and convoy commanders (step 4, section 7): a formation that meets an enemy closes on it, breaks to fight with its targets shared out, re-forms afterwards, and withdraws when it is losing; battle group roles and fleet command (step 5, section 8); and the named tactical profiles (step 6, section 9). Not built yet: patrols and convoys as traffic (7), the full battle builder and balancing harness (8), the player's formation selector (9). The plan is in `C:\Users\Adrian\.claude\plans\` and the order of work in the roadmap (`phase_3_roadmap.md`).

## 1. Architecture

Three layers, with orders going down and reports coming up, so one ship's behaviour never depends on group logic:

```
Command layer   FleetCommander (WarFleet) -> UnitCommander (each Formation)   [steps 4-5]
                (a battle group's UnitCommander gives its squadrons roles)
Pilot layer     ShipPilot: one per armed ship; picks a target, flies, fires    [step 3]
Ship layer      NpcShip flies it; Combatant.set_target / fire (same as the player)
Shared, read-only: Hostility (who is an enemy), TacticalPicture (what is where)
```

Pure maths (`Hostility`, `TargetScorer`, later `CombatSteering`) works on plain data and is tested without a scene, like `DamageModel`. All tunable numbers are data (`resources/combat/`). Nothing names a ship class in code: a ship class names its `CombatDoctrine`.

## 2. Hostility

`Hostility` (`scripts/combat/hostility.gd`), the companion of `Allegiance` (friends). The `CombatManager` owns one and gives it to every combatant (`Combatant.hostility`, `Combatant.is_hostile_to(other)`). Two ships are hostile when they are **not allies** and one of these holds (`Hostility.get_reason` names the first, in this order):

| Reason | Rule |
|---|---|
| `war` | Their factions are at war: either faction's `FactionRelation` for the other has `at_war`. (Federation and Hegemony are at war.) |
| `pirates` | One belongs to a faction with `Faction.hostile_to_all` (the Pirates, `faction_3`). A ship that belongs to nobody is a victim of pirates too |
| `reputation` | One is the player and the player's reputation with the other's faction is at or below `HostilityRules.attack_player_reputation` (-80, the start of Hostile) |
| `grudge` | One side attacked the other within `HostilityRules.grudge_seconds` (90) |

It is symmetric, and peace is the default: factions with no relation, and ships that belong to nobody, are not hostile. In the sandbox there is no reputation, so the player is only ever hostile to pirates or through a grudge.

**Grudges are between sides.** A side is a faction, the player (`Hostility.PLAYER_SIDE`), or a ship that belongs to nobody (itself). The player's allies (reputation Friendly or better) count as on the player's side too, so they take up the player's quarrels. `CombatManager` records a grudge (`Hostility.record_attack`) for a **deliberate** attack: anything the player hits, or the target an NPC was shooting at. A stray shot that hits a bystander (the player flying past a dogfight) starts none. Allies never start one. Repeated attacks renew it. Grudges are timed in game time (`CombatManager`'s clock, which stops while paused), end when the system changes (`set_system` clears them) and are **not saved**.

Reputation is still charged only by the `CombatManager`, only for the player's acts. NPC against NPC fights charge nobody.

Rules: `resources/combat/hostility_rules.tres`.

## 3. Awareness: `TacticalPicture`

A node under the star system (the `CombatManager` adds it in `set_system`, so it is freed with the system). It decides nothing and moves nothing; pilots and commanders ask it. Every `REFRESH_INTERVAL` (0.2 s) it lists the live combatants (the player included) and who each NPC is targeting. Positions are read live.

| Query | Answers |
|---|---|
| `get_combatants()` | Every live combatant |
| `hostiles_near(ship, radius)` | The combatants hostile to `ship` within `radius`, nearest first |
| `targeters_of(target)`, `count_targeters(target)` | The ships (never the player: a selection is not an attack) targeting it |
| `threats_to(ship)` | Hostile ships that have chosen it as their target, and armed hostiles within 1.2 times their weapon reach of it |

How far a ship sees is its doctrine's `sensor_range(weapon_range)` (a multiple of its longest weapon's reach).

## 4. Choosing targets: `TargetScorer`

Pure maths on plain data (`ShooterInfo`, `TargetInfo`, `CombatDoctrine`; `from_combatant` builds the first two from live ships). The score of a target is a weighted sum of terms from 0 to 1:

| Term | Meaning |
|---|---|
| effectiveness | The share of my firepower that can hurt it. A nimble target (fighters, heavy fighters) is only hurt by light weapons. A target nothing I carry can hurt is **excluded**, so cruisers and capital ships never choose a fighter and leave fighters to fighters |
| affinity | Is it the size of ship my class is meant for (`preferred_tier_min/max` against `ShipClass.tier`); less the further outside |
| threat | `1 - e^-k`, where k is how many times over it could destroy me within `threat_horizon` seconds. **Times `protect_bonus` when it is attacking a ship I protect**: escort fighters go for the fighters chewing on their cruiser |
| distance | Full inside my weapon reach, falling to nothing at the limit of sight |
| finish | How damaged it already is |
| focus | A commander named it for me |
| overkill | (a penalty) Enough ships are already on it (`attackers_wanted` is its rating over mine) |
| bias | Added as it is: a tactical profile's liking for this kind of target (step 6) |

`TargetScorer.choose` returns the best candidate, but keeps the current target unless the best beats it by the doctrine's `hysteresis` (25%), so ships do not keep changing their minds. `attacking_protected` and `is_focus` are set by the caller (the protecting commander); the scorer has no idea who protects whom.

## 5. Doctrines

A `CombatDoctrine` (`resources/combat/ai/doctrines/`) is how a kind of ship fights, as data: sensor range, preferred target sizes, the target-choice weights above, and how it flies. A ship class names its doctrine (`ShipClass.doctrine`, inherited through `parent`, `get_doctrine()`); ships that never fight (freighters, shuttles) have none. Doctrines are shared by classes:

| Doctrine | Classes | Meant for |
|---|---|---|
| `fighter` | fighter, interceptor | Light craft (tier 0 to 1) |
| `heavy_fighter` | heavy fighter | Tier 0 to 2 |
| `light_warship` | gunboat, frigate, light frigate | Tier 1 to 2 |
| `cruiser` | cruiser | Tier 2 to 4 |
| `capital_ship` | capital ship | Tier 3 to 4 |

The same file says how the ship flies (style, preferred range, rear attack, evasion, strafe, firing tolerance, when to run: section 6). A new ship of an existing class needs nothing; a new class names one of these or a new file.

## 6. Pilots (step 3)

`ShipPilot` (`scripts/combat/ai/ship_pilot.gd`) is the pilot of one NPC ship (`NpcShip.get_pilot()`; every NPC ship has one, a plain object owned by the ship). It decides who to fight or whether to run, and shoots. It flies nothing itself: it produces a `SteeringIntent` (the velocity it wants and the heading to hold) that `NpcShip` flies with the ship's own physics, and it fires through the ship's `Combatant`, so NPCs use the same weapons, cooldowns, energy and shots as the player. It thinks every `AiTuning.decision_interval` (0.25 s, offset per ship) and flies and fires every frame.

**It acts for a ship on its own** (`NpcShip.is_free_agent()`: in no formation or fleet), and only while the ship is flying about (`can_fight()`: not docked, or jumping in or out; a formation member only when its commander has ordered its pilot to take control). Members of formations wait for their unit's commander (section 7), which gives their pilot an order; members of fleets wait for step 5.

### Modes

| Mode | When | What it does |
|---|---|---|
| `IDLE` | Nothing to fight | The ship flies its route (the pilot is not in control) |
| `ATTACK` | A hostile it can hurt is in sight (the doctrine's sensor range) | Picks the best target (`TargetScorer`, section 4), flies at it in the doctrine's style, weaves when it is under attack, fires what would hit |
| `RETREAT` | Its hull is below the doctrine's `retreat_hull_fraction` and an enemy is in sight | Runs, still firing what it can at its target, until it has seen no enemy for `calm_time`; jumps out of the system if there is a way out |
| `FLEE` | A ship with no doctrine (a freighter) and an armed enemy within `flee_alarm_range` | The same, never firing |
| `HOLD` | In a battle line (see below), an enemy in sight, nothing it can hurt and nothing to support | Stays where it is (an anchor) or near its anchor (a screen ship), nose toward the enemy |
| `SUPPORT` | An anchor with point defence, nothing it can hurt, and one of its own fighters fighting | Flies up to within point-defence range of what the fighter is fighting, so that its point defence covers them |

When the pilot takes over, the ship enters `NpcShip.State.ENGAGED` and remembers the state it was in (travelling, wandering, departing ...). When the pilot stands down (no enemy seen for `AiTuning.calm_time`, 3 s) the ship goes back to that state and carries on with its route. The HUD status says what it is doing ("Engaging Federation Fighter", "Retreating", "Fleeing"). A ship on its own with an enemy in sight but nothing it can hurt (a cruiser with only fighters about) stays `IDLE`: it picks no target and does not give chase. In a battle line it holds instead (below).

### How it flies

The pilot's behaviours are pure functions in `CombatSteering` (tested without a scene), each giving a **velocity** the ship should have. `NpcShip._engaged` turns that into flight: a small correction (up to `AiTuning.trim_range`) is made with the station-keeping **trim thrusters** (any direction, a fraction of the thrust, as formation members use) while the nose stays on the pilot's aim; a big one with the main engines (turn toward it, thrust once facing it). Speed, thrust and turn rate are the ship's own.

| Style (doctrine) | Used by | Behaviour |
|---|---|---|
| `DOGFIGHT` | fighters, heavy fighters | Closes to its fighting range and matches the target's velocity there, aiming at where the shot will meet it (`lead_point`). Goes for the target's tail (`rear_attack_weight`) unless it is already within `tail_cone_degrees` of it; after `reposition_limit` seconds without a shot it attacks directly for `commit_time`, so it never spends a fight repositioning |
| `SKIRMISH` | gunboats, frigates | The same at a middle range, plus a slow circle round the target (`strafe`), changing direction every `strafe_period` |
| `STANDOFF` | cruisers, capital ships | Holds its range, faces the target, lets its guns work |

All hold a **fighting range** of `preferred_range_fraction` times the ship's effective weapon range (the reach of its weapons averaged by damage, `WeaponSystem.get_effective_range`), so a ship with long guns fights further out. `close_velocity` brakes for the range exactly (it comes to rest there without flying through it) and backs away when too close. **Evasion:** a ship that has been hit lately or is being targeted weaves sideways (`evasion` of `AiTuning.evade_speed`, changing side every 0.5 to 1.3 s): fighters hard, frigates a little, a capital ship not at all. The weave and strafe speeds are kept within the trim range so a weaving ship can still hold its nose on target. **Running** (`flee_velocity`) is directly away from the threats (nearer ones count for more), leaning toward the exit that is most directly away from them; when the ship is far enough out (`can_jump`) it jumps out (`NpcShip.begin_jump_out`). With no way out it just keeps running until it is safe.

**Pursuit leash.** A ship that runs from an equally fast one cannot be caught, so a pilot gives up when it has gone `AiTuning.pursuit_leash` (3,000 px) from where it began the fight: it ignores that target for `give_up_seconds` (30 s), stands down and goes back to what it was doing. (Without this a retreating ship in a system with no exit was chased, at the same top speed, out to 70,000 px.) The battle panel's ships know the four ways out of the system (`CombatSandbox.BATTLE_EXITS`), so a retreating ship jumps out as it would in the real game.

### Battle lines

Fleet fights used to scatter: every pilot chased its own target, so ships drifted across the system, left combat range, and a cruiser being pounded by fighters it could not hit (its medium guns pass through them) wandered off after targets across the field. Now cruisers and capital ships lead the line, advancing on the enemy's big ships, and fighters and frigates fight around them.

A doctrine has a `line_role` (`CombatDoctrine.LineRole`): `ANCHOR` (cruiser, capital ship), `SCREEN` (fighter, heavy fighter, gunboat and frigate) or `FREE` (the default). The role only applies to a ship with an armed friend (an ally with a doctrine, never the player) within `AiTuning.line_join_range` (3,500 px); a ship with none is `FREE` whatever its doctrine says, so duels and lone raiders fight as before. The role is worked out at every decision (`ShipPilot._update_line`, using `TacticalPicture.friends_near`, `nearest_anchor` and `centre_of`).

- **Anchor.** Picks its target **from anywhere in sight** (the scorer's threat, size and distance terms; there is no reach limit, so it cannot get stuck waiting for something to come into range, and cruisers, which cannot hurt nimble ships, choose big ones) and **advances on it** at `anchor_advance_speed` (0.5) of its top speed, so that its screen keeps up, until it is at its fighting range (`preferred_range_fraction` of its guns' average reach, which is the standoff steering of the doctrine). A target that moves away is followed again; one the commander named (`CombatOrder.target`) counts wherever it is, even beyond the ship's own sensor. With **nothing it can hurt** it does one of two things. If one of its own fighters (a friendly nimble ship) is fighting, and it has point defence, it goes into `SUPPORT`: it flies up, at the same advancing speed and with its nose toward it, to within `support_range_fraction` (0.7) of its point-defence range of **what that fighter is fighting** (the nearest such target), so that its point defence covers them (`ShipPilot._find_support`). Otherwise it holds where it is (`HOLD`). Its point defence (`docs/combat.md`, section 2) shoots the fighters meanwhile. (Before 3.3 step 5 an anchor took up a fixed place and crept forward after a delay, to a limit, only toward targets in reach of that place: it could give up for good just outside weapon range, even though its commander had named a target.)
- **Screen.** Stays near the nearest friendly anchor (one whose hull is above its retreat limit), or the centre of its friends when there is none. It picks no target further than `screen_radius` (1,600 px) from that point, and `CombatSteering.tether_velocity` bends its flight back toward the point as it nears and passes the edge (a soft band of `screen_soft_band` of the radius, then straight back at top speed). With nothing to shoot it holds within half the radius. The escort bonus in the target score still makes it go for whatever is attacking its anchor.
- A ship under an `ENGAGE` order is not tethered (the commander owns its leash: its role is `FREE`), and the target the commander named counts even if it is outside the screen radius. A `GUARD` order brings its own tether (section 7).
- Retreating and fleeing ships ignore the line. The `pursuit_leash` only applies to `FREE` ships with no order.
- **Sight.** A free ship only knows about hostile ships within its doctrine's sensor range (`sensor_range_factor` times its longest weapon reach: 2.5 for cruisers, 3 for capital ships and fighters). Ships under a commander are given targets from the commander's sight (`sight_radius`, `fleet_sight_radius`), which is wider.

The numbers are in `AiTuning` ("Battle line") and the role in each doctrine. A `ENGAGE` order from a commander replaces the screen role's tether; the "nearest anchor" and "centre of friends" queries still serve free ships and `GUARD` orders.

### Firing

`Combatant.fire_at_will()` (`WeaponSystem.fire_at_will`) fires only the ready weapons that would hit the target, with the same cooldowns, energy and shots as `fire()` (which the player still uses unchanged):

- a **fixed** gun when the nose is on the target's intercept point (within the doctrine's `fire_tolerance_degrees`, or the angle the target's own size covers at that range);
- a **turret** when the intercept point is inside its arc;
- never a weapon that would pass through the target (medium and heavy weapons against a nimble ship): a cruiser dead on a fighter fires nothing, a frigate fires only its light turrets;
- never beyond the weapon's reach.

`WeaponSystem.shots_fired` counts every shot (for tests and the balance harness to come).

### Out of play

The player's ship is out of play (`Combatant.set_out_of_play`) while docked or jumping: its hurtbox is off, so nothing can hit it, and the `TacticalPicture` leaves it out, so pilots do not see it. (`PlayerShip` sets it from `set_flight_enabled` and `begin_warp`.)

### Tuning

Shared numbers (thinking rate, calm time, battle line, trim range, weave and strafe speeds, dogfight timings) are in `resources/combat/ai/ai_tuning.tres` (`AiTuning`). What differs by kind of ship (style, range, rear attack, evasion, strafe, firing tolerance, when to run) is in the doctrine (section 5).

## 7. Unit commanders (step 4)

`UnitCommander` (`scripts/combat/ai/unit_commander.gd`) is a child node of every `Formation` (the formation makes it in `setup`; `formation.commander`). It is the brain of the unit: it reasons from the flagship, thinks once a second (`TacticalProfile.think_interval`) and gives each ship's pilot a `CombatOrder` (plain data, `combat_order.gd`). It never steers a ship, and pilots never decide what a group does. Its numbers are a `TacticalProfile` (`scripts/combat/ai/tactical_profile.gd`; one file for now, `resources/combat/ai/profiles/default.tres`; the named profiles come in step 6).

### States

The state is `Formation.State`, kept on the formation (`formation.state`, signal `state_changed`) so anything can read it.

| State | When | What the unit does |
|---|---|---|
| `FOLLOWING` | No hostile ship within `sight_radius` (4500 px) of the flagship | Flies its route in shape; every ship shoots what comes in reach from its slot (`FIRE_AT_WILL`) |
| `INTERCEPTING` | A hostile is in sight but farther than `engage_radius` (2500 px) from every ship | The leader flies at the nearest hostile (`MOVE`, at the formation's own speed and turn limits); the shape is chosen for the enemy (screen against mostly nimble craft, line against mostly tier 2+ ships, else wedge: the profile's `shape_*`); the rest keep their slots and fire at will |
| `ATTACKING` | A hostile is within `engage_radius`, and it stays so until the enemy is out of sight | The unit **breaks**: every armed ship gets an `ENGAGE` order and leaves its slot (state `ENGAGED`, the slot is remembered). Targets are shared out (below) |
| `DEFENDING` | A convoy with a hostile in sight | The freighters (and unarmed ships) fly on and fire at will. Each armed escort gets a `GUARD` order for the nearest freighter: it takes only targets within 1.5 x `guard_radius` (900 px) of a freighter and stays within `guard_radius` of it. With no such enemy it keeps its slot. A convoy never changes shape |
| `WITHDRAWING` | Not a convoy, and it has lost more than `withdraw_losses` (80%, the default profile's only rule) of its peak strength, with an armed enemy in sight. The profile can also set `max_odds` (the armed enemy in sight stronger than that multiple of the unit's strength: 0 = any odds) and `flagship_withdraw_hull` (0 = never); the default uses neither, so **a wounded leader fights on until it dies** and the next ship is promoted | The leader runs from the enemy (`WITHDRAW`, at the formation's limits, no weaving) for the way out and jumps, and the unit goes with it; the rest keep their slots. It stays withdrawing until nothing hostile is in sight |
| `HOLDING` | Reserved for the player's formation commands (step 9) | |

With no hostile in sight for `calm_seconds` (6 s) the unit goes back to `FOLLOWING`: orders are cleared, the pilots stand down, the ships fly back to their slots and the unit takes its own shape again. Strength is the sum of `CombatRating` of the unit's ships.

**Fighting to the death.** A ship under an `ENGAGE` or `GUARD` order does not run when its hull is low (its doctrine's `retreat_hull_fraction` is ignored): a leader that jumped out would take the whole unit with it. The unit stands or withdraws as one. A badly damaged member is not released from the formation while it is `ATTACKING` or `DEFENDING`: it fights on and is replaced by nobody. Once the unit is calm again, a member still below `FormationTuning.disabled_hull_fraction` is released (`REASON_DISABLED`) and acts as a free agent, which does retreat.

### Orders (`CombatOrder`)

| Kind | Who | Effect |
|---|---|---|
| `FIRE_AT_WILL` | Ships in their slots | The pilot picks the nearest hostile in weapon reach and fires what is aimed. It does not fly: the ship stays `IN_FORMATION` |
| `ENGAGE` | Armed ships in `ATTACKING` | The pilot takes control (`NpcShip.can_fight()` allows a formation member when its pilot `controls_ship()`) and fights like a free agent, with the commander's `target` as its focus (`TargetInfo.is_focus`, `weight_focus`). A target beyond the ship's own sensor range still counts: it is the commander's choice. No pursuit leash applies: the unit's sight radius is the leash |
| `GUARD` | Escorts in `DEFENDING` | `ENGAGE` tethered to a `protectee` within `radius`: the pilot's screen-role tether, with the order's radius |
| `MOVE` | The leader in `INTERCEPTING` | Flies to `point` (the nearest hostile), shooting what is in reach |
| `WITHDRAW` | The leader in `WITHDRAWING` | Runs from `point` (the middle of the armed enemy) for the exit and jumps |

`MOVE` and `WITHDRAW` keep the formation's speed, thrust and turn limits (`NpcShip._engaged` uses `effective_*` for them), so the members follow in shape. Orders are reissued every think; a ship that leaves the formation, or a leader that is replaced, has its order cleared.

### Sharing out the targets

In `ATTACKING` the commander walks its own armed ships strongest first. Each takes the best `TargetScorer` choice among the hostiles in sight (maximum distance `2 x sight_radius`), where the ships already given a target count as targeters, and at least `min_attackers` (2) are wanted on each enemy, so fighters work in pairs and the pile does not all go on one ship. The current target is kept unless a better one beats it by the doctrine's hysteresis. The pilot may still pick a better target of its own when its commanded one is gone. A ship that loses a target, or a unit that loses a ship (`member_lost`) or its leader (`leader_changed`), is re-ordered at once, not at the next think.

### Hierarchy

A ship that leads a squadron inside a battle group takes its orders from its squadron's commander. A commander orders only the ships that lead no unit of their own (a battle group's own cruisers and frigates). How the levels talk to each other is section 8.

The shared-out targets are made by `TargetAllocator` (`scripts/combat/ai/target_allocator.gd`, pure: it only returns orders), used by squadron, battle group and fleet commanders alike.

`Formation` keeps the state, and does not give up on ships that are off their slots while it is `ATTACKING` or `DEFENDING` (`is_in_action()`); neither does it release a badly damaged one (`REASON_DISABLED`) then; both checks resume when the unit is calm, and the clock on straying from the slots restarts when the state changes.

## 8. Battle groups and fleets (step 5)

### Roles: a battle group commands its squadrons

While a battle group is `ATTACKING`, its commander gives each of its squadrons a **role** (`UnitCommander.Role`):

| Role | The squadron | Its orders |
|---|---|---|
| `SCREEN` | Is `DEFENDING`: guards the battle group's own big ships (cruisers, frigates: `get_core_ships()`) | `GUARD` orders like a convoy's escorts: only enemies within 1.5 x `guard_radius` of a big ship are taken, those that are attacking the one the escort guards (`TacticalPicture.targeters_of`) counting most |
| `STRIKE` | Is `ATTACKING` | `ENGAGE` orders, with small craft preferred (`TargetAllocator.strike_bias`: tier 1 and under, fighters, heavy fighters and gunboats, in full, a frigate at half, bigger ships not at all) |

When the enemy has armed light (nimble) craft, the weakest `profile.screen_squadrons` (1) squadrons screen and the rest strike; against big ships only, all of them strike. Roles are taken back (`NONE`) when the battle group leaves `ATTACKING`, and then the squadrons keep their slots and fire at will. **A squadron inside a battle group makes no decisions of its own**: it does not close on, intercept or withdraw from the enemy by itself, so a battle group stays together (the battle group's own commander decides, and its leader's withdrawal takes the squadrons with it). A squadron on its own, or one whose battle group has dissolved, is a normal unit (section 7). The battle group's own big ships get `ENGAGE` orders and fight from the place they hold (the anchor behaviour, section 6).

### Fleet command: `FleetCommander`

`FleetCommander` (`scripts/combat/ai/fleet_commander.gd`) is a child of every `WarFleet` (`fleet.commander`). A fleet has no formation, so it has its own small state machine (`FleetCommander.State`) and an **objective** (`FleetCommander.Objective`), set with `set_objective(kind, point, target, radius)`, which is what the future war layer will call. It thinks once a second from the flagship and sees `profile.fleet_sight_radius` (6000 px).

| Objective | Hostile ships that are its business | While not fighting |
|---|---|---|
| `OFFENSIVE` (default) | All in sight. `target` (an enemy ship) names the enemy unit to be dealt with first | Flies its route |
| `DEFENSIVE` | Those within `radius` (default `sight_radius`) of `point` | The flagship is ordered (`MOVE`) to the point and holds it; the rest follow on the leash |
| `INTERCEPT` | Those within `engage_radius` of the flagship, which is when `target` has been caught | The flagship is ordered toward where the target will be (its position plus its velocity times the time to reach it); a target that is gone returns the fleet to `OFFENSIVE` |

| State | What it does |
|---|---|
| `FOLLOWING` | Battle groups get the directive `HOLD` (their commanders do not go out to meet the enemy; their ships fire at will from their places) and the capital ships fire at will |
| `ENGAGING` | **Matching:** the hostile ships are grouped into enemy units (a fleet, or the top formation, or a ship alone: `_unit_key`), strongest first, the named target's unit leading; battle groups, strongest first, are given the units in turn (round again if there are more groups) as their **focus**, a soft preference in target scoring (`weight_focus`), not a restriction. Groups are set `FREE` and run themselves. **Capital ships** (the flagship and the others on the leash that lead no formation) get `ENGAGE` orders, which with their doctrine means they hold their place and fight at long range behind the groups |
| `WITHDRAWING` | Battle groups get the directive `WITHDRAW` (their leaders run and jump, and their units go with them), the capital ships get `WITHDRAW` orders. It begins when the fleet has lost more than `withdraw_losses` (80%) of its peak strength with an armed enemy in sight, or `order_withdraw()` is called, and ends when nothing hostile is in sight (`calm_seconds` later the state is `FOLLOWING`) |

**The flagship**: `WarFleet` already replaces a lost flagship with the next capital ship (`flagship_changed`); the commander clears the old one's orders and carries on, and the fleet does not withdraw because its flagship fell or was hurt (the profile has no flagship rule for fleets). The leash (`WarFleet`, `docs/formations.md` section 4) is unchanged: units in a fight (`ENGAGED`) ignore it.

`UnitCommander.set_directive(Directive.FREE | HOLD | WITHDRAW, from)` and `set_focus(ships)` are what a fleet uses on its battle groups; they can be used by anything above a unit.

## 9. Tactical profiles (step 6)

A `TacticalProfile` (`scripts/combat/ai/tactical_profile.gd`, `resources/combat/ai/profiles/*.tres`) is the temperament of a unit's commander. Every `UnitCommander` and `FleetCommander` has one. **Which one** is decided in this order: the profile the spawner is given (`FleetSpawner.spawn_formation` / `spawn_plan`, `profile`, which also reaches every unit inside a fleet or battle group: a pirate fleet is pirates all through), else the one the unit's `FormationRecipe` names (`tactical_profile`: squadron, battle group and fleet use `military_patrol`, the convoy `convoy_escort`), else `default`. Pirates and mercenaries are not factions or recipes: they are ordinary units given the `pirate` or `mercenary` profile. `ContentRegistry.tactical_profile(id)` and `tactical_profiles()` list them. The sandbox's composed-unit panel has a profile choice; a battle preset side can name one (`"profile"`).

| Setting | What it does |
|---|---|
| `sight_radius`, `engage_radius`, `calm_seconds`, `fleet_sight_radius` | How far it sees, how close an enemy must come to start the fight, how long it stays alert (section 7, 8) |
| `proactive` | On: it goes for any hostile ship it sees. Off: it only takes notice of ships that have attacked it or something it guards (`Hostility.has_grudge`, which also counts a war enemy that fired on it) or that are targeting one of its ships, and then of the whole enemy force. Otherwise it flies its route and lets the enemy be (`TacticalProfile.filter_hostiles`, used by both commanders) |
| `max_odds` | The armed enemy in sight, stronger than this multiple of the unit's own strength (`CombatRating`), makes the unit withdraw at once (0: any odds). It replaces the old `withdraw_ratio` |
| `withdraw_losses`, `flagship_withdraw_hull` | When it withdraws in the middle of a fight: after losing this share of its peak strength (1.0 or more: never); `flagship_withdraw_hull` 0 means a wounded leader fights to the death |
| `pursuit_leash`, `give_up_seconds` | How far from where the fight began the unit chases (0: no limit, sight is the leash). Past it the enemy is ignored for `give_up_seconds`, the unit goes back to `FOLLOWING` at once and carries on with its route (`UnitCommander._chased_too_far`) |
| `target_bias_cargo` | Added to a cargo ship's score as a target (`TargetAllocator`) |
| `guard_radius`, `min_attackers`, `screen_squadrons`, `strike_bias`, `shape_*` | Escorting, pairing and roles, and shapes (sections 7, 8) |
| `default_objective` | A fleet's starting objective: offensive, or defensive (it holds where it first stood and fights what comes within `sight_radius` of that place) |

| Profile | proactive | max odds | losses to withdraw | leash | Other |
|---|---|---|---|---|---|
| `military_patrol` | yes | 2.0 | 80% | 3,500 px | The recipes' default |
| `military_attack` | yes | 4.0 | 90% | 9,000 px | Accepts worse odds, chases a long way, sees a fleet's enemies from 7,500 px |
| `convoy_escort` | yes | any | never | none | Escorts guard within 1,100 px of the freighters |
| `pirate` | yes | 1.0 | 40% | 6,000 px | `target_bias_cargo` 3: goes for freighters first |
| `mercenary` | no | 1.5 | 60% | 2,500 px | Retaliates only |
| `default` | yes | any | 80% | none | A unit given nothing else (and the tests) |

Ships under a commander still fight to the death (their doctrine's `retreat_hull_fraction` is ignored under an `ENGAGE` or `GUARD` order): units withdraw as units, by these numbers. Loose traffic ships have no profile yet (step 7).

## 10. Factions

`Faction.hostile_to_all` (a bool) marks a faction whose ships fight everyone: the Pirates (`faction_3`, `resources/factions/pirates.tres`), who have no ship models of their own and fly whatever ships they are given. The Hegemony (`faction_2`) and its six ships are described in [factions.md](factions.md); balancing it against the Federation is in `doctrine_balancing.md`.

## 11. What the player sees

The same questions, asked about the player, drive the navicomputer and one key. `CombatManager` answers them (the HUD and `TargetingManager` hold no rules; `Main` hands them the answers):

- `get_player_relation(targetable)` gives `CombatManager.Relation`: `ALLY` (a friend of the player, reputation Friendly or better), `HOSTILE` (`Hostility` says it will attack the player: pirates, a Hostile reputation, a grudge) or `NEUTRAL`. Anything that is not a ship is neutral.
- `get_player_attackers()` (and `get_player_attacker_targetables()`) lists the hostile ships that have chosen the player as their target, from `TacticalPicture.targeters_of`. The player's own selection of a ship is not an attack, and a neutral ship or an ally that targets the player is not an attacker. The list is as fresh as the picture's last look (at most 0.2 s old).

**Navicomputer** (`NavMap`, set up with `set_combat_view`): ship dots are **red** when hostile, **green** for allies and **blue** otherwise (`NavMap.ship_colour`); a ship that is targeting the player also has a **red ring** round its dot. Each ship blip carries `relation` and `attacking`. Without a combat view every ship is blue.

**V** (`target_attacker`) selects the closest of the ships that are targeting the player (`TargetingManager.select_closest_attacker`, measured from the player; ships that cannot be targeted, such as one that has jumped out, are skipped). With nobody attacking it does nothing and keeps the current selection. NPC pilots target the player when they are hostile to them (pirates, a Hostile reputation, a grudge), so the ring and V work in a real fight.

## 12. Sandbox tools

The combat sandbox (see [combat.md](combat.md) section 14) has a toolbar at the top left. **FORMATIONS (F2)** and **BATTLE (F3)** open and close the two dev panels (button or key). The panels share one place on the left of the screen, so opening one closes the other; both hide while the game is paused or docked. The buttons never hold the keyboard focus, so Space (which fires weapons) cannot press one again after a click. The **battle panel** spawns two sides facing each other ahead of the player: for each, a faction (or none), a ship model and a count. It says how many ships each side has left and whether the sides, and the player, are hostile and why. The ships fight as soon as they are spawned. A **preset** list (`CombatSandbox.BATTLE_PRESETS`: 1v1 fighters, 2v1, frigates, cruisers, capital ships, three fighters against a cruiser, two mixed fleets, a pirate against a freighter, two squadrons, a squadron against a cruiser, a convoy against pirates, two battle groups, two fleets of two capital ships and two battle groups; a side is one kind of ship, a mixed force listed from the front rank to the back, one unit under its commander: `"formation": {"shape", "ships", "kind"}`, or a whole battle group or fleet from a hand-written `"plan": {"recipe", "shape", "ships", "children"}` with a `"separation"` that keeps the big sides apart) spawns a whole battle at once. `CombatSandbox.spawn_battle`, `spawn_battle_preset`, `spawn_ship` (with optional exit bearings, so a retreating ship can jump out) and `clear_battle` do the work.

## 13. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/hostility_test.gd
& $godot --headless --path . --script res://scripts/tests/target_scorer_test.gd
& $godot --headless --path . --script res://scripts/tests/tactical_picture_test.gd
& $godot --headless --path . --script res://scripts/tests/combat_steering_test.gd
& $godot --headless --path . --script res://scripts/tests/pilot_duel_test.gd
& $godot --headless --path . --script res://scripts/tests/squadron_ai_test.gd
& $godot --headless --path . --script res://scripts/tests/fleet_ai_test.gd
& $godot --headless --path . --script res://scripts/tests/profile_test.gd
& $godot --headless --path . --script res://scripts/tests/player_awareness_test.gd
& $godot --headless --path . --script res://scripts/tests/sandbox_battle_test.gd
```

- `hostility_test.gd` (pure): war, pirates, the player's reputation at, above and below the threshold, grudges (starting, renewing, expiring, clearing), sides (the player's friends, lone ships), allies never hostile, bad rules.
- `target_scorer_test.gd` (pure): doctrines validate and are shared; cruisers and capital ships cannot choose fighters and pick big targets; fighters pick fighters; the protect bonus sends fighters after the fighters attacking their cruiser; distance, damage, focus, overkill, hysteresis and bias.
- `tactical_picture_test.gd` (real scene): every ship gets the rules, who is hostile to whom through the picture, pirates, who targets whom and who threatens whom, and a hit starting a grudge.
- `combat_steering_test.gd` (pure): lead points, whether the nose is on target, holding a range (a simulated ship arrives and stays without overshooting, also against a moving target), the tail, strafing, weaving, running and choosing an exit, the tuning and the doctrines' relative values.
- `pilot_duel_test.gd` (real scene, sped up, a minute or two; scenario names after `--`): the firing rules (aligned, in reach, cooldown, energy, a cruiser not wasting shots on a fighter, a frigate using only its light turrets), ships staying out of fights with nobody hostile, a Federation fighter against a Hegemony freighter, a pirate hunting a freighter that runs, two fighters beating one and standing down, a cruiser ignoring fighters and beating a frigate, three fighters beating a cruiser, a damaged ship running and jumping out (and running and standing down with no way out), a chaser giving up a chase it cannot win, formation members being left alone, two fleets fighting with the cruisers advancing and firing and nobody straying far from the middle (`battle_line`), two cruisers that start out of each other's weapon range with fighters between them closing and opening fire (`standoff`), and a cruiser with only enemy fighters to look at going into `SUPPORT`, moving up behind its own fighters and shooting with its point defence (`support`), and a pirate attacking the player (attacker list, V, and a docked or jumping player being out of play).
- `squadron_ai_test.gd` (real scene, sped up, about a minute; scenario names after `--`: basics, fight, losses, withdraw, convoy): a formation has a commander and follows with every ship told to fire at will; a squadron meets three fighters (INTERCEPTING in a screen, then ATTACKING with ENGAGE orders on at least two different targets, the ships leaving their slots), wins, goes back to FOLLOWING, re-forms in its own shape with nobody still ordered to fight; losing a ship and then the leader re-orders the survivors, none to a dead target; a squadron far outmatched withdraws (leader ordered to WITHDRAW, the rest in their slots, running from the enemy); a convoy goes to DEFENDING, its escorts get GUARD orders, the freighters never leave the convoy and it keeps its shape, then the unit goes back to FOLLOWING.
- `fleet_ai_test.gd` (real scene, sped up, under a minute; scenario names after `--`: roles, fleet, objectives, withdraw, flagship): a battle group's two squadrons become one screen and one strike force against light craft (the screen's ships guard the big ships, the strikers engage, the big ships engage), both strike against big ships only, and the roles are taken back after the fight; a fleet holds its battle groups while nothing is in sight, then engages, matches its two groups to two different enemy units (the strongest to the strongest), orders its capital ships to engage, and goes back to following; a defending fleet ignores an enemy outside its area, sends the flagship to the point and engages one inside it; an intercepting fleet flies at its target, engages once it is caught, and returns to the offensive when the target is gone; `order_withdraw()` sends battle groups and capital ships running; a lost flagship is replaced and the fleet neither withdraws nor stops fighting.
- `profile_test.gd` (real scene, sped up, under a minute; scenario names after `--`: files, spawn, proactive, odds, cargo, leash, fleet): the five profiles and `default` exist, are valid and differ, and the recipes name theirs; a profile given to the spawner (or a recipe's) reaches the commanders, a fleet's override its battle groups; a patrol goes for an enemy that does nothing while mercenaries in sight of it do not, until it targets one of them or fires once on them (a grudge); a patrol meeting a force three times its strength withdraws while an attack group meeting the same force fights; pirates target the freighter and a default unit the armed escort beside it; a unit with a short leash gives up a chase, ignoring the enemy; a defensive fleet starts out defending, and a mercenary fleet ignores an enemy a patrol fleet engages.
- `player_awareness_test.gd` (real scene, the full game): who is neutral, hostile or an ally to the player (at the reputation thresholds too), the colours on the navicomputer, the ring, who counts as an attacker, and V choosing the closest attacker.
- `sandbox_battle_test.gd` (real scene): the toolbar and F2 / F3, the panels hiding while paused, the battle builder, the battle panel and its presets.

## 14. Balance notes (first findings)

**Fighter loadouts.** A fighter has one mount with one light blaster (it had two); a heavy fighter and the Hegemony gunboat have two mounts (a light blaster and a pulse cannon). Nothing sells these ships, so no save can hold them and the mount counts could change freely. Measured in the sandbox with the AI, 3 Federation fighters against a Hegemony cruiser that cannot hurt them (3 runs each, `Engine.time_scale` 6; the cruiser retreats at 15% hull, so sometimes it jumps out instead of dying):

| Fighter loadout | Time to kill the cruiser | 1v1 fighters decisive | 2v1 decisive (first kill) |
|---|---|---|---|
| 2 blasters, damage 8 (before) | 23 s | 0 of 3 | 3 of 3 (10 s) |
| 1 blaster, damage 8 (now) | 44 s | 1 of 3 | 2 of 3 (18 s) |
| 2 blasters, damage 5 | 34 s | 0 of 3 | 2 of 3 (17 s) |
| 1 blaster, damage 12 | 30 s | 1 of 3 | 2 of 3 (15 s) |

Dropping a mount nearly doubles the time to kill and touches only fighters; lowering the blaster's damage also changes every other ship that carries one (frigates, heavy fighters, the shuttle, the player's first ship). Equal fighters rarely finish each other (they retreat at 25% hull, and the survivor of a 2v1 may run rather than die), which is the retreat setting and will vary by tactical profile (step 6).

**Hitboxes.** A ship's hitbox is 40% of its sprite size unless the model sets `hit_radius`. The Hegemony sprites are bulkier, so with the same stats the Hegemony capital ship was about 10% easier to hit and won no capital ship duel (the Federation won 3 of 3). The Hegemony ships now set `hit_radius` to match the Federation ship of the same class (`ship_class_test` checks it), and the duel splits 3 and 3 over 6 runs. A pair of ships that are meant to be equal must have the same hit radius.

**Heavy fighter targeting.** With one light blaster in two, a heavy fighter can hurt a fighter with only 38% of its firepower, so it scored an enemy fighter no higher than a capital ship. Its size-affinity weight is 1.5 (was 1.0) so it still prefers light craft and frigates.
