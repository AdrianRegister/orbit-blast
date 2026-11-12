# Formations and fleet organisation (Phase 3.2)

How ships are organised into squadrons, battle groups, fleets and convoys, and how formation shapes work. Built in steps; this document grows with each. Read it, [combat.md](combat.md) and [wars_system.md](../wars_system.md) before changing anything here.

**Built so far:** ship classes and the combat rating (step 1), formation shapes and slot assignment (step 2), the runtime formation and its movement (step 3). Not built yet: composition rules and fleets (step 4), tactical effects (step 5), traffic integration (step 6), the rest of the sandbox panel and polish (step 7). The formation states (following, holding, intercepting, attacking, defending, withdrawing) and the player's formation selector are deliberately left for Phase 3.3.

---

## 1. Ship classes (step 1)

Every ship model names a `ShipClass` resource (`resources/ship_classes/`): fighter, heavy fighter, gunboat, corvette, light frigate, frigate, cruiser, capital ship, interceptor, shuttle, freighter, bulk freighter, plus the abstract parents `warship` and `cargo_ship`. Classes are data, not subclasses: a new class, or a new ship of an existing class, is a new `.tres`. `is_a()` follows the `parent` chain, so a rule can say "any cargo ship". See [ships-and-upgrades.md](ships-and-upgrades.md) section 12c.

`CombatRating.of(model)` ranks ships: the geometric mean of staying power and firepower. "The strongest ship" in a formation means the highest rating.

---

## 2. Formation shapes (step 2)

A **shape** (`FormationShape`, one `.tres` per shape in `resources/formations/shapes/`) is a pattern ships hold around their leader. It is data and maths only; movement does not know which shape is in use, so a new shape is usually a new file.

| Piece | File | Role |
|---|---|---|
| `FormationShape` | `scripts/fleet/formation_shape.gd` | The layout kind, its numbers (spacing, angle, ring radii) and the seating plan (`zone_rules`) |
| `FormationZoneRule` | `scripts/fleet/formation_zone_rule.gd` | One line of the seating plan: which ships fill a zone (strongest, lightest, cargo, non-cargo, any) |
| `FormationSlot` | `scripts/fleet/formation_slot.gd` | One place: an offset from the leader and a zone |
| `FormationGeometry` | `scripts/fleet/formation_geometry.gd` | Pure maths: the slots for a shape and a number of ships, the spacing for big ships |
| `SlotCandidate` | `scripts/fleet/slot_candidate.gd` | A member as plain data (rating, size tier, cargo, footprint) |
| `SlotAssigner` | `scripts/fleet/slot_assigner.gd` | Pure maths: who holds which slot |
| `FormationTuning` | `scripts/fleet/formation_tuning.gd`, `resources/formations/formation_tuning.tres` | Shared tunable numbers |

**Frame.** Offsets are in the leader's frame: +x straight ahead, +y to the right. A slot's world position is `leader position + offset.rotated(leader heading)`. Slot 0 is always the leader's own place at the origin.

**Zones.** LEAD, FRONT, FLANK, CORE (protected), REAR, SCREEN (a forward picket line), END (the ends of a line). A zone is what a place is; later each zone can carry its own tactical bonuses (step 5).

### The shapes

| Shape | Layout | Leader | Seating plan |
|---|---|---|---|
| `wedge` | A V; ranks of two behind the tip; `angle_degrees` sets how wide | The tip, the strongest ship | Strong ships on the inner ranks, the weakest at the rear rank |
| `line` | Ships abreast, alternating left and right (`mirror`); `angle_degrees` 0 with `mirror` off is a column, 45 an echelon | The middle | Strong ships inside, the weakest at the ends |
| `diamond` | A lattice of rows 1, 2, 3, 2, 1 (then 1 to 4 and back): four ships are a clean diamond, a fifth fills the middle | The front tip | Strong ships on the flanks and the rear, the weakest in the core |
| `screen` | A tight block holding the leader and a picket line `screen_depth_factor` spacings ahead | In the block | Lightest ships are the pickets, the rest stay behind them |
| `convoy` | The leader in the middle, an inner ring, a wider outer ring (the escorts); rings widen until their ships fit | The middle (a freighter) | Freighters in the inner ring, the strongest escorts at the front and rear |
| `convoy_diamond` | A diamond with the leader in the middle (`lead_at_core`) | The middle (a freighter) | Freighters in the sheltered core, escorts on the tip, flanks and rear |

Odd-sized wedges, lines and diamonds are symmetrical. The slot list is in fill order, the most valuable places first.

### Spacing

`FormationGeometry.compute_spacing` returns the shape's own spacing, or `spacing_gap_factor` (1.3) times the two largest members' radii when that is more, so a capital ship never overlaps its neighbours. A sub-unit (a squadron inside a battle group) will use its whole extent (`FormationGeometry.extent` plus its ship's radius) as its footprint.

### Seating

`SlotAssigner.assign` seats the leader in slot 0, then follows the shape's `zone_rules` in order, taking the best candidate for each slot of the zone (by the rule's filter), then fills any places left with whoever is left. It is deterministic. Ships that rate the same keep the order they were given, or the places they held before (`previous`), so ranks close up when a ship is lost instead of shuffling.

---

## 3. Runtime and movement (step 3)

| Piece | File | Role |
|---|---|---|
| `Formation` | `scripts/fleet/formation.gd` | A group of NPC ships around a leader. A node under the star system's new `Formations` node (kept apart from `Ships`, whose children are all treated as ships); freed with the system |
| `FormationSteering` | `scripts/fleet/formation_steering.gd` | Pure maths: the leader's speed, turn and thrust limits, the velocity a member wants, trim thrust, separation and obstacle avoidance |
| `FleetSpawner` | `scripts/fleet/fleet_spawner.gd` | Builds a formation of ships into a system (the leader is the strongest ship; a convoy is led by its strongest freighter) |
| `NpcShip` (changes) | `scripts/ships/npc_ship.gd` | State `IN_FORMATION`; `formation` (the one it follows) and `led_formation` (the one it leads); the leader's limits |
| `SandboxPanel` | `scripts/dev/sandbox_panel.gd` | Dev panel in the combat sandbox (spawn formations, change shape, kill a leader or member) |
| Tunables | `resources/formations/formation_tuning.tres` | Every number below |

A formation has a `kind` (SQUADRON, BATTLE_GROUP, CONVOY), a `shape`, a `lead` and its ships. The **lead** follows a route; the others hold station. For a squadron or battle group the lead is also the **flagship** (the strongest ship, `get_flagship()`); for a convoy the lead is the strongest freighter (the middle of the shape) and the flagship is the strongest escort. The flagship is only recorded here: deciding things comes with the NPC combat AI.

### What a formation does each frame

It runs before its ships. It orients itself, works out each slot's world position from the leader, keeps the leader's limits up to date, and releases members that are wrecked or lost.

- **Orientation.** The slots are laid out along the leader's **direction of travel** once it moves faster than `travel_heading_speed` (blended in over `travel_heading_blend`), and along its nose when it is slow or stopped. A leader's nose swings ahead of its path, so following the path keeps the slots turning smoothly.
- **Slot velocity.** A slot is moving: the leader's velocity plus the swing of the slot as the formation turns (`FormationSteering.slot_velocity`). Members fly to match it, plus a correction in proportion to their distance from the slot (`slot_gain`). Matching the slot's velocity, not just its position, is what keeps a member on a turning formation from lagging behind it.
- **Members** (`NpcShip._follow`) use the normal ship physics where they can. A **small velocity correction** (up to `trim_range`) is made with **station-keeping trim thrusters**: `trim_thrust_fraction` of the ship's thrust, in any direction, while the nose follows the formation's heading. A ship with forward-only engines can only brake by turning round, and the slots on the inside of every turn move slower than the leader, so without trim thrusters members flip over at every turn. A **big correction** uses the main engines: turn toward it, thrust when facing it. A member more than `catch_up_factor` spacings away flies straight at its slot at top speed. (Set `trim_thrust_fraction` to 0 to turn trim thrusters off.)
- **On station** means within `station_tolerance_factor` of the spacing (at least `station_tolerance_min` px) of the slot.

### Limits on the leader

So every member can keep up, the leader is limited (`NpcShip.formation_*_cap`, set by the formation):

- **Speed:** `speed_margin` (90%) of the slowest member's top speed.
- **Acceleration:** `thrust_margin` (80%) of the weakest member's thrust.
- **Turn rate:** the fastest at which every member can still swing with it. For a member `d` px out, with the leader at speed `v` and turning at `w`: it needs `w x d` of spare speed, sideways acceleration `(v + w x d) x w` within `turn_accel_fraction` of its thrust, and must itself be able to turn at `w`. The cap follows the leader's current speed (a slow leader turns more tightly) and never drops below `min_turn_cap`.
- **Turn acceleration:** the leader's turn rate also changes gradually (and slows in time to stop on target, with no overshoot), at a rate the outermost member's engines allow.

A big formation therefore turns slowly and a tight one turns sharply, whatever shape it is.

### Losses and recovery

| Event | Result |
|---|---|
| A member is **destroyed** | Removed (`member_lost`, reason `destroyed`); the slots are rebuilt for the new size and ranks close up (equal ships keep their order) |
| The **leader is destroyed** | The strongest remaining ship (for a convoy, the strongest remaining freighter) takes over and **continues the old leader's journey** (`NpcShip.take_over_route_from`: destination, visits, exit, wander or patrol); `leader_changed` is emitted |
| A member drops below `disabled_hull_fraction` of its hull | Released (`disabled`): it leaves the formation and carries on alone (there is no engine damage yet, so "disabled" means heavily damaged) |
| A member stays beyond `lost_distance` for `lost_time` | Released (`separated`) |
| Fewer ships than the shape's `min_members` remain | The formation **dissolves**: everyone carries on alone, `dissolved` is emitted |
| A member **falls behind** | It catches up (above); it is only released if it stays lost |
| The leader **jumps in or out** | Nothing can fly at 3,000 to 9,000 px/s, so while the leader is `ARRIVING` or `WARPING` members are **locked to their slots** (and stop being targetable as they warp). They are released onto their slots when the leader returns to normal flight; when the leader warps out the whole formation leaves with it |
| The shape changes (`set_shape`) | Slots are rebuilt; members fly to their new slots with the normal physics, so re-forming is smooth (`shape_changed`) |

A released ship resumes ordinary behaviour (`NpcShip.leave_formation`): it picks a destination, or leaves the system, or wanders if it has nowhere to go.

### Collision avoidance

`Formation.get_avoidance(ship)` gives a push (a velocity) away from other ships (including the player) inside `(radius + radius) x (1 + separation_margin)`, and from planets and stations inside their radius plus `obstacle_margin` (except the place the leader is heading for, so a formation can gather at a dock). Members get it in `_follow`; the leader gets it when it flies. Ordinary traffic is untouched.

### NPC ship changes

- `NpcShip.State.IN_FORMATION`. Members never dock or jump by themselves.
- A **formation leader** steers differently when wandering or patrolling: it cruises (nose toward the waypoint at a steady speed) instead of braking and turning back on itself, because a formation behind it cannot follow a ship that reverses on the spot. It starts each leg early enough to round the corner.
- `begin_wandering` now picks each next point ahead of the ship (within about 80 degrees, at least 300 px away) instead of anywhere in the circle. `begin_patrol(points)` flies a fixed loop of points, for repeatable tests and demos.
- `effective_max_speed()`, `effective_turn_rate()`, `effective_thrust()` replace reading the stats directly in the flight code; with no formation they equal the stats, so ordinary traffic flies exactly as before.

### Sandbox panel

In the combat sandbox (see [combat.md](combat.md) section 14) a panel on the left spawns a formation ahead of the player (a preset such as a squadron, battle group or convoy, or any ship times a count), in a chosen shape. It shows the targeted ship's formation (kind, shape, size, how many are on station, the leader, cruise speed and turn limit), applies a shape to it, kills its leader or a member (to see promotion and closing ranks), and clears all formations. Presets are `CombatSandbox.GROUP_PRESETS`.

---

## 4. Recipes

**Add a shape.** Copy a file in `resources/formations/shapes/`, give it a unique `id`, choose a layout and numbers, and write its seating plan. For example a column is `layout = LINE`, `angle_degrees = 0`, `mirror = false`. Shapes are found by `ContentRegistry.formation_shape(id)` / `formation_shapes()`.

**Tune spacing, tolerance, limits or avoidance.** Edit `resources/formations/formation_tuning.tres` (shared) or the shape's `spacing`. The tuning groups: slots (spacing), station keeping (tolerance, gain, trim thrusters), orientation, the leader's limits, recovery (catch-up, lost distance and time, the disabled hull fraction) and collision avoidance. Every field has a comment in `formation_tuning.gd`.

**Try a formation by hand.** Main menu, DEV COMBAT SANDBOX, then use the panel. To add a preset group, add a line to `CombatSandbox.GROUP_PRESETS`.

---

## 5. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/ship_class_test.gd
& $godot --headless --path . --script res://scripts/tests/formation_geometry_test.gd
& $godot --headless --path . --script res://scripts/tests/formation_steering_test.gd
& $godot --headless --path . --script res://scripts/tests/formation_movement_test.gd
```

`formation_geometry_test.gd` covers every shape's layout (slot counts, zones, no two slots closer than the spacing for any size, symmetry, columns and echelons from the same layout), spacing and extent, and seating (strongest at the tip, cargo in the core, lightest as pickets, stability, determinism, and random formations of every shape).

`formation_steering_test.gd` covers the pure maths: speed and thrust caps, the turn limit (including the sideways-acceleration term), following velocity, slot velocity, trim thrust, separation and obstacle avoidance.

`formation_movement_test.gd` runs formations through the real sandbox scene **in real time (about five minutes)**; pass scenario names after `--` to run only some (`wedge`, `wander`, `shapes`, `member`, `leader`, `dissolve`, `separated`, `disabled`, `recovery`, `shape_change`, `jump`, `planet`, `player`). It checks members holding station along a fixed racetrack and behind a randomly wandering leader, every shape, the leader's speed and turn limits, no overlaps, a destroyed member and a destroyed leader (and route continuity), dissolving, a separated member, a wrecked member, a straggler catching up, changing shape without jumping, jumping in and out with the leader, and avoiding a planet and the player.
