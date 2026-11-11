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
| `Contract` | `scripts/missions/contract.gd` | Runtime base class: id, title, description, origin, destination, reward, status |
| `CargoDeliveryContract` | `scripts/missions/cargo_delivery_contract.gd` | The cargo delivery type: commodity and quantity |
| `ContractSource` | `scripts/missions/contract_source.gd` | Interface: `generate(location, context, wanted, existing)` and `get_target_offers()` |
| `ProceduralContractSource` | `scripts/missions/procedural_contract_source.gd` | Invents contracts from the galaxy, see section 13 |
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

`ContractManager` asks its `ContractSource` for contracts the first time a location is used and tops the location up again every time the player docks there (section 13). The game uses the `ProceduralContractSource`; there are no hand-written contracts. Another source can be passed to `ContractManager.set_source()`; tests use `scripts/tests/support/fixed_contract_source.gd` for fixed, repeatable offers.

---

## 6. The mission computer screen

Same look and conventions as the trading screen. Left (75%): a list in three sections, **Available here**, **Active** and **Completed**, with contract, destination, cargo and reward. Right (25%): details of the selected contract (description, from, to, cargo, reward, status, progress such as `In hold: 40 / 40. Deliver to Mars`), the **Accept contract** button, and the cargo hold list. Refusals appear in red under the button. **Back** or Esc closes it, and departing closes it too.

The button on the settlement screen is enabled when the location has offers or contracts involving it. The screen reads the manager and listens to its signals; it holds no contract state.

---

## 7. Changing what is generated

Edit `resources/contracts/generation_rules.tres` (counts, mix, quantities, jump limits, wording) and `resources/contracts/reward_rules.tres` (payment). No code change is needed. See section 13.

---

## 8. Recipe: add a mission type or a generator

- **New mission type:** extend `Contract`, override `get_requirement_text()` and `get_progress_text()`, and make a source that creates it. The screen only uses the base class. Accept and completion in `ContractManager` currently handle `CargoDeliveryContract` explicitly; add the equivalent steps for the new type there (or move them into overridable methods when a second type exists).
- **Generator:** extend `ContractSource`, return new `AVAILABLE` contracts from `generate(location, context, wanted, existing)`, and call `set_source()` before the first visit.

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

No deadlines, failure or abandoning, no reputation (the issuing authority is stored for it), and no rewards other than credits. The mission screen is only reachable while docked.

## 11. Saving

Every contract (available, active, completed and failed) is saved in full with its type, ids, status and progress, together with the next contract id and the list of locations that have already created their offers. A new contract type must implement `get_type_id()`, `to_dict()`, `validate_dict()` and `load_dict()` and be added to `ContractFactory.create()`. On load, active contracts are checked against the cargo lots so they cannot disagree. See [save-system.md](save-system.md).

## 12. Exploration contracts and long-distance deliveries (Phase 2.4)

**Contract types.** `Contract` is the base; `CargoDeliveryContract` and the new `ExplorationContract` extend it. A contract may have no destination location (exploration), and every contract can say `get_type_label()`, `get_origin_text()`, `get_destination_text()` ("Mars, Sol"), `get_journey_text()` ("Sol > Sirius > Tau Ceti: 2 jumps, 41 fuel", measured from the issuer's system while on offer and from the player's system once accepted) and `get_target_system()`. They get that from a `ContractContext` (galaxy, travel and scouting state, reward rules, where the player is), which the `ContractManager` hands to every contract. Fuel in journey text is the jump cost from the galaxy map; it is not used up yet.

**Exploration.** Scout a star system: enter it and come within docking range of **every** body (planets, moons, gas giants, stations). `TravelManager` tracks the bodies reached per system (`scouted`) and announces `system_scouted`; the manager marks every accepted exploration contract for that system as `explored`. The reward is **not** paid in flight: it is paid, once, with the completion popup, when the player next lands at the issuing location (like a delivery). The map stops marking the system, and the contract's progress text says to return to the issuer. Viewing or selecting a system on the map never completes anything. Cases: an already-discovered target can still be accepted (progress already made counts); a target that is fully scouted is not offered, and a stale offer is refused ("already explored"); several contracts for one system complete together; contracts for different systems are independent; completed contracts are never considered again.

**Offers.** Contracts are generated (section 13); the old hand-written offers no longer exist.

**Towards generation.** `ContractSource.generate(location, context)` is the only seam: a procedural source would be another subclass using the context's galaxy, discovery state and reward rules (with per-location profiles of allowed types, commodity pools and distance ranges). The manager, screens, save format and rewards would not change.

**Mission computer.** Columns CONTRACT, TYPE, DESTINATION, OBJECTIVE, REWARD; details add TYPE, ISSUED AT, TARGET/TO, OBJECTIVE and JOURNEY, and progress such as "Scouted 1 of 2 bodies in Wolf 359". **Galaxy map:** systems that accepted contracts point at get a gold ring and an EXPLORE or DELIVERY label, and the info panel lists the objective. **Completion:** exploration shows an "EXPLORATION COMPLETE" popup with flavour from `resources/flavour/exploration_complete.tres`.

**Saving.** Exploration contracts save with `type: "exploration"` and `target_system`; a contract with no destination saves `destination` as "". The `galaxy` section stores `scouted_nodes`. Exploration contracts also save `explored`. A save where an accepted exploration contract's target is already scouted but which is not marked `explored` is refused as damaged, so loading can never pay out. Old saves load unchanged.

**Tests.** `exploration_test.gd` (generation, accepting, map markers, completion only by scouting, the already-discovered and multiple-contract cases, rewards once, saving, a cross-system delivery end to end) and `scouting_test.gd`.

---

## 13. Procedural contracts (Phase 2.5)

**Source.** `ProceduralContractSource` fills every inhabited location (dockable, with people) from the galaxy as it is. The numbers and wording are in `resources/contracts/generation_rules.tres` (`ContractGenerationRules`); payment is in `reward_rules.tres`. A seed makes it reproducible (`seed_rng()`, used by tests).

**Always something to take.** A mission computer is topped up to its target (4 offers) the first time it is used and **every time the player docks**; landing happens before the Mission Computer button is set, so it is enabled at every inhabited location. Accepting offers empties the list until the next landing. If the random mix yields nothing the generator falls back ferry, cargo, exploration, and a test proves every inhabited location always gets a contract. The player may still be unable to take a job (not enough cargo space); that is fine.

| Type | Rule |
|---|---|
| Cargo delivery | Goods the issuer exports (any trade good if it exports nothing) to another inhabited location owned by the **same faction** (system and location), at most 4 jumps away, usually 10-100 units; 15% are **bulk** (200-600 units of cheap goods). Destinations that import the goods are preferred. Quantity never exceeds the biggest hold of any ship. |
| Ferry passengers (`FerryContract`, type `ferry`) | 1-3 passengers (a contract lot of the non-market *Passengers* commodity, so they use cargo space but can never be sold) to any inhabited location within **3 jumps**, in the same system or another, any faction. Small, quick, early game work. |
| Exploration | Scout an uninhabited system that is not fully scouted, within 3 jumps. None are offered when there is nothing left to scout. Paid on landing at the issuer. |

The same type, destination (or target) and commodity are never offered twice at one location.

**Issuing authority.** Every contract has `authority`: `CIVILIAN` or `MILITARY` (saved as `issuing_authority`; missing in older saves = civilian) and `get_issuing_faction()` (the issuer's faction). Generated contracts are all civilian today. A reputation system can use the pair: a faction that only cares about military gain ignores civilian completions. The mission computer shows an AUTHORITY row.

**Rewards.** All in `reward_rules.tres`. Cargo has hard ceilings so the limits hold whatever the commodity: a cargo delivery under 200 units pays at most **20,000**, a bulk one (200+ units) at most **45,000**; a typical 50 unit, 4 jump run pays roughly 6,000 to 15,000. Ferries pay roughly 450 to 2,500, exploration roughly 9,000 to 13,000.

**Old saves.** Contracts already in a save stay exactly as saved (including old, larger rewards). Locations whose lists the save stored are topped up the next time the player lands there.

**Tests.** `procedural_contract_test.gd`: every inhabited location always gets a mission; the faction, distance and size rules (using a duplicated galaxy where Procyon belongs to a rival faction); reward ceilings; authority and saving; topping up on landing; old saves; the real game's buttons.
