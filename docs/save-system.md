# Save and Load

How the game is saved and loaded, what is in the save file, and how to keep it working as the game grows. For contracts see [missions.md](missions.md), for cargo and markets see [economy.md](economy.md), for static data see [scene-inheritance-and-content.md](scene-inheritance-and-content.md).

Contents

1. [Overview](#1-overview)
2. [What is saved, and what is not](#2-what-is-saved-and-what-is-not)
3. [The save file](#3-the-save-file)
4. [Architecture](#4-architecture)
5. [Saving: manual and automatic](#5-saving-manual-and-automatic)
6. [Loading](#6-loading)
7. [Damaged and incompatible saves](#7-damaged-and-incompatible-saves)
8. [Menus](#8-menus)
9. [Rules for permanent ids](#9-rules-for-permanent-ids)
10. [Recipe: save new state](#10-recipe-save-new-state)
11. [Recipe: change the format](#11-recipe-change-the-format)
12. [Testing](#12-testing)

---

## 1. Overview

There is one save slot, `user://savegame.json` (on Windows under `%APPDATA%\Godot\app_userdata\Orbit Blast\`). It is written when the player chooses **Save Game** in the pause menu and automatically after important actions. **Continue** on the main menu and **Load Game** in the pause menu load it.

Nothing in the save file refers to scenes, nodes or Resources. It holds plain data (numbers, text, lists) and refers to game content by permanent **ids** such as `"food"` or `"mars"`.

---

## 2. What is saved, and what is not

| State | Owner | Saved |
|---|---|---|
| Credits | `EconomyManager` / `PlayerData` | yes, `economy.credits` |
| Cargo capacity, ordinary cargo, contract cargo (with notes) | `CargoHold` | yes, `economy.cargo` |
| Market stock of every visited market, and the day each was brought up to | `Market` | yes, `economy.markets` |
| The calendar day | `GameClock` | yes, `clock` (optional; absent in older saves, then day 0) |
| Damage to planets and stations (only the damaged ones) | `InfrastructureManager` | yes, `infrastructure` (optional) |
| The day each critical system last changed hands | `ZoneManager` | yes, `zones` (optional) |
| Available, active, completed and failed contracts; the next contract id | `ContractManager` | yes, `contracts` |
| Which settlements have changed hands (only those that differ from their starting owner) | `TerritoryManager` | yes, `territory` (optional) |
| Star system, ship id, position, heading, velocity, flying or docked, and where | `Main` / `PlayerSection` | yes, `player` |
| Reserved sections for changes to locations and other world entities | | `world` (empty) and `extensions` (empty) |
| NPC ships | `TrafficManager` | **no**, regenerated on load |
| Current target, open screens, popups, HUD | UI | **no**, derived |
| Prices | `Market` | **no**, always recomputed from the static data and stock |
| Locations, commodities, ship stats, contract offers | `.tres` resources | **no**, static content |

**NPC ships are regenerated.** They have no persistent state yet (no combat, trading or missions), so saving them would add ids, positions and AI states for nothing. After a load the system gets fresh traffic, as when it is first entered.

**Prices are not stored** because they depend only on static data, what the settlement makes and uses, and the stock. Markets the player never visited are not stored either: they are recreated from the data, the same every time. If later features add mutable market state (a blockade, damaged infrastructure), it goes in the market's saved data next to the stock. Older saves with whole-number stock, an `extra` object and no `day` still load (see [economy.md](economy.md)).

---

## 3. The save file

```json
{
  "version": 1,
  "saved_at": 1731300000,
  "player": {
    "system": "sol", "ship": "shuttle",
    "position": [1234.0, -567.0], "rotation": 1.25, "velocity": [120.0, -40.0],
    "mode": "space",
    "docked_at": "earth"
  },
  "economy": {
    "credits": 500000,
    "cargo": {
      "capacity": 500,
      "manifest": {"food": 25},
      "lots": {"contract_1": {"commodity": "food", "quantity": 40, "note": "contract, Mars in the Sol system"}}
    },
    "markets": {"earth": {"stock": {"food": 1200.0, "electronics": 400.5}, "day": 12}}
  },
  "clock": {"day": 12},
  "contracts": {
    "next_id": 8,
    "generated_locations": ["earth", "mars"],
    "available": [], "active": [], "completed": [], "failed": []
  },
  "world": {"systems": {}},
  "extensions": {}
}
```

- `mode` is `"space"` or `"docked"`; `docked_at` exists only when docked.
- A contract is stored in full, whatever generated it: `{"type": "cargo_delivery", "id", "title", "description", "origin", "destination", "reward", "status", "commodity", "quantity", "quantity_in_hold", "issuing_authority"}`. Origin and destination are location ids; a `ferry` contract has the same fields as a cargo delivery; `issuing_authority` is `CIVILIAN` or `MILITARY` and optional on load (civilian); `status` is the status name.
- `generated_locations` records which locations have already created their offers, so an offer taken or delivered does not come back.
- `saved_at` is the Unix time of the save, shown on the main menu.

---

## 4. Architecture

```
SaveManager (node in main.tscn)
 ├── knows the envelope: version, one section per provider
 ├── register_section("economy",   EconomyManager)
 ├── register_section("contracts", ContractManager)
 └── register_section("player",    PlayerSection)   -> Main.restore_player()
```

| Piece | File | Role |
|---|---|---|
| `SaveManager` | `scripts/save/save_manager.gd` | Collects sections, writes and reads the file, validates then applies, coalesces autosaves |
| `SaveFile` | `scripts/save/save_file.gd` | Atomic write, read with backup fallback. Knows nothing of the game |
| `SaveMigrations` | `scripts/save/save_migrations.gd` | Upgrades old saves one version at a time |
| `SaveData` | `scripts/save/save_data.gd` | Helpers for checking values read from JSON |
| `ContentRegistry` | `scripts/save/content_registry.gd` | Turns ids back into Resources (commodities, locations, ship stats, systems) |
| `Galaxy` | `scripts/galaxy/galaxy.gd`, `resources/universe/galaxy.tres` | System id to scene, map position and links (see [galaxy.md](galaxy.md)) |
| `PlayerSection` | `scripts/save/player_section.gd` | The `player` section |
| `ContractFactory` | `scripts/missions/contract_factory.gd` | Contract type name to class |

A **section provider** is any object with:

```gdscript
func save_state() -> Dictionary                                   # plain data
func validate_state(data, registry, document) -> Array[String]    # problems; changes nothing
func load_state(data: Dictionary, registry) -> void               # replaces the provider's state
func reset_state() -> void                                        # optional: for an optional section missing from the file
```

`SaveManager` never looks inside a section. Each owner of state describes and checks its own, `CargoHold` and `Market` do the same for their parts, and `ContractManager` calls `Contract.to_dict()` and the factory. No Autoload is used and the scene tree is never serialised.

---

## 5. Saving: manual and automatic

- **Manual:** pause menu, Save Game. Written immediately.
- **Automatic:** requested after a contract is accepted or completed, after a trade, and on docking and undocking (which also covers changing location).
- **Coalescing:** one action usually changes several systems, so autosave requests are not written at once; they are collected and written once at the end of the frame (so the state is whole), and writes are at least 2 seconds apart (a request inside that window is written when it ends).
- **Only during a game:** autosave is off until `Main.start_session()` is called (by the main menu). Scenes and tests that create `Main` directly never write the player's save.
- Nothing is saved while a load is in progress.

**Atomic writes** (`SaveFile.write_atomic`): the new save is written to `savegame.json.tmp`, read back and compared; only then is the current save renamed to `savegame.json.bak` and the new file renamed into place. A crash at any step leaves a usable `savegame.json` or `.bak`, never a half-written main file. If renaming fails the old save is put back. Failures are reported through the `save_failed` signal and the pause menu, and the game carries on.

---

## 6. Loading

Loading is **validate everything, then apply**.

1. **Read:** `savegame.json`; if unusable, `savegame.json.bak`.
2. **Migrate** old versions to the current one (section 11).
3. **Validate** every registered section against the data and the registry: shapes and types, ids that resolve, quantities that make sense, and cross-checks (every active delivery contract has its cargo lot of the right size and every lot has an active contract; cargo within capacity; stock only for commodities that exist (goods a market does not deal in are ignored); unique contract ids below `next_id`; a contract's status matches the list it is in). If anything fails, loading stops here and the running game is unchanged.
4. **Apply**, in order: economy (credits, cargo, markets), contracts, then the player (`Main.restore_player`): every screen and popup is closed, the saved star system is loaded if it differs from the current one (from the `Galaxy`), the ship's position, heading and velocity are restored, NPC traffic is cleared and started again, and if the player was docked, the docked state and settlement screen are restored.

Loading **replaces** state, it never adds to it, so loading twice gives the same game. Re-docking after a load uses `DockingManager.restore_docked()`, which does not emit `docked`, so no delivery is made, no reward paid and no autosave triggered by the restore.

If a save says the player was docked at a location that is not in the loaded system (an inconsistent save), the player resumes in open space.

---

## 7. Damaged and incompatible saves

| Problem | Result |
|---|---|
| No save file | Continue and Load Game are disabled; "No saved game" |
| Empty file, truncated or invalid JSON, JSON that is not an object | main file ignored, `.bak` tried; if both fail, a message and the game is unaffected |
| Missing or wrong `version` | refused |
| Version **newer** than the game (`SaveMigrations.CURRENT_VERSION`) | refused with "made by a newer version of the game" |
| Older version | migrated, then validated |
| Wrong types, unknown ids, impossible quantities, contracts that disagree with cargo | refused with the first problem, nothing applied |
| Failed write | `save_failed` signal, message in the pause menu; the previous save is untouched |

On the main menu Continue is disabled when the file cannot even be parsed. A save that parses but does not pass validation is found when Continue is pressed: the menu shows why, stays on screen and New Game still works.

---

## 8. Menus

- **Main menu** (`scenes/ui/main_menu.tscn`, the project's start scene): New Game, Continue (disabled without a usable save; says when the save was made), Quit. It creates `Main`, calls `start_session()` (and `load_game()` for Continue) and removes itself.
- **Pause menu** (`scenes/ui/pause_menu.tscn`): opened with **Esc** in flight or docked when nothing else has used Esc. The trading screen, mission computer and event popup consume Esc first, so closing them does not open the pause menu. Resume, Save Game, Load Game (disabled without a save), Quit to Menu. The game tree is paused while it is open, so the ship keeps its speed. A status line reports "GAME SAVED" or why it failed.

**New Game warns before replacing a save.** If a save file exists (even a damaged one), New Game first shows a confirmation, "START A NEW GAME?", saying the previous saved game will be lost, with Cancel (the default, also Esc) and Start New Game. With no save it starts at once. Nothing is deleted at that moment: the old file is replaced by the first autosave of the new game.

---

## 9. Rules for permanent ids

Ids are what the save file stands on. **Once a release can write saves, never change an id.**

| Content | Field | Example |
|---|---|---|
| Commodity | `Commodity.id` | `food` |
| Location | `InhabitedData.id` | `earth`, `victory_i` |
| Ship | `ShipStats.id` | `shuttle` |
| Star system | `StarSystem.system_id` and the `Galaxy` | `sol` |
| Contract | `Contract.id`, `contract_<n>` (counter saved as `next_id`) | `contract_3` |

Ids must be unique and non-empty. `ContentRegistry.problems` reports duplicates and missing ids, and `InhabitedData.validate()` reports an empty location id. Display names can change freely; ids cannot.

New locations, commodities and ship stats are found by the registry automatically from their folders (`resources/locations/`, `resources/commodities/`, `resources/ships/`). A new star system must also be added to `resources/universe/galaxy.tres`.

---

## 10. Recipe: save new state

For a new system with persistent state (ship upgrades, reputation, exploration, ...):

1. Give the owner `save_state()`, `validate_state()` and `load_state()` as in section 4. Store ids, never Resources or node paths. Use `SaveData` to check numbers read from JSON (they all arrive as floats). Replace the owner's state in `load_state()`; do not add to it.
2. In `Main._ready()`: `_saves.register_section(&"reputation", _reputation)`. Register it after anything it depends on, because sections are applied in order.
3. Request autosaves where the state changes: `something_changed.connect(_saves.request_autosave)`.
4. Add a round-trip test (see `save_state_test.gd`) and cases that must be rejected.

Optional new sections do not break old saves: register with `required = false` and give the provider a `reset_state()`; a save that lacks the section resets it. Mutable per-entity state of locations or systems goes into the reserved `world` section; anything else that does not fit goes in `extensions` or its own section.

Examples of what this supports: owned ships and upgrades (a `ships` section keyed by ship id), discovered systems (a set of system ids), faction reputation (faction id to number), new contract types (a new class returned by `ContractFactory.create()`).

---

## 11. Recipe: change the format

- **Adding an optional field:** no migration. Read it with a default when it is absent.
- **Renaming or restructuring:** raise `SaveMigrations.CURRENT_VERSION` and add a step to `SaveMigrations._steps()` under the old version number, a function that takes the old document and returns the new one. Add a test saving an old-format document and loading it.
- Never edit what an old version of the file meant without raising the version.

---

## 12. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/save_ids_test.gd
& $godot --headless --path . --script res://scripts/tests/save_state_test.gd
& $godot --headless --path . --script res://scripts/tests/save_file_test.gd
& $godot --headless --path . --script res://scripts/tests/save_game_test.gd
& $godot --headless --path . --script res://scripts/tests/save_ui_smoke_test.gd
```

| Test | Covers |
|---|---|
| `save_ids_test.gd` | ids unique and resolvable; every placed location is registered |
| `save_state_test.gd` | credits, cargo with contract lots, markets, active and completed contracts round-trip through JSON; loading twice; no repeated reward; 18 kinds of damaged data rejected |
| `save_file_test.gd` | missing, empty, truncated, non-object, wrong-type, newer-version saves; backup fallback; stray temp file; failed write; migration steps; autosave coalescing and spacing |
| `save_game_test.gd` | the real game scene: position and velocity, docked restore without a repeated reward, regenerated NPCs (not duplicated), star system switching, autosave, refused loads leaving the game untouched |
| `save_ui_smoke_test.gd` | the real buttons: New Game, Continue, Esc, Save, Load, Resume, Quit to Menu, damaged saves; Esc closes the trading screen first |

All tests use throwaway files in `user://`, never the real save. The existing economy, contract, trading, mission and NPC traffic tests are unchanged and still pass.

Manual check: start a game, trade, accept a contract, quit to the menu, press Continue, and confirm credits, cargo (including the contract line), markets and docked state. Then damage `savegame.json` by hand and confirm Continue says so and New Game still works.

## Fleet and save version 2

Version 2 added the `fleet` section (see [ships-and-upgrades.md](ships-and-upgrades.md)): `next_id`, `active` and a list of ships with `id`, `model`, `name`, `upgrades` and `flags`. `ShipManager` is the section provider and is registered after the economy so the hold takes the active ship's capacity. The `player` section no longer stores `ship`. Migration 1 to 2 turns the old `player.ship` into a fleet of one ship named after its model. The cargo validation no longer requires cargo to fit the capacity: the capacity comes from the active ship and an old save may hold more than the ship now carries, so such cargo is kept instead of the save being refused. When the main menu starts a new game, the starting ship is named before autosave begins.

## Galaxy section

The optional `galaxy` section stores the discovered system ids (`{"discovered": [...]}`). It is applied after the player so the current system is known, and a save without it defaults to Sol plus the current system. See [galaxy.md](galaxy.md).


## Reputation section

The optional `reputation` section is `{"values": {faction id: int}}` (only non-neutral factions), provided by `ReputationManager`; older saves load neutral. Contracts additionally save `reputation_change`, `reputation_applied` and `required_reputation` (optional). See [factions.md](factions.md).
