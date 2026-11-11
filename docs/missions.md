# Mission Computer and Cargo Delivery Contracts

How contracts work, how they connect to cargo, the economy and docking, and how to add offers, mission types or a generator. For the economy see [economy.md](economy.md); for scene and data layering see [scene-inheritance-and-content.md](scene-inheritance-and-content.md).

Contents

1. [Overview](#1-overview)
2. [Structure](#2-structure)
3. [Contract cargo and the cargo hold](#3-contract-cargo-and-the-cargo-hold)
4. [Accepting and delivering](#4-accepting-and-delivering)
5. [Where contracts come from](#5-where-contracts-come-from)
6. [The mission computer screen](#6-the-mission-computer-screen)
7. [Recipe: add a contract to a location](#7-recipe-add-a-contract-to-a-location)
8. [Recipe: add a mission type or a generator](#8-recipe-add-a-mission-type-or-a-generator)
9. [Testing](#9-testing)
10. [Current limits](#10-current-limits)

---

## 1. Overview

Each inhabited location can offer cargo delivery contracts. While docked there, the player presses **MISSION COMPUTER** on the settlement screen, inspects the offers and accepts one. The issuer supplies the cargo, which takes up space in the player's hold but cannot be sold. Docking at the destination delivers it automatically and pays the reward.

---

## 2. Structure

| Piece | File | Role |
|---|---|---|
| `ContractOffer` | `scripts/resources/contract_offer.gd`, `resources/contracts/*.tres` | Static data: title, description, destination, commodity, quantity, reward |
| `Contract` | `scripts/missions/contract.gd` | Runtime base class: id, title, description, origin, destination, reward, status |
| `CargoDeliveryContract` | `scripts/missions/cargo_delivery_contract.gd` | The cargo delivery type: commodity and quantity |
| `ContractSource` | `scripts/missions/contract_source.gd` | Interface: `generate(location) -> Array[Contract]` |
| `OfferContractSource` | `scripts/missions/offer_contract_source.gd` | Turns a location's `contract_offers` into contracts |
| `ContractManager` | `scripts/missions/contract_manager.gd` | Owns available, active and completed contracts; accepts and completes them |
| `MissionComputerScreen` | `scenes/ui/mission_computer_screen.tscn`, `scripts/ui/mission_computer_screen.gd` | The interface |

`ContractManager` is a node in `main.tscn` (no Autoload), next to `Economy`. It never changes credits or cargo itself: it asks the `EconomyManager` (`load_contract_cargo`, `unload_contract_cargo`, `award_credits`), which remains the only writer of credits and cargo.

Statuses: `AVAILABLE`, `ACCEPTED`, `COMPLETED`, `FAILED`. Nothing sets `FAILED` yet (no deadlines).

---

## 3. Contract cargo and the cargo hold

There is still one `CargoHold` and one capacity. Contract cargo is stored in the same hold as separate **lots**, one per contract (`contract id -> commodity and quantity`), apart from the ordinary manifest:

- `get_used()` counts ordinary cargo and lots, so `get_free()`, `can_add()` and the HUD "used / capacity" cover both. Buying goods also respects space taken by contract cargo.
- `get_quantity(id)` and `get_manifest()` return ordinary cargo only. The trading screen's "YOU OWN", MAX SELL and `quote_sell` therefore never see contract cargo, so it cannot be sold, even at a market that imports that commodity.
- `EconomyManager.get_cargo_lines()` adds a line such as `Food (contract, Mars in the Sol system)`, so the flight HUD and trading screen list it, with its destination, with no extra UI. The text after the name is a note stored with the lot when the contract is accepted (`ContractManager` builds it; the system name comes from a lookup that `Main` provides with `set_system_lookup()`, since there is no galaxy registry yet). If the system is unknown it reads `(contract, Mars)`.

Two contracts for the same commodity are two lots and are delivered independently.

---

## 4. Accepting and delivering

**Accept** (`ContractManager.accept(contract, location)`): checked first, changed only if everything passes. Refused when the contract is no longer available, is not issued at `location`, or the quantity does not fit in the free cargo space (`AcceptResult`). On success the lot is loaded, the status becomes `ACCEPTED` and `contracts_changed` is emitted. Any number of contracts can be active while there is capacity.

**Deliver** (`ContractManager.on_docked(target)`): `Main` calls it whenever the player docks. Every active contract whose destination is that location is completed: the lot is checked and removed, the reward is paid with `award_credits` (which emits `credits_changed`, updating the HUD), the status becomes `COMPLETED`, and `contract_completed` is emitted. `Main` answers that signal with an **event popup** (see [flavour-text.md](flavour-text.md)): a "DELIVERY COMPLETE" box with a random line of flavour text from `resources/flavour/contract_delivery.tres` and the contract, cargo, destination and reward. Several deliveries at once are shown one after another. Docking anywhere else changes nothing. If a lot is missing, nothing is paid and an error is logged.

---

## 5. Where contracts come from

`ContractManager.get_available(location)` asks its `ContractSource` the first time a location is used and keeps the result, so offers are stable between visits, one-time (an accepted contract leaves the list) and have unique ids. The only source today is `OfferContractSource`, which reads fixed offers from the location's `contract_offers`. A procedural generator would be another `ContractSource` passed to `ContractManager.set_source()`; the manager and screen need no changes.

---

## 6. The mission computer screen

Same look and conventions as the trading screen. Left (75%): a list in three sections, **Available here**, **Active** and **Completed**, with contract, destination, cargo and reward. Right (25%): details of the selected contract (description, from, to, cargo, reward, status, progress such as `In hold: 40 / 40. Deliver to Mars`), the **Accept contract** button, and the cargo hold list. Refusals appear in red under the button. **Back** or Esc closes it, and departing closes it too.

The button on the settlement screen is enabled when the location has offers or contracts involving it. The screen reads the manager and listens to its signals; it holds no contract state.

---

## 7. Recipe: add a contract to a location

1. Create `resources/contracts/<name>.tres` (**ContractOffer**): `title`, `description`, `commodity`, `quantity`, `reward`, and `destination_path`, the location file to deliver to (for example `res://resources/locations/mars.tres`).
2. Add it to the issuing location's **Contract Offers** (`resources/locations/<place>.tres`).

`destination_path` is a path, not a direct reference, because locations offer contracts to each other and Godot cannot load resources that reference each other in a loop. Problems (no destination, destination equal to the issuer, zero quantity, negative reward) are reported by `InhabitedData.validate()` and invalid offers are skipped with an error.

---

## 8. Recipe: add a mission type or a generator

- **New mission type:** extend `Contract`, override `get_requirement_text()` and `get_progress_text()`, and make a source that creates it. The screen only uses the base class. Accept and completion in `ContractManager` currently handle `CargoDeliveryContract` explicitly; add the equivalent steps for the new type there (or move them into overridable methods when a second type exists).
- **Generator:** extend `ContractSource`, return new `AVAILABLE` contracts from `generate(location)`, and call `set_source()` before the first visit.

---

## 9. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/contract_test.gd
& $godot --headless --path . --script res://scripts/tests/mission_ui_smoke_test.gd
```

`contract_test.gd` covers availability and unique ids, accepting, refusals that change nothing, the shared capacity, unsellable contract cargo, several active contracts, delivery at the right and wrong location, payment, and missing cargo. `mission_ui_smoke_test.gd` plays it through the real game scene: dock at Earth, accept through the button, fly to Mars, see the delivery and the completed entry. The contract_test run logs one expected error line for its missing-cargo case.

---

## 10. Current limits

No deadlines, failure or abandoning, no saving, no refreshing or procedural offers, and no rewards other than credits. The mission screen is only reachable while docked.
