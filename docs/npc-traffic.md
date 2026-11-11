# NPC Ships and Ambient Traffic

How ambient NPC ships work, how they connect to star systems, planets, stations and targeting, and how to add ship types or tune a system's traffic. For scene inheritance see [scene-inheritance-and-content.md](scene-inheritance-and-content.md); for the economy see [economy.md](economy.md).

Contents

1. [Overview](#1-overview)
2. [Structure](#2-structure)
3. [Behaviour (state machine)](#3-behaviour-state-machine)
4. [Spawning and cleanup](#4-spawning-and-cleanup)
5. [Targeting](#5-targeting)
6. [Interaction with planets and stations](#6-interaction-with-planets-and-stations)
7. [Recipe: add a ship type](#7-recipe-add-a-ship-type)
8. [Recipe: tune or override a system's traffic](#8-recipe-tune-or-override-a-systems-traffic)
9. [Testing](#9-testing)
10. [Current limits and extension points](#10-current-limits-and-extension-points)

---

## 1. Overview

Every star system has ambient traffic: ships that fly between its inhabited locations, dock for a while, fly on to another location, and eventually leave the system out of sight. The player can select them with the mouse or with **T**. There is no combat, no mission logic and no NPC trading in this milestone.

---

## 2. Structure

```
star_system.tscn (inherited by every system)
 ├── Background
 ├── Objects        planets and stations
 ├── Ships          every NPC ship is a child of this node
 └── Traffic        TrafficManager  (config: a TrafficConfig resource)
```

| Piece | File | Role |
|---|---|---|
| `NpcShip` | `scripts/ships/npc_ship.gd`, `scenes/ships/npc_ship.tscn` | One AI ship and its state machine |
| `TrafficManager` | `scripts/systems/traffic_manager.gd` | Decides what spawns and where, keeps the population at the cap |
| `ShipType` | `scripts/resources/ship_type.gd`, `resources/ship_types/*.tres` | Name, sprite, scale, flight stats, category (civilian / military), spawn weight |
| `TrafficConfig` | `scripts/resources/traffic_config.gd`, `resources/traffic/default_traffic.tres` | Population cap, ship type pool, spawn and behaviour tuning |
| `NpcShipDetails` | `scripts/resources/npc_ship_details.gd` | The faction / ship / status rows shown in the HUD target panel |
| `ShipStats` (existing) | `scripts/resources/ship_stats.gd` | Thrust, turn rate and top speed, shared with the player ship's data format |

`NpcShip` node layout:

```
NpcShip (Node2D)        does not rotate
 ├── Visual (Node2D)    rotates to the heading
 │    └── Sprite2D
 └── Targetable         instance of targetable.tscn, cycle_group = targetable_ship
```

Only `Visual` rotates, so the yellow selection brackets of the `Targetable` stay upright, exactly like those of planets and stations.

Because the NPCs are children of the system scene, **freeing or replacing the system frees its NPCs**. No NPC can be left behind when systems are switched, and no Autoload is used.

`StarSystem` gained three helpers: `get_inhabited_nodes()`, `get_ships_root()` and `start_traffic(player)`. `Main` calls `start_traffic(player_ship)` once for the system it loads. A future system-switching mechanic should call the same method on the new system. `get_space_objects()` is unchanged and does not include NPCs.

---

## 3. Behaviour (state machine)

`NpcShip.State`: `TRAVELLING`, `APPROACHING`, `DOCKED`.

| State | What the ship does | Moves on when |
|---|---|---|
| TRAVELLING | Accelerates toward its destination and cruises at top speed | The braking curve says it must start slowing down |
| APPROACHING | Turns retrograde and thrusts against its velocity so it stops just inside the destination's docking range | Inside docking range and slower than `DOCK_SPEED` (10 px/s) |
| DOCKED | Sits stopped at the location, **still visible and targetable**, for a random time | Timer ends: picks a **different** location and flies off from where it sits |

- **Same rules as the player.** Ships fly like the player: thrust only pushes along the facing direction and momentum is kept, so to slow down the ship must turn retrograde first. It docks only when it is inside the docking range (`Targetable.dock_range` via `SpaceObject.get_dock_range()`) and almost stopped. The braking curve starts early enough to leave time for that turn, which is slower for big ships like the freighter.
- **Docked ships stay in the world.** They do not hide or become untargetable, so they can be selected, and later attacked. They leave by turning toward their next destination and accelerating; nothing teleports.
- **Leaving the system.** After a random number of visits (`visits_range`) a ship heads out of the system (DEPARTING) along the direction of one of the system's links, and once it is at least the system's `jump_radius` from the centre (the player's rule) it warps away (WARPING): it accelerates hard and is removed once well clear. A ship that is warping can no longer be targeted. A system with no links has no jumping traffic: its ships keep visiting forever.
- The steering ignores velocity errors under 8 px/s and thrusts only when facing within about 17 degrees of the direction it needs to accelerate in. There is no pathfinding and no collision between ships or with planets, so ships docked at the same place can overlap.
- The ship's faction is copied from the faction of the location it came from. There is no separate faction system yet.

---

## 4. Spawning and cleanup

`TrafficManager` (configured by `TrafficConfig`):

1. **At load** it places `initial_fill_fraction × max_ships` ships already in flight, at random points between two locations, so the system is not empty.
2. **Afterwards**, every `spawn_interval` seconds (divided by the system's `traffic_rate`) while below the cap (`max_ships` x `traffic_rate`), one ship appears. In a system with links it jumps in at the edge of the system (see "Traffic between systems" below); a system without links spawns it just outside a random location's docking range, as if it had just undocked.
3. A spawn point is rejected, and another tried (12 attempts, then it waits for the next tick), if it is:
   - closer than `min_spawn_distance_from_player` to the player,
   - closer than a location's docking range plus `spawn_clearance` to any location (except the one it leaves),
   - closer than `ship_spacing` to another visible NPC.
4. The ship type is a weighted random pick from `ship_types` (`spawn_weight`).
5. **Cleanup:** NPCs that have finished their visits leave only when the player cannot see them (see section 3) and are replaced by new arrivals. All of them are freed with the system.

`max_ships` is one total for now. `ShipType.category` (civilian / military) exists so the cap can be divided between the two later.

---

## 5. Targeting

| Input | Action | Cycles through |
|---|---|---|
| Left-click | selects whatever is under the cursor | planets, stations, ships |
| **Tab** | `cycle_target` | planets and stations only (unchanged behaviour) |
| **T** | `cycle_ship_target` | NPC ships only |

The two cycles behave identically: scene order, wrap-around, and the first entry when nothing (or something from the other group) is selected.

How it is done:

- `Targetable` has `cycle_group` (`Targetable.LOCATION_GROUP` by default, `Targetable.SHIP_GROUP` for NPCs). Every `Targetable` also still joins the general `targetable` group.
- `TargetingManager.select_next(group)` cycles one group and skips disabled targets.
- `Targetable.set_enabled(false)` disables a target: the click shape is switched off, the cycle skips it, and a current selection is cleared (`became_unavailable` signal). NPCs do not use it when docking, because docked ships stay targetable; it is there for future use. Freed ships clear the selection through the existing `tree_exiting` path.
- The HUD target panel shows the ship's name, `Ship (Type)`, distance, and `NpcShipDetails` rows (FACTION, SHIP, STATUS). The status updates live (for example "Approaching Earth"). Pressing dock on a ship says it cannot be docked with, because its details are not dockable.

---

## 6. Interaction with planets and stations

- NPCs treat every `InhabitedNode` in the system's `Objects` node as a possible destination, so a new planet or station is automatically part of the traffic. A system needs at least two to have traffic.
- NPCs only read from locations (position, docking range, name, faction). They never change them.
- NPCs do not use or change a location's market or the player's economy.
- Locations are never moved, blocked or affected by ships.

---

## 7. Recipe: add a ship type

1. Put the sprite in `assets/sprites/ships/` (all ship art must point **up**; the sprite node is rotated +90° so up becomes the heading).
2. Create flight stats if needed: `resources/ships/<name>_stats.tres` (**ShipStats**: `thrust`, `turn_rate`, `max_speed`; `cargo_capacity` is ignored by NPCs). Existing ones can be reused.
3. Create `resources/ship_types/<name>.tres` (**ShipType**) and set `display_name`, `texture`, `sprite_scale` (see below), `stats`, `category` and `spawn_weight`. On-screen width is the texture width times `sprite_scale`: all ship art is 500 px wide.
4. Add it to the `ship_types` array of a `TrafficConfig` (for example `resources/traffic/default_traffic.tres`).

```ini
[gd_resource type="Resource" script_class="ShipType" format=3]

[ext_resource type="Script" path="res://scripts/resources/ship_type.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/sprites/ships/shuttle.png" id="2"]
[ext_resource type="Resource" path="res://resources/ships/shuttle_stats.tres" id="3"]

[resource]
script = ExtResource("1")
display_name = "Shuttle"
texture = ExtResource("2")
sprite_scale = 0.15
stats = ExtResource("3")
category = 0
spawn_weight = 3.0
```

No code changes are needed. Current types and sizes: Shuttle (civilian, scale 0.15, 75 px), Freighter (civilian, scale 0.4, 200 px, slow), Interceptor (military, scale 0.12, 60 px, which is 80% of the shuttle, fast).

---

## 8. Recipe: tune or override a system's traffic

The base `star_system.tscn` assigns `default_traffic.tres` to its `Traffic` node, so every system gets it. To change one system:

1. Create `resources/traffic/<system>_traffic.tres` (**TrafficConfig**).
2. In the system's scene (an inherited scene), select the `Traffic` node and assign the file to **Config**.

```ini
[node name="Traffic" parent="." index="3"]
config = ExtResource("5")
```

Settings:

| Field | Meaning | Default |
|---|---|---|
| `max_ships` | Most NPCs alive at once at a traffic_rate of 1.0; 0 disables traffic | 10 |
| `ship_types` | Pool of `ShipType`; picked by weight | shuttle, freighter, interceptor |
| `spawn_interval` | Seconds between new arrivals at a traffic_rate of 1.0 | 5 |
| `initial_fill_fraction` | Share of the cap placed in flight at load | 0.5 |
| `min_spawn_distance_from_player` | Spawn exclusion radius around the player (px) | 800 |
| `spawn_clearance` | Extra gap kept beyond each location's docking range (px) | 150 |
| `ship_spacing` | Minimum gap to other ships when spawning (px) | 150 |
| `departure_clearance` | How far beyond the docking range newly arriving ships appear (px) | 40 |
| `dock_time_range` | Seconds docked, (min, max) | (5, 15) |
| `visits_range` | Visits before leaving the system, (min, max) | (1, 3) |

Problems in the config or a ship type are reported in the Output panel when the system loads.

---

## 9. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/npc_traffic_test.gd
```

`npc_traffic_test.gd` loads the real main scene and checks: the starting population, spawn clearance from the player, locations and other ships, the population cap over a simulated 20 minutes, the TRAVELLING → APPROACHING → DOCKED sequence, that every docking happens in range and slowly, that ships depart for a different location, that ships leave after their visits and are replaced, the T and Tab cycles (wrapping, group separation, skipping disabled targets, clearing a selection that becomes unavailable), that docked ships stay visible, targetable and stopped, that ships turn retrograde to brake, that no ship vanishes within the despawn distance of the player, the ship sizes and the sprite orientation, HUD rows, mouse selection, and that freeing the system leaves no ships. It exits with code 1 on failure.

The movement, brackets and look of the ships are best checked by running the game.

---

## 10. Current limits and extension points

| Not done yet | Where it plugs in |
|---|---|
| Military / civilian population split | `ShipType.category` plus per-category caps in `TrafficConfig` and `TrafficManager` |
| Combat, weapons, reactions to the player | New states in `NpcShip.State` and a new behaviour step in `_physics_process` |
| NPC trading | `NpcShip` docking hook (`_dock()`) and the `EconomyManager` markets |
| Real factions | Replace the copied `faction_name` string |
| Jumping between systems | Swap the `StarSystem` node in `Main` and call `start_traffic()` on the new one; the old NPCs are freed with the old system |
| Collision avoidance, pathfinding | Replace the straight-line steering in `NpcShip._fly()` |

## 11. Saving

NPC ships are not saved. After a load, `StarSystem.restart_traffic()` removes every NPC and starts the traffic again from scratch (`TrafficManager.reset()`), so loading never duplicates ships. See [save-system.md](save-system.md).

## Selecting the nearest ship

The **R** key (`target_nearest_ship`) selects the NPC ship closest to the player (`TargetingManager.select_nearest`, measured from the ship given to `set_origin`). T still cycles through ships one by one. R does nothing when there is no ship to select. Covered by `target_nearest_test.gd`.


## Traffic between systems

Ships travel between star systems the way the player does. In each system:

- **Arrivals.** New ships jump in (ARRIVING) at the edge of the system, on the circle of the system's `jump_radius`, from the direction of one of its links on the galaxy map (so ships arriving from Sol appear on the side of Sol). They enter fast, slow down to their own top speed, and carry on as normal to a random location. `Main` gives each system the bearings of its links (`StarSystem.set_traffic_exits`) before starting its traffic.
- **Departures.** After their visits ships leave by a link, jumping once they are beyond the jump radius (see above).
- **`StarSystem.traffic_rate`** scales it all: the cap on ships in the system (`max_ships` x rate) and how often a ship arrives (`spawn_interval` / rate). Departures follow, because ships leave after their visits and replacements only arrive while below the cap. 1.0 is a busy core system and is the default, so all seven current systems are busy (about four arrivals a minute with the default config). A remote or sparsely populated system should use about 0.1 to 0.3, and 0 means no traffic at all.
- A system with no links (or none that matter) keeps the older behaviour: its own residents undock from its locations to replace ships, and nobody leaves.

`NpcShip` has the new states ARRIVING, DEPARTING and WARPING; `TrafficManager` has `get_max_ships()`, `get_spawn_interval()` and `set_exit_bearings()`. Tests: `traffic_flow_test.gd` (arrivals on the edge along links, departures only beyond the jump radius, no ship vanishing without warping, rate scaling, rate 0, systems with no links) and the updated `npc_traffic_test.gd`.
