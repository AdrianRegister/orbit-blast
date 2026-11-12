# Galaxy, Galaxy Map and Inter-system Travel

How the galaxy is described, how the map works, how the player jumps between systems, and how to add systems. For saving see [save-system.md](save-system.md); for scenes and data layering see [scene-inheritance-and-content.md](scene-inheritance-and-content.md).

Contents

1. [Overview](#1-overview)
2. [Structure](#2-structure)
3. [The galaxy data](#3-the-galaxy-data)
4. [The systems](#4-the-systems)
5. [Discovery](#5-discovery)
6. [Jumping](#6-jumping)
7. [The galaxy map](#7-the-galaxy-map)
8. [Saving](#8-saving)
9. [Recipes](#9-recipes)
10. [Testing](#10-testing)
11. [Current limits](#11-current-limits)

---

## 1. Overview

The galaxy is static data (`resources/universe/galaxy.tres`): which star systems exist, where each sits on the galaxy map, and which pairs are linked. The map (press **M**) is a navigation interface over that data; it does not replace the star system scenes. Jumping follows links only, loads the destination system with the existing system-swapping code, and puts the ship on the edge of the new system.

---

## 2. Structure

| Piece | File | Role |
|---|---|---|
| `Galaxy` | `scripts/galaxy/galaxy.gd`, `resources/universe/galaxy.tres` | All systems and links; lookups, jump costs, validation |
| `GalaxySystem` | `scripts/galaxy/galaxy_system.gd` | One entry: the system scene, its map position, whether it starts discovered, its faction |
| `SystemLink` | `scripts/galaxy/system_link.gd` | A two-way jump connection, with an optional fuel cost override |
| `SystemSummary` | `scripts/galaxy/system_summary.gd` | Read-only description of a system (name, locations, imports, exports, services), built from its scene |
| `TravelManager` | `scripts/galaxy/travel_manager.gd` | Jump rules and the discovered set; the `galaxy` save section |
| `JumpCheck` | `scripts/galaxy/jump_check.gd` | Result of "may I jump there now?" |
| `GalaxyMapScreen` | `scenes/ui/galaxy_map_screen.tscn`, `scripts/ui/galaxy_map_screen.gd` | The screen: map plus information panel and Jump button |
| `GalaxyMapView` | `scripts/ui/galaxy_map_view.gd` | The drawn map, panning, zooming and picking |
| `JumpFlash` | `scenes/ui/jump_flash.tscn`, `scripts/ui/jump_flash.gd` | The white flash that hides the change of system |

`TravelManager` is a node in `main.tscn` (no Autoload). `Main` owns the scene work (`jump_to`), as it already did for loading saves.

---

## 3. The galaxy data

- A system's **id and name stay on its scene** (`StarSystem.system_id`, `system_name`). The galaxy never copies them; it reads them from the scenes once (`SystemSummary`) and keeps the result. That is also how the map can describe a system that is not loaded, and how a location id is mapped back to its system (`Galaxy.system_of_location`).
- `map_position` is in map units, independent of the layout inside the system. Sol is the origin.
- **Links** are explicit and two-way. A link's **jump cost** is its own `fuel_cost` if set, otherwise the map distance times `Galaxy.fuel_per_unit` (rounded up, at least 1). Set `fuel_cost` on a link to balance it individually.
- `Galaxy.validate()` reports links to unknown systems, self-links, duplicate links, repeated system ids, systems sharing a position, systems that cannot be reached from the first one, and any problem found in a system scene.

---

## 4. The systems

```
Barnard's Star      Tau Ceti       Epsilon Eridani
        |               |                |
  Alpha Centauri     Sirius          Procyon
              \        |        /
                   Sol
```

| System | Locations |
|---|---|
| Sol | Earth, Mars, Victory I |
| Alpha Centauri | Hera, Argo Station |
| Barnard's Star | Daedalus (dwarf planet), Atlas (gas giant), Atlas Ring (station) |
| Sirius | Persephone, Hecate (moon), Sirius Gate (station) |
| Tau Ceti | Aurelia, Oberon (gas giant) |
| Procyon | Talos, Minos (dwarf planet) |
| Epsilon Eridani | Elysium, Lethe (moon), Styx Platform (station) |

Each system obeys `StarSystem.validate()`: at least one planet, at most 3 objects, and a moon only together with a planet. **Gas giants** are undockable and uninhabited (`PlanetData.dockable = false`; validation requires no population or services), and NPC traffic ignores them as destinations. Dwarf planets and moons are small `size` values of existing sprites. Inhabited locations get a market automatically (what they make and use follows from population and planet type, see [economy.md](economy.md)) and a few get shipyards and outfitters. Systems with fewer than two dockable places have no NPC traffic.

---

## 5. Discovery

`TravelManager` keeps the set of discovered systems. A new game starts with every `start_discovered` system (Sol); arriving in a system discovers it (`discover(id)`, which can also be called by anything else, such as a future exploration contract). The map draws discovered systems filled and unexplored ones hollow and dim; unexplored systems still show their name but their faction, imports, exports and services read "Unknown".

---

## 6. Jumping

The flow: open the map (**M**), click a linked system, press **SELECT DESTINATION** (the map closes), fly clear of the system centre and press **J**.

**Navicomputer.** The space HUD has a NAVICOMPUTER panel between CARGO and TARGET. It shows `Selected destination: <name>` (or "No destination selected"), how far the ship is from the system centre against the minimum (`FROM CENTRE 1,540 / 2,000`), and a status: **JUMP OK - PRESS J** in green once the ship is at least `jump_radius` (2,000 px by default) from the centre, **TOO CLOSE TO CENTRE** in red before that, **JUMPING...** during the jump. If J is pressed and something stops it (no destination, too close, docked), the reason appears in red in the panel. `Main` pushes these values into `Hud.set_navigation()` every frame; the HUD holds no navigation state.

**The system map.** At the top of the NAVICOMPUTER panel is a small square map (`NavMap`, `scripts/ui/nav_map.gd`) in the style of Escape Velocity Nova's sensor display. It is always centred on the player and scrolls as the ship moves (north stays up); it covers 2,500 px in each direction (`view_range`). Planets are blue circle outlines, uninhabited bodies such as gas giants grey outlines, stations yellow outlines, NPC ships blue dots (the dot of the currently selected ship flashes until it is deselected or the ship is gone), and the player a small white arrow showing the heading. If no planet or gas giant is in view, a yellow arrow flashes at the edge of the map pointing towards the system centre; it disappears as soon as a planet comes into view and is hidden when the ship is already at the centre. `Main` gives it the loaded system (`Hud.set_nav_system`), including after a jump. It reads the ship and the system and owns no state; `nav_map_test.gd` covers it.

**The destination** is chosen only from systems linked to the current one (`TravelManager.set_destination`), is saved in the `galaxy` section, and is cleared when the jump completes (or if a loaded save's destination is not linked to where the player is).

**The rules** (`TravelManager.check_jump`): refused when the system is unknown, is the current one, is not linked, the player is docked, the ship is closer to the centre than `jump_radius`, or (later) there is not enough fuel. **Fuel is not enforced yet**: the cost is calculated and displayed, and `_has_fuel()` is where it will be checked and deducted.

**The sequence** (`Main.try_jump`, J):
1. J is pressed and the rules are checked. The ship's controls are ignored (`PlayerShip.warping`) and it accelerates along its heading to a very high speed (`WARP_SPEED` 9,000 px/s at `WARP_ACCELERATION` 6,000 px/s^2). Opening the map is blocked meanwhile.
2. After `Main.WARP_DURATION` (2 seconds) the screen flashes white (`JumpFlash`): a quick rise, then a fade.
3. While the screen is fully white, `Main.jump_to(id)` swaps the systems (the old system and its NPCs are freed), keeps the ship's heading and puts it on the opposite edge of the new system (leave pointing up and you enter from the bottom, still flying up, drifting in slowly), starts the new traffic, marks the system discovered, clears the destination and requests an autosave.
4. The flash fades away over the new system.

Credits, cargo, contracts and the ship with its upgrades are separate objects and are untouched. `jump_to` can also be called directly (the tests do); it applies the same rules but has no warp or flash.

---

## 7. The galaxy map

- **M** opens it (flying or docked, when nothing else is on screen); **M** or **Esc** closes it. The game is paused while it is open, so the ship does not drift and flight keys do nothing.
- Drawn like a Nova-style chart: dark background, faint grid, thin link lines. The current system has double rings and "YOU ARE HERE"; systems linked to it have a bright outline and bright links; the selected system has corner brackets. Labels keep one screen size at every zoom.
- **Click** a marker to select it, **drag** to pan, **scroll** to zoom (around the cursor, limited). The view opens centred on the current system, zoomed out just enough to show the whole galaxy if needed.
- The side panel shows the name, status, faction, route, jump cost, distance, exports, imports, services and links, and a **SELECT DESTINATION** button, enabled for any system directly linked to the current one (otherwise the reason is shown in red). Selecting closes the map and sets the navicomputer's destination, which the map then labels "DESTINATION". The map works while docked too, so a destination can be chosen before departing. Jumping is done from space with **J**, not from the map.

---

## 8. Saving

The `galaxy` section is optional and holds the discovered system ids and the selected destination (`{"discovered": [...], "destination": "id"}`; the destination is optional). The current system stays in the `player` section. Saves from before the map load with the default (Sol plus the system the player is in), so no migration was needed. Static data (positions, links) is never in the save.

---

## 9. Recipes

**Add a system**: make `scenes/systems/<name>_system.tscn` inheriting `star_system.tscn` with a unique `system_id` and a `system_name`, placing planets and stations under `Objects` (unique location ids in `resources/locations/`). Add a `GalaxySystem` (scene, map position, faction) to `galaxy.tres` and at least one `SystemLink`. Run `galaxy_test.gd`: it validates everything.

**Rebalance jump cost**: change `fuel_per_unit` on the galaxy, or set `fuel_cost` on a link.

---

## 10. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/galaxy_test.gd
& $godot --headless --path . --script res://scripts/tests/travel_test.gd
& $godot --headless --path . --script res://scripts/tests/galaxy_map_smoke_test.gd
& $godot --headless --path . --script res://scripts/tests/navigation_test.gd
```

`galaxy_test.gd` covers the data (lookups, summaries, links, costs, validation, every system and its rules, traffic). `travel_test.gd` covers the jump rules, discovery, the transition and what it preserves, and saving including a docked save in another system and an old save without the section. `galaxy_map_smoke_test.gd` plays the map through the real scene: layout at configured positions, selecting, panning, zooming, reachability, M and Esc, choosing a destination and jumping with J. `navigation_test.gd` covers the navicomputer readout, J and its refusals, the warp acceleration, the flash timing, the arrival, and saving the destination (it takes about ten seconds because the sequence is timed).

---

## 11. Current limits

No fuel or energy resource (the cost is shown only), no contracts that send the player to other systems, and no procedural galaxy. Each system's star background is identical.

## 12. Inhabited, scouted and Wolf 359 (Phase 2.4)

- **`inhabited`** is derived from a system's locations (`SystemSummary.inhabited`, `Galaxy.is_inhabited`): true if at least one dockable location has people. **`scouted`** is player state in `TravelManager`: the bodies of a system the player has been within docking range of; a system is scouted when it has all of them (`get_scouting_progress`, `is_scouted`, `update_scouting`, `system_scouted`). A system must be discovered before it can be scouted, and flying at warp speed does not scout.
- **Map colours:** discovered systems are blue. A system that is uninhabited **and** scouted turns white; until then an uninhabited system looks like any other discovered one. The info panel shows SCOUTED ("2 of 3 bodies") and INHABITED (Unknown until scouted, except that inhabited systems are recognised on discovery).
- **Wolf 359** is a dead-end system one jump from Barnard's Star, uninhabited, with **Medusa** (jungle planet, undockable) and **Cerberus** (red gas giant, undockable). It has no NPC traffic.
- `Galaxy.find_route(a, b)` returns the cheapest chain of systems along the links and `get_route_cost(route)` its fuel cost; contracts use them for journey text and rewards.
- The `galaxy` save section gains `scouted_nodes` (`{system id: [location ids]}`, optional).

## 13. Factions (Phase 2.6)

A faction is a `Faction` resource (`scripts/resources/faction.gd`) in `resources/factions/`: `id` (permanent, e.g. `faction_1`), `display_name` ("Federation"), `colour`, `description`. Locations (`InhabitedData.faction`), star systems (`GalaxySystem.faction`) and ship models (`ShipStats.faction`) refer to the resource, never to a name, so the name is written in one place. Compare factions by id (`faction_id()`, `Galaxy.get_faction_id()`); show the name with `get_faction_name()`. To add a faction, add a `.tres` with a new id; `ContentRegistry.faction(id)` finds it. Relations and reputation will be added to `Faction`.


## 14. The galaxy table and generator (Phase 2.6)

The galaxy follows the Escape Velocity Nova map (`reference_resources/escape_velocity_nova_galaxy_map.webp`). It is **data driven**:

| Piece | File | Role |
|---|---|---|
| Table | `data/galaxy/galaxy_map.json` | One row per system: `id`, `name`, `x`,`y` (pixels of the reference image), `faction` (a faction id, "" = unclaimed), `inhabited` (black dot on the reference map), `links`, `region`; optional `class` (a system class id, see [system_classes.md](system_classes.md)); flags `hand_built` and `locked`. `origin_system` (Sol) and `scale` place systems on our map |
| Name pools | `data/galaxy/name_pools.json` | Themed names for generated planets and stations, per region |
| Generator | `tools/galaxy_generator.gd`, run by `tools/generate_galaxy.gd` | Writes `scenes/systems/generated/`, `resources/locations/generated/` and `resources/universe/galaxy.tres` |
| Test | `scripts/tests/galaxy_data_test.gd` | The table is sound, the files on disk are exactly what the table produces, speed |

```powershell
& $godot --headless --path . --script res://tools/generate_galaxy.gd
```

**What is generated.** Each system gets 1 to 3 bodies (an ordinary system holds at most 3 objects; a system class may allow up to 6, see [system_classes.md](system_classes.md)). A system the map shows as inhabited gets an inhabited first body built from an archetype (farming, mining, industrial, trade, outpost): a planet type and a population range from the archetype (the economy follows from those, so no goods list or market file is written), and for a few places a shipyard or outfitter. The archetype's export and import lists are used only to keep the seeded random sequence, and so every id, unchanged. Other bodies are barren and cannot be landed on (gas giants, rocks); uninhabited systems have only those. Names come from the region's pool and are unique across the galaxy. Everything is seeded from the system id, so running the generator again changes nothing.

**Hand built and locked.** `hand_built` systems (Sol, Centauri, Barnard's Star, Sirius, Tau Ceti, Procyon, Wolf 359 and Alphard, whose id is still `epsilon_eridani`) keep their own scenes and locations; the generator only lists them in `galaxy.tres`. Ids never change, so old saves still work; only the displayed names differ from before. `locked` systems are generated once and then ignored by the generator, so they can be edited by hand (the names their locations hold stay reserved, so no other system takes them and no id changes).

**Richer content later.** Change the archetypes (or add fields) in the generator and regenerate; hand built and locked systems are not touched.

**Adding systems.** Add rows (with links on both ends) to the table and regenerate. The test fails if a link is one-sided, an id or name repeats, or a system cannot be reached from Sol.

**Scale.** Neighbour and link lookups use an index; `Galaxy.get_reachable(origin, max_jumps)` is one breadth-first search and is what contract generation uses to find nearby places. The galaxy map only draws names of undiscovered systems when zoomed in, and skips systems that are off screen.

**Now.** The Federation core around Sol (about 90 systems). The remaining regions of the reference map are a later step: more rows in the table, factions for the other territories, name pools for them.


## 15. Ownership and contested systems (Phase 2.7)

**Settlements own; systems are derived.** The faction of an inhabited place (planet or station, `InhabitedData.faction`) is the single fact. Who controls a star system is worked out from its settlements, so a system can be contested (Earth Federation, Mars held by someone else) with nothing stored at system level.

- **`TerritoryManager`** (`scripts/galaxy/territory_manager.gd`, a node in `main.tscn`, no Autoload) answers every question about ownership. `owner_of(location)` / `owner_id_of` / `owner_name_of` give the *current* owner: a runtime override if there is one, otherwise the location's own `faction` (its starting owner; static content is never changed while playing). `transfer_settlement(location, faction)` changes hands (null = independent) and announces it with `settlement_owner_changed`, `system_control_changed`, `system_became_contested` and `territory_changed`. Wars will use this one call.
- **`get_control(system_id) -> SystemControl`** (`scripts/galaxy/system_control.gd`): `UNCLAIMED`, `CONTROLLED` (one faction owns every settlement) or `CONTESTED` (settlements of two or more factions: the system then has **no owner**, `factions` lists who is present). Only settlements count (dockable places with people); independent settlements do not make a system contested; a system with no settlements goes to its **claim**.
- **`GalaxySystem.claim`** (was `faction`): the faction a system belongs to on the map. It decides systems with no settlements and is the default owner of the settlements generated there (the table's `faction` field). It never says who owns settlements.
- **Who reads it:** cargo contracts (a delivery must be between settlements with the same current owner, even inside one system; `Contract.get_issuing_faction()`), shipyard faction gating (`ShipManager`), the HUD "OWNED BY" row and NPC ships' faction (through `StarSystem.set_owner_lookup`), and the galaxy map (the FACTION row shows "Contested: A, B"; a contested system gets a ring split in the factions' colours).
- **Saving:** an optional `territory` section `{"owners": {location id: faction id or ""}}` holds only the settlements that differ from their starting owner; older saves load with every settlement at its starting owner.
- **To make a contested system today:** edit a settlement's `faction` in its location file (in a `locked` system if it is generated), or call `transfer_settlement` in a test.
- **For wars:** `SystemControl` has room for a dominant controller of a contested system (for example by military value); military value, strength and operations are not built yet. See `wars_system.md`.

Zones, centres of power and mini-cores that follow ownership are in [system_classes.md](system_classes.md).

Tests: `scripts/tests/territory_test.gd`.
