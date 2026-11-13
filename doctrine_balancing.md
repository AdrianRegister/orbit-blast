# Faction doctrine balancing (proposal, for reference)

Agreed during Phase 3.3 planning (2026-11-13). Nothing here is built yet, apart from what the steps below say.

## Starting point (Phase 3.3 step 1)

The Hegemony ships copy the numbers, mounts and loadouts of the matching Federation ship. The Hegemony gunboat is new (the Federation has none). Its numbers sit between the heavy fighter and the frigate. The two factions differ only in looks until we decide to give them distinct doctrines.

## How to balance distinct doctrines later

Use three tools together. A doctrine change is then: edit one stats file, run the report, run the matrix.

### 1. A rating budget

Matching classes across factions keep their `CombatRating.of(model)` within ±5% of each other (Federation cruiser against Hegemony cruiser, and so on). A test enforces it.

Doctrines then **trade within the budget** instead of adding to it. More armour costs speed or guns; longer range costs damage per second. Balancing becomes "same budget, different shape", instead of tuning every ship against every other ship.

### 2. An analytic balance report (`tools/balance_report.gd`)

Pure maths on the static data, run in seconds. For every pair of ship models it prints:

- the damage per second that actually lands, counting evasion (`evades_heavy_fire`) and the shield and armour multipliers through `DamageModel`;
- the time to kill, each way;
- the rating per credit.

It catches a number that is out of line before anyone flies it.

### 3. A simulated duel matrix (`scripts/tests/support/battle_harness.gd`, Phase 3.3 step 8)

Runs the real NPC combat AI headless, at a raised time scale, for N random seeds:

- 1v1 for every class pair;
- squadron against squadron.

It reports win rates and time to kill. The targets:

- **Matching classes** across factions: 45 to 55% wins.
- **Planned counters** (for example, fighters beating an unescorted cruiser): large swings, but only the intended ones.

This is the step that catches imbalance the maths cannot see: turning circles, evasion, how the AI uses a ship.

## Suggested doctrine directions (only ideas)

- **Federation:** faster, more turrets, medium range. Works through mobility and formation fire.
- **Hegemony:** heavier armour, slower, fewer but heavier fixed guns. Works through staying power at long range.

Both stay inside the rating budget for each class.
