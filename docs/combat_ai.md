# NPC combat AI (Phase 3.3)

How NPC ships decide who to fight and how to fight them. Built in steps; this document grows with each. Read it, [combat.md](combat.md), [formations.md](formations.md) and [wars_system.md](../wars_system.md) before changing anything here.

**Built so far:** hostility and awareness (step 2): who is hostile to whom, what a ship can see, how it ranks targets, the doctrines that tune that, and the sandbox's toolbar and battle builder; and what the player is told about it (the navicomputer's colours and **V**, section 7). Not built yet: pilots that fly and fire (3), squadron and convoy commanders (4), battle group and fleet command (5), tactical profiles (6), patrols and convoys as traffic (7), the full battle builder and balancing harness (8), the player's formation selector (9). The plan is in `C:\Users\Adrian\.claude\plans\` and the order of work in the roadmap (`phase_3_roadmap.md`).

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

**Grudges are between sides.** A side is a faction, the player (`Hostility.PLAYER_SIDE`), or a ship that belongs to nobody (itself). The player's allies (reputation Friendly or better) count as on the player's side too, so they take up the player's quarrels. `CombatManager` records a grudge on every hit (`Hostility.record_attack`); allies never start one. Repeated attacks renew it. Grudges are timed in game time (`CombatManager`'s clock, which stops while paused), end when the system changes (`set_system` clears them) and are **not saved**.

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

A `CombatDoctrine` (`resources/combat/ai/doctrines/`) is how a kind of ship fights, as data: sensor range, preferred target sizes and the target-choice weights above. A ship class names its doctrine (`ShipClass.doctrine`, inherited through `parent`, `get_doctrine()`); ships that never fight (freighters, shuttles) have none. Doctrines are shared by classes:

| Doctrine | Classes | Meant for |
|---|---|---|
| `fighter` | fighter, interceptor | Light craft (tier 0 to 1) |
| `heavy_fighter` | heavy fighter | Tier 0 to 2 |
| `light_warship` | gunboat, frigate, light frigate | Tier 1 to 2 |
| `cruiser` | cruiser | Tier 2 to 4 |
| `capital_ship` | capital ship | Tier 3 to 4 |

Later steps add how a ship flies (preferred range, evasion, retreat) to the same file. A new ship of an existing class needs nothing; a new class names one of these or a new file.

## 6. Factions

`Faction.hostile_to_all` (a bool) marks a faction whose ships fight everyone: the Pirates (`faction_3`, `resources/factions/pirates.tres`), who have no ship models of their own and fly whatever ships they are given. The Hegemony (`faction_2`) and its six ships are described in [factions.md](factions.md); balancing it against the Federation is in `doctrine_balancing.md`.

## 7. What the player sees

The same questions, asked about the player, drive the navicomputer and one key. `CombatManager` answers them (the HUD and `TargetingManager` hold no rules; `Main` hands them the answers):

- `get_player_relation(targetable)` gives `CombatManager.Relation`: `ALLY` (a friend of the player, reputation Friendly or better), `HOSTILE` (`Hostility` says it will attack the player: pirates, a Hostile reputation, a grudge) or `NEUTRAL`. Anything that is not a ship is neutral.
- `get_player_attackers()` (and `get_player_attacker_targetables()`) lists the hostile ships that have chosen the player as their target, from `TacticalPicture.targeters_of`. The player's own selection of a ship is not an attack, and a neutral ship or an ally that targets the player is not an attacker. The list is as fresh as the picture's last look (at most 0.2 s old).

**Navicomputer** (`NavMap`, set up with `set_combat_view`): ship dots are **red** when hostile, **green** for allies and **blue** otherwise (`NavMap.ship_colour`); a ship that is targeting the player also has a **red ring** round its dot. Each ship blip carries `relation` and `attacking`. Without a combat view every ship is blue.

**V** (`target_attacker`) selects the closest of the ships that are targeting the player (`TargetingManager.select_closest_attacker`, measured from the player; ships that cannot be targeted, such as one that has jumped out, are skipped). With nobody attacking it does nothing and keeps the current selection. Until pilots exist (step 3) nothing targets the player by itself, so in the sandbox a ship must be told to (`Combatant.set_target`).

## 8. Sandbox tools

The combat sandbox (see [combat.md](combat.md) section 14) has a toolbar at the top left. **FORMATIONS (F2)** and **BATTLE (F3)** open and close the two dev panels (button or key); both hide while the game is paused or docked. The **battle panel** spawns two sides facing each other ahead of the player: for each, a faction (or none), a ship model and a count. It says how many ships each side has left and whether the sides, and the player, are hostile and why. Until pilots exist (step 3) the ships only drift. `CombatSandbox.spawn_battle`, `spawn_ship` and `clear_battle` do the work.

## 9. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/hostility_test.gd
& $godot --headless --path . --script res://scripts/tests/target_scorer_test.gd
& $godot --headless --path . --script res://scripts/tests/tactical_picture_test.gd
& $godot --headless --path . --script res://scripts/tests/player_awareness_test.gd
& $godot --headless --path . --script res://scripts/tests/sandbox_battle_test.gd
```

- `hostility_test.gd` (pure): war, pirates, the player's reputation at, above and below the threshold, grudges (starting, renewing, expiring, clearing), sides (the player's friends, lone ships), allies never hostile, bad rules.
- `target_scorer_test.gd` (pure): doctrines validate and are shared; cruisers and capital ships cannot choose fighters and pick big targets; fighters pick fighters; the protect bonus sends fighters after the fighters attacking their cruiser; distance, damage, focus, overkill, hysteresis and bias.
- `tactical_picture_test.gd` (real scene): every ship gets the rules, who is hostile to whom through the picture, pirates, who targets whom and who threatens whom, and a hit starting a grudge.
- `player_awareness_test.gd` (real scene, the full game): who is neutral, hostile or an ally to the player (at the reputation thresholds too), the colours on the navicomputer, the ring, who counts as an attacker, and V choosing the closest attacker.
- `sandbox_battle_test.gd` (real scene): the toolbar and F2 / F3, the panels hiding while paused, the battle builder, and the battle panel.
