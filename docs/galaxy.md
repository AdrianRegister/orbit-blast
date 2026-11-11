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

Each system obeys `StarSystem.validate()`: at least one planet, at most 3 objects, and a moon only together with a planet. **Gas giants** are undockable and uninhabited (`PlanetData.dockable = false`; validation requires no population, market, contracts or services), and NPC traffic ignores them as destinations. Dwarf planets and moons are small `size` values of existing sprites. New locations have goods lists and a few shipyards and outfitters but no markets or contracts yet. Systems with fewer than two dockable places have no NPC traffic.

---

## 5. Discovery

`TravelManager` keeps the set of discovered systems. A new game starts with every `start_discovered` system (Sol); arriving in a system discovers it (`discover(id)`, which can also be called by anything else, such as a future exploration contract). The map draws discovered systems filled and unexplored ones hollow and dim; unexplored systems still show their name but their faction, imports, exports and services read "Unknown".

---

## 6. Jumping

The flow: open the map (**M**), click a linked system, press **SELECT DESTINATION** (the map closes), fly clear of the system centre and press **J**.

**Navicomputer.** The space HUD has a NAVICOMPUTER panel between CARGO and TARGET. It shows `Selected destination: <name>` (or "No destination selected"), how far the ship is from the system centre against the minimum (`FROM CENTRE 1,540 / 2,000`), and a status: **JUMP OK - PRESS J** in green once the ship is at least `jump_radius` (2,000 px by default) from the centre, **TOO CLOSE TO CENTRE** in red before that, **JUMPING...** during the jump. If J is pressed and something stops it (no destination, too close, docked), the reason appears in red in the panel. `Main` pushes these values into `Hud.set_navigation()` every frame; the HUD holds no navigation state.

**The system map.** At the top of the NAVICOMPUTER panel is a small square map (`NavMap`, `scripts/ui/nav_map.gd`) in the style of Escape Velocity Nova's sensor display. It is always centred on the player and scrolls as the ship moves (north stays up); it covers 2,500 px in each direction (`view_range`). Planets are blue circle outlines, uninhabited bodies such as gas giants grey outlines, stations yellow outlines, NPC ships blue dots, and the player a small white arrow showing the heading. If no planet or gas giant is in view, a yellow arrow flashes at the edge of the map pointing towards the system centre; it disappears as soon as a planet comes into view and is hidden when the ship is already at the centre. `Main` gives it the loaded system (`Hud.set_nav_system`), including after a jump. It reads the ship and the system and owns no state; `nav_map_test.gd` covers it.

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

No fuel or energy resource (the cost is shown only), no contracts that send the player to other systems, no markets or contracts in the new systems, and no procedural galaxy. Each system's star background is identical.
