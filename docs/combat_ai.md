# NPC combat AI (Phase 3.3)

How NPC ships decide who to fight and how to fight them. Built in steps; this document grows with each. Read it, [combat.md](combat.md), [formations.md](formations.md) and [wars_system.md](../wars_system.md) before changing anything here.

**Built so far:** hostility and awareness (step 2): who is hostile to whom, what a ship can see, how it ranks targets, the doctrines that tune that, and the sandbox's toolbar and battle builder; and what the player is told about it (the navicomputer's colours and **V**, section 8); and pilots (step 3, section 6): ships that fight, run and jump out. Not built yet: squadron and convoy commanders (4), battle group and fleet command (5), tactical profiles (6), patrols and convoys as traffic (7), the full battle builder and balancing harness (8), the player's formation selector (9). The plan is in `C:\Users\Adrian\.claude\plans\` and the order of work in the roadmap (`phase_3_roadmap.md`).

## 1. Architecture

Three layers, with orders going down and reports coming up, so one ship's behaviour never depends on group logic:

```
Command layer   FleetCommander (WarFleet) -> UnitCommander (each Formation)   [steps 4-5]
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

**It only acts for a ship on its own** (`NpcShip.is_free_agent()`: in no formation or fleet), and only while the ship is flying about (`can_fight()`: not docked, jumping in or out, or in a formation slot). Members of formations and fleets wait for their commanders (steps 4 and 5): they hold their slots and do not fight yet.

### Modes

| Mode | When | What it does |
|---|---|---|
| `IDLE` | Nothing to fight | The ship flies its route (the pilot is not in control) |
| `ATTACK` | A hostile it can hurt is in sight (the doctrine's sensor range) | Picks the best target (`TargetScorer`, section 4), flies at it in the doctrine's style, weaves when it is under attack, fires what would hit |
| `RETREAT` | Its hull is below the doctrine's `retreat_hull_fraction` and an enemy is in sight | Runs, still firing what it can at its target, until it has seen no enemy for `calm_time`; jumps out of the system if there is a way out |
| `FLEE` | A ship with no doctrine (a freighter) and an armed enemy within `flee_alarm_range` | The same, never firing |
| `HOLD` | In a battle line (see below), an enemy in sight, nothing it can shoot from its place | Keeps its place (an anchor) or stays near its anchor (a screen ship), nose toward the enemy |

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

Fleet fights used to scatter: every pilot chased its own target, so ships drifted across the system, left combat range, and a cruiser being pounded by fighters it could not hit (its medium guns pass through them) wandered off after targets across the field. Now cruisers and capital ships anchor the line and fighters and frigates fight around them.

A doctrine has a `line_role` (`CombatDoctrine.LineRole`): `ANCHOR` (cruiser, capital ship), `SCREEN` (fighter, heavy fighter, gunboat and frigate) or `FREE` (the default). The role only applies to a ship with an armed friend (an ally with a doctrine, never the player) within `AiTuning.line_join_range` (3,500 px); a ship with none is `FREE` whatever its doctrine says, so duels and lone raiders fight as before. The role is worked out at every decision (`ShipPilot._update_line`, using `TacticalPicture.friends_near`, `nearest_anchor` and `centre_of`).

- **Anchor.** Advances on the enemy as a free ship would until something it can shoot is in reach (its longest weapon reach times `anchor_reach_margin`, 1.1), or until it is attacked. It then takes its place **at that point, which never moves** while it holds it: it turns, fires and shoots only what is within reach of that point. It does not leave to chase, and it holds (`HOLD`) when nothing is in reach. If it has had nothing in reach for `anchor_advance_delay` (4 s), even while fighters it cannot hit are attacking it, it **creeps**: its place moves toward the best target it can hurt (chosen without the reach limit, so the scorer's liking for big ships makes it the enemy anchor) at `anchor_advance_speed` (0.3) of its top speed, so its screen keeps up. It takes up a new place when the target is in reach, or stops and holds when the place is `anchor_advance_limit` (1,500 px) from where the line first formed. So two lines that start out of range of each other still meet, and a cruiser pounded by fighters goes for the enemy cruiser instead of sitting still. Its point defence (`docs/combat.md`, section 2) shoots the fighters meanwhile.
- **Screen.** Stays near the nearest friendly anchor (one whose hull is above its retreat limit), or the centre of its friends when there is none. It picks no target further than `screen_radius` (1,600 px) from that point, and `CombatSteering.tether_velocity` bends its flight back toward the point as it nears and passes the edge (a soft band of `screen_soft_band` of the radius, then straight back at top speed). With nothing to shoot it holds within half the radius. The escort bonus in the target score still makes it go for whatever is attacking its anchor.
- Retreating and fleeing ships ignore the line. The `pursuit_leash` only applies to `FREE` ships.

The numbers are in `AiTuning` ("Battle line") and the role in each doctrine. Step 5 (battle group and fleet command) should replace the "nearest anchor" and "centre of friends" queries with the fleet commander's explicit line.

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

## 7. Factions

`Faction.hostile_to_all` (a bool) marks a faction whose ships fight everyone: the Pirates (`faction_3`, `resources/factions/pirates.tres`), who have no ship models of their own and fly whatever ships they are given. The Hegemony (`faction_2`) and its six ships are described in [factions.md](factions.md); balancing it against the Federation is in `doctrine_balancing.md`.

## 8. What the player sees

The same questions, asked about the player, drive the navicomputer and one key. `CombatManager` answers them (the HUD and `TargetingManager` hold no rules; `Main` hands them the answers):

- `get_player_relation(targetable)` gives `CombatManager.Relation`: `ALLY` (a friend of the player, reputation Friendly or better), `HOSTILE` (`Hostility` says it will attack the player: pirates, a Hostile reputation, a grudge) or `NEUTRAL`. Anything that is not a ship is neutral.
- `get_player_attackers()` (and `get_player_attacker_targetables()`) lists the hostile ships that have chosen the player as their target, from `TacticalPicture.targeters_of`. The player's own selection of a ship is not an attack, and a neutral ship or an ally that targets the player is not an attacker. The list is as fresh as the picture's last look (at most 0.2 s old).

**Navicomputer** (`NavMap`, set up with `set_combat_view`): ship dots are **red** when hostile, **green** for allies and **blue** otherwise (`NavMap.ship_colour`); a ship that is targeting the player also has a **red ring** round its dot. Each ship blip carries `relation` and `attacking`. Without a combat view every ship is blue.

**V** (`target_attacker`) selects the closest of the ships that are targeting the player (`TargetingManager.select_closest_attacker`, measured from the player; ships that cannot be targeted, such as one that has jumped out, are skipped). With nobody attacking it does nothing and keeps the current selection. NPC pilots target the player when they are hostile to them (pirates, a Hostile reputation, a grudge), so the ring and V work in a real fight.

## 9. Sandbox tools

The combat sandbox (see [combat.md](combat.md) section 14) has a toolbar at the top left. **FORMATIONS (F2)** and **BATTLE (F3)** open and close the two dev panels (button or key); both hide while the game is paused or docked. The **battle panel** spawns two sides facing each other ahead of the player: for each, a faction (or none), a ship model and a count. It says how many ships each side has left and whether the sides, and the player, are hostile and why. The ships fight as soon as they are spawned. A **preset** list (`CombatSandbox.BATTLE_PRESETS`: 1v1 fighters, 2v1, frigates, cruisers, capital ships, three fighters against a cruiser, two mixed fleets, a pirate against a freighter; a side is one kind of ship, or a mixed force listed from the front rank to the back) spawns a whole battle at once. `CombatSandbox.spawn_battle`, `spawn_battle_preset`, `spawn_ship` (with optional exit bearings, so a retreating ship can jump out) and `clear_battle` do the work.

## 10. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/hostility_test.gd
& $godot --headless --path . --script res://scripts/tests/target_scorer_test.gd
& $godot --headless --path . --script res://scripts/tests/tactical_picture_test.gd
& $godot --headless --path . --script res://scripts/tests/combat_steering_test.gd
& $godot --headless --path . --script res://scripts/tests/pilot_duel_test.gd
& $godot --headless --path . --script res://scripts/tests/player_awareness_test.gd
& $godot --headless --path . --script res://scripts/tests/sandbox_battle_test.gd
```

- `hostility_test.gd` (pure): war, pirates, the player's reputation at, above and below the threshold, grudges (starting, renewing, expiring, clearing), sides (the player's friends, lone ships), allies never hostile, bad rules.
- `target_scorer_test.gd` (pure): doctrines validate and are shared; cruisers and capital ships cannot choose fighters and pick big targets; fighters pick fighters; the protect bonus sends fighters after the fighters attacking their cruiser; distance, damage, focus, overkill, hysteresis and bias.
- `tactical_picture_test.gd` (real scene): every ship gets the rules, who is hostile to whom through the picture, pirates, who targets whom and who threatens whom, and a hit starting a grudge.
- `combat_steering_test.gd` (pure): lead points, whether the nose is on target, holding a range (a simulated ship arrives and stays without overshooting, also against a moving target), the tail, strafing, weaving, running and choosing an exit, the tuning and the doctrines' relative values.
- `pilot_duel_test.gd` (real scene, sped up, a minute or two; scenario names after `--`): the firing rules (aligned, in reach, cooldown, energy, a cruiser not wasting shots on a fighter, a frigate using only its light turrets), ships staying out of fights with nobody hostile, a Federation fighter against a Hegemony freighter, a pirate hunting a freighter that runs, two fighters beating one and standing down, a cruiser ignoring fighters and beating a frigate, three fighters beating a cruiser, a damaged ship running and jumping out (and running and standing down with no way out), a chaser giving up a chase it cannot win, formation members being left alone, two fleets fighting with the cruisers holding their lines and nobody straying far from the middle (`battle_line`), and a pirate attacking the player (attacker list, V, and a docked or jumping player being out of play).
- `player_awareness_test.gd` (real scene, the full game): who is neutral, hostile or an ally to the player (at the reputation thresholds too), the colours on the navicomputer, the ring, who counts as an attacker, and V choosing the closest attacker.
- `sandbox_battle_test.gd` (real scene): the toolbar and F2 / F3, the panels hiding while paused, the battle builder, the battle panel and its presets.

## 11. Balance notes (first findings)

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
