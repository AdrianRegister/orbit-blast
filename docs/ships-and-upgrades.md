# Ships, Shipyards and Upgrades

How ship models, owned ships, upgrades, shipyards and outfitters fit together, and how to add new ones. For money and cargo see [economy.md](economy.md); for saving see [save-system.md](save-system.md); for data layering see [scene-inheritance-and-content.md](scene-inheritance-and-content.md).

Contents

1. [Overview](#1-overview)
2. [Structure](#2-structure)
3. [Effective specs](#3-effective-specs)
4. [Buying ships](#4-buying-ships)
5. [Upgrades](#5-upgrades)
6. [Switching ships and cargo](#6-switching-ships-and-cargo)
7. [Services on locations](#7-services-on-locations)
8. [The screens](#8-the-screens)
9. [Recipes](#9-recipes)
10. [Saving](#10-saving)
11. [Testing](#11-testing)
12. [Current limits](#12-current-limits)

---

## 1. Overview

The player owns a **fleet** of ships and flies the **active** one. A ship is an `OwnedShip`: a reference to a shared **model** (`ShipStats`) plus its own name, installed upgrades and flags. Shipyards sell models; outfitters sell upgrades; both are configured per location. All money goes through the `EconomyManager`.

---

## 2. Structure

| Piece | File | Role |
|---|---|---|
| `ShipStats` | `scripts/resources/ship_stats.gd`, `resources/ships/*_stats.tres` | The ship **model**: id, name, description, price, sprite, base thrust, turn rate, top speed, cargo |
| `ShipType` | `scripts/resources/ship_type.gd`, `resources/ship_types/*.tres` | NPC traffic wrapper (category, spawn weight) around a `ShipStats` |
| `UpgradeDefinition` | `scripts/resources/upgrade_definition.gd`, `resources/upgrades/*.tres` | One upgrade: category, tier, price, bonuses, limit per ship |
| `OwnedShip` | `scripts/ships/owned_ship.gd` | One ship the player owns: id, model, name, upgrades, flags |
| `Fleet` | `scripts/ships/fleet.gd` | All owned ships, the active id, the id counter; its own save format |
| `ShipSpecs` | `scripts/ships/ship_specs.gd` | The numbers actually used: model base with upgrades applied |
| `ShipManager` | `scripts/ships/ship_manager.gd` | The only code that changes the fleet: buy, install, switch, rename. Also the `fleet` save section |
| `ShipResult` | `scripts/ships/ship_result.gd` | Outcome or quote: ok, message, cost, trade-in value, new ship |

`ShipManager` is a node in `main.tscn` (no Autoload). The sprite of a ship lives in its `<ship>_stats.tres` and is applied to the flying ship by `PlayerShip.apply_ship()` and to NPCs by `NpcShip`; no scene hardcodes a ship picture.

---

## 3. Effective specs

`ShipSpecs.compute(model, upgrades)` is the only place base values and upgrades are combined, so nothing derived is stored. Engine and manoeuvrability bonuses are **fractions of the model's base value** and only the best installed tier counts (tiers replace each other, they do not stack). Cargo bonuses are flat and add up. `PlayerShip.stats` is a `ShipSpecs`; NPCs fly with the model's base numbers.

---

## 4. Buying ships

`ShipManager.quote_ship(model, trade_in)` says whether a purchase is allowed and what it costs, changing nothing. `buy_ship(model, trade_in)` repeats the checks and then applies everything in one block: spend the credits, create the ship, make it active, resize the hold. A refused purchase changes nothing; a successful one spends exactly once.

Checks: the player is docked, the location's shipyard sells the model, the credits cover the price, and the current cargo (including contract cargo) fits in the new ship.

When buying, the screen asks what to do with the current ship:

- **Trade in**: the ship is removed. Its value is its model's price and is taken off the new price, but the result never drops below `ShipManager.minimum_trade_in_price` (10,000 CR), and never exceeds the new ship's own price. A ship is never free and the shipyard never pays the player.
- **Keep**: the full price is paid and the old ship stays in the fleet with the flag `PREVIOUS_SHIP`. The flag hides it from the game (`Fleet.get_visible_ships()` leaves it out) but keeps all its data. The future hangar will list these ships.

A new ship is named after its model until the player names it (up to 50 characters, trimmed, not empty). The name prompt cannot be skipped.

---

## 5. Upgrades

- **Cargo bay**: +15 cargo, `max_per_ship = 2`. The limit is data on the upgrade.
- **Engines** (tiers I, II, III): +10% / +20% / +30% top speed and acceleration.
- **Manoeuvring jets** (tiers I, II): +10% / +25% turn rate.

Tiers must be bought in order and each costs its full price. Upgrades belong to the individual ship, so they stay on it when the player switches ships. `install_upgrade` checks the same things as a purchase (docked, offered here, limit and tier, credits, cargo fits the new capacity) and changes nothing if any fails.

---

## 6. Switching ships and cargo

There is one shared cargo hold. Cargo, including contract cargo, travels with the player, and the hold's capacity always follows the active ship (`EconomyManager.set_cargo_capacity`). `ShipManager.switch_to(id)` only works while docked and refuses with an explanation if the cargo would not fit, so cargo is never lost. The UI does not offer switching yet (the hangar will); the method and its rules exist and are tested. After any change `active_ship_changed` is emitted and `Main` applies the ship to the flying `PlayerShip`.

A ship can hold more than its capacity only in one case: an old save loaded with a ship smaller than the one it was made with. The cargo is kept (never destroyed); the hold simply cannot take more until some is sold or delivered.

---

## 7. Services on locations

`InhabitedData` has two lists:

- `shipyard_ships`: the models its shipyard sells. Empty means no shipyard.
- `outfitter_upgrades`: the upgrades its outfitter offers. Empty means no outfitter.

The settlement screen enables the SHIPYARD and OUTFITTERS buttons from these lists. No logic mentions a location. Currently Earth (ships and most upgrades), Mars (upgrades only) and Victory I (ships and manoeuvring/cargo upgrades) differ so the variety is testable. Factions and reputation can later turn these lists into entries with requirements.

---

## 8. The screens

Same look and conventions as the trading screen. `ShipyardScreen` and `OutfittersScreen` list items on the left and show details on the right: description, price and a **comparison table** (`SpecComparison`: current, new, change) between the player's ship and the selected ship or upgrade. Refusals appear in red. Back or Esc closes them, and departing closes them too. `ChoicePopup` (trade in or keep) and `NamePrompt` are small modal boxes that work while the game is paused.

On a **new game** the starting shuttle is named first; the game waits (and autosave stays off) until the name is confirmed.

---

## 9. Recipes

**Add a ship model**: create `resources/ships/<name>_stats.tres` (ShipStats) with a unique `id`, name, description, price, `texture`, `display_width` (its on-screen width in pixels, independent of the sprite's size) and base numbers. To sell it, add it to a location's `shipyard_ships`. To let NPCs fly it, make a `resources/ship_types/<name>.tres` pointing at it and add that to a traffic config.

**Add an upgrade**: create `resources/upgrades/<name>.tres` (UpgradeDefinition) with a unique `id`, category, tier, price and bonuses, and add it to locations' `outfitter_upgrades`. The registry finds it by `id` automatically.

**Change prices or percentages**: edit the `.tres` files.

---

## 10. Saving

The `fleet` section stores `next_id`, the active id and every ship (`id`, `model`, `name`, `upgrades`, `flags`). It is applied after the economy so the hold takes the active ship's capacity. Save version 2 introduced it; a version 1 save is migrated into a fleet of one ship (named after the ship in the old player section, no upgrades). Cargo above the active ship's capacity is accepted when loading. See [save-system.md](save-system.md).

---

## 11. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/ship_test.gd
& $godot --headless --path . --script res://scripts/tests/ship_ui_smoke_test.gd
```

`ship_test.gd` covers specs, purchases (full price, trade-in, the 10,000 floor, kept ships), upgrades (limits, tiers, atomic failures), cargo-blocked switches and purchases, naming rules and unique ids. `ship_ui_smoke_test.gd` plays the outfitters and shipyard through the real buttons. `save_game_test.gd` covers saving the fleet and migrating a version 1 save.

---

## 12. Current limits

No hangar or fleet screens (kept ships are stored but unreachable), no per-ship cargo, no combat equipment, no running costs, no ship selling other than trade-in, and shipyard stock does not depend on faction or reputation yet. Prices and percentages are first guesses.

## 13. Factions, military ships and the ship roster

`ShipStats.faction` says which faction a model belongs to (a `Faction` resource, compared by id; the Federation is `faction_1`, in `resources/factions/federation.tres`). A model with a faction can only be bought at a shipyard of a location owned by that faction: `ShipManager.get_ships_for_sale(location)` filters the location's `shipyard_ships` by it, the shipyard screen and the settlement button use that list, and `quote_ship` refuses with "only sold by <faction>". Military ships (`ShipType.category = MILITARY`) spawn as NPC traffic but are not listed by any shipyard, so the player cannot buy them; when faction reputation exists, adding them to a Federation shipyard's list is all it takes.

Roster: Shuttle, Interceptor, Freighter, Light Frigate, Bulk Freighter (no faction), and the Federation Frigate, Cruiser and Capital Ship (`federation_` sprites; Federation, military). All eight are in `resources/traffic/default_traffic.tres`. Prices and flight numbers of the new ships are first guesses.

Space stations are now drawn from a sprite (`SpaceStation.texture`, set in `space_station.tscn`); like planets, the location's `size` is the sprite's width in pixels.