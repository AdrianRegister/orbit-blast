# Trading and Economy

How buying and selling works in Orbit Blast, how the pieces relate, and how to add commodities and markets. For scene inheritance and adding planets/systems, see [scene-inheritance-and-content.md](scene-inheritance-and-content.md).

Contents

1. [Overview](#1-overview)
2. [Resource relationships](#2-resource-relationships)
3. [Runtime architecture](#3-runtime-architecture)
4. [Pricing and stock rules](#4-pricing-and-stock-rules)
5. [Transaction rules](#5-transaction-rules)
6. [The trading interface](#6-the-trading-interface)
7. [Recipe: add a commodity](#7-recipe-add-a-commodity)
8. [Recipe: configure a market for a location](#8-recipe-configure-a-market-for-a-location)
9. [Current test data](#9-current-test-data)
10. [Testing](#10-testing)
11. [Extending the system](#11-extending-the-system)

---

## 1. Overview

Any inhabited location (planet or station) can have a market. The player docks, presses **TRADING FLOOR** on the settlement screen, and buys or sells commodities.

Responsibilities are kept apart:

| Responsibility | Class | File |
|---|---|---|
| Commodity definition | `Commodity` | `scripts/resources/commodity.gd` |
| Market configuration | `MarketData`, `MarketListing` | `scripts/resources/market_data.gd`, `market_listing.gd` |
| Live market (stock, prices) | `Market` | `scripts/economy/market.gd` |
| Player money and cargo state | `PlayerData`, `CargoHold` | `scripts/resources/player_data.gd`, `scripts/economy/cargo_hold.gd` |
| Transaction processing | `EconomyManager`, `TradeQuote` | `scripts/economy/` |
| Interface | `TradingScreen` | `scripts/ui/trading_screen.gd`, `scenes/ui/trading_screen.tscn` |
| Cargo display (shared) | `CargoList` | `scripts/ui/cargo_list.gd`, `scenes/ui/cargo_list.tscn` |

---

## 2. Resource relationships

```
Commodity (.tres)  resources/commodities/       id, display_name, description, base_price, icon
     ▲
     │ referenced by
     ├──────────────────────────────┐
MarketListing (sub-resource)        │
   commodity, base_stock            │
     ▲                              │
MarketData (.tres)  resources/markets/          InhabitedData (.tres)  resources/locations/
   listings[], price/stock          ◄────────── market            exported_goods[]  (Commodity)
   multipliers, sell_price_factor               imported_goods[]  (Commodity)
```

- A **Commodity** is defined once and shared by every market, cargo hold and goods list.
- A **MarketData** lists which commodities a location deals in and their normal stock. It does *not* say whether each is imported or exported.
- The **location's `exported_goods` / `imported_goods`** (already part of `InhabitedData`) decide that. This keeps one source of truth: a good cannot be an export in the market and an import on the settlement screen.
- Planet and station scenes are untouched. The market lives entirely in `.tres` files, and `InhabitedNode` only passes the data along.
- `InhabitedData.validate()` rejects a good that is both imported and exported, and reports problems in the market data (such as the same commodity listed twice).

---

## 3. Runtime architecture

```
main.tscn
 ├── Economy          (EconomyManager)   owns live markets; the only code that changes money/cargo/stock
 ├── SettlementScreen                    emits trading_requested
 ├── TradingScreen                       asks Economy for quotes; calls buy()/sell()
 └── Hud                                 shows credits (Economy.credits_changed) and the cargo list (Economy.cargo_changed)

Main (composition root) owns PlayerData { credits, cargo: CargoHold, ship_stats }
```

- `Main` creates `PlayerData` once, sets `credits` from its exported `starting_credits` (500,000) and `cargo.capacity` from `ShipStats.cargo_capacity` (500), then calls `Economy.setup(player_data)`. Nothing recreates these, so credits and cargo persist when docking, undocking and (later) changing star systems.
- `EconomyManager.get_market(location_data)` builds a `Market` the first time a location is visited and returns the same one afterwards, so stock changes persist. It returns `null` for a location without a `market`.
- There are no Autoloads. `Main` wires the nodes together with signals:

| Signal | Emitted by | Used by |
|---|---|---|
| `credits_changed(credits)` | `EconomyManager` | HUD credits; trading screen |
| `cargo_changed` | `EconomyManager` (from `CargoHold.changed`) | HUD cargo list (via `Main`); trading screen |
| `market_changed(market)` | `EconomyManager` (from `Market.changed`) | trading screen |
| `transaction_completed(quote)` | `EconomyManager` | available for future systems (stats, events) |
| `trading_requested` | `SettlementScreen` | `Main`, which opens `TradingScreen` |

Trading is not a separate game state. The game stays `DOCKED`; the trading screen is a layer above the settlement screen, and departing (or `Back`/Esc) closes it.

---

## 4. Pricing and stock rules

All rules live in `Market`, with tunable numbers in each `MarketData`.

| Role of the commodity at this location | Buy price (player pays) | Starting stock | Player may sell here? |
|---|---|---|---|
| **Exported** | `base_price × export_price_multiplier` (0.75) | `base_stock × export_stock_multiplier` (1.5) | No |
| **Imported** | `base_price × import_price_multiplier` (1.3) | `base_stock × import_stock_multiplier` (0.4) | **Yes** |
| Listed, neither | `base_price` | `base_stock` | No |
| Not listed | not available | n/a | No |

- **Sell price** (what the market pays) is `buy price × sell_price_factor` (0.9). The 10% spread means you cannot profit by buying and selling in the same place.
- Prices are rounded to whole credits with a minimum of 1.
- Only a location's **imports** are accepted from the player.
- Because exports are cheap and imports pay well, a profitable route exists whenever one location exports what another imports.

The defaults above are the `MarketData` field defaults. Each market can override them in the Inspector.

---

## 5. Transaction rules

`EconomyManager` is the only way to trade. Each trade is first **quoted**, a check that changes nothing, and is applied only if the quote is valid. A trade either happens completely or not at all.

**Buy** is refused (in this order) when:

1. The quantity is below 1.
2. The commodity is not listed at this market.
3. The quantity exceeds the market's stock.
4. The total cost exceeds the player's credits.
5. The quantity exceeds the free cargo space.

**Sell** is refused when:

1. The quantity is below 1.
2. The market does not accept the commodity (not an import).
3. The quantity exceeds what the player is carrying.

A successful trade updates credits, cargo and market stock, then emits `credits_changed` and `transaction_completed`.

`quote_buy()` / `quote_sell()` return a `TradeQuote` (`is_ok()`, `reason`, `get_message()`, `quantity`, `unit_price`, `total`). The interface uses these to show the total before the player confirms.

---

## 6. The trading interface

Open it with **TRADING FLOOR** on the settlement screen. The button is disabled for locations with no market. `Back` or Esc returns to the settlement screen.

- **Header:** location name.
- **Summary:** credits.
- **Cargo hold panel** (right of the table): `USED n / capacity` and one line per commodity carried with its quantity, sorted by name, or `EMPTY`. It lists everything in the hold, not just goods this market trades, and updates after every trade.
- **Table:** commodity, stock, buy price, sell price (`--` when the market will not accept it), and quantity owned. Select a row to trade it.
- **Trade panel:** a quantity box (with **MAX BUY** and **MAX SELL**), then separate **BUY** and **SELL** rows. Each shows the total cost or revenue for the entered quantity, or, in red, why it is not allowed. The button is disabled while refused.
- **Status line:** the result of the last trade.

The trade panel is raised 75px from the bottom edge (the bottom margin of the screen's `Margin` node is 99). Change `margin_bottom` there to move it.

The screen reads quotes and calls `buy()` / `sell()`; it owns no game state and refreshes from the economy's signals.

### 6.1 The cargo list

`CargoList` is one reusable scene used in two places, so the displays always agree:

| Where | Node | Fed by |
|---|---|---|
| Flight HUD, below velocity and weapon, above the target panel | `Hud/Panel/Layout/CargoPanel/CargoList` | `Main._update_cargo_hud()` on `EconomyManager.cargo_changed`, through `Hud.set_cargo()` |
| Trading screen, right-hand panel | `TradingScreen/.../CargoList` | `TradingScreen._refresh()` |

It is purely presentational: `set_cargo(used, capacity, lines)` where `lines` is an Array of `[display_name, quantity]` pairs. Use `EconomyManager.get_cargo_lines()` to get them.

The hold stores only commodity ids, so `EconomyManager` remembers every `Commodity` it has seen (from each market it builds and from purchases) to turn ids into names. An id with no known commodity is shown as the raw id. Saving and loading will need a proper commodity lookup, such as a registry built from `resources/commodities/`.

---

## 7. Recipe: add a commodity

1. In the FileSystem dock, right-click `resources/commodities/` → **New Resource…** → **Commodity**, and save it (for example `medicine.tres`).
2. Fill in:
   - `id`: unique and stable, lower case (`medicine`). It is the key in cargo and stock, so never change it later.
   - `display_name`, `description`.
   - `base_price`: credits before any market adjustment.
   - `icon`: optional.

Or write the file by hand:

```ini
[gd_resource type="Resource" script_class="Commodity" format=3]

[ext_resource type="Script" path="res://scripts/resources/commodity.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"medicine"
display_name = "Medicine"
description = "Pharmaceuticals and medical supplies."
base_price = 180
```

A new commodity does nothing until a market lists it (next section). No code changes are needed.

---

## 8. Recipe: configure a market for a location

Example: give Venus a market. Venus is a `PlanetData` at `resources/locations/venus.tres`.

### Step 1: Decide what the location exports and imports

Set `exported_goods` and `imported_goods` on the location's data resource, as `Commodity` resources (they must not overlap).

### Step 2: Create the market

Right-click `resources/markets/` → **New Resource…** → **MarketData**, save it as `venus_market.tres`. In the Inspector, add entries to `listings`; each is a **MarketListing** with a `commodity` and a `base_stock`. List every commodity the location should deal in, including exports, imports and any extra goods that are only for sale.

Optionally tune `export_price_multiplier`, `import_price_multiplier`, `sell_price_factor` and the stock multipliers for this market only.

By hand:

```ini
[gd_resource type="Resource" script_class="MarketData" format=3]

[ext_resource type="Script" path="res://scripts/resources/market_data.gd" id="1"]
[ext_resource type="Script" path="res://scripts/resources/market_listing.gd" id="2"]
[ext_resource type="Resource" path="res://resources/commodities/food.tres" id="c0"]
[ext_resource type="Resource" path="res://resources/commodities/medicine.tres" id="c1"]

[sub_resource type="Resource" id="listing_0"]
script = ExtResource("2")
commodity = ExtResource("c0")
base_stock = 200

[sub_resource type="Resource" id="listing_1"]
script = ExtResource("2")
commodity = ExtResource("c1")
base_stock = 80

[resource]
script = ExtResource("1")
listings = Array[ExtResource("2")]([SubResource("listing_0"), SubResource("listing_1")])
```

### Step 3: Assign it

Set the `market` property of the location's data resource (`venus.tres`) to `venus_market.tres`:

```ini
market = ExtResource("market")
```

Each location should have its **own** market file. If two locations shared one, they would still have separate live stock (stock is kept per location), but they would share the same listings and tuning.

### Checking your work

Run the project. Warnings (such as a good that is both imported and exported, or a commodity listed twice) appear in the Output panel when the location loads.

---

## 9. Current test data

Base prices: Food 50, Electronics 220, Ore 80, Machinery 150, Fuel 60.

| Location | Exports | Imports | Listed but neither |
|---|---|---|---|
| Earth | Food, Electronics | Ore, Machinery | none |
| Mars | Ore | Food, Fuel | Machinery |
| Victory I | Fuel | Electronics, Machinery | none |

Examples of the resulting prices: Food costs 38 at Earth (export) and 65 at Mars (import); Ore costs 60 at Mars (export) and 104 at Earth (import), so Ore bought at Mars and sold at Earth pays about 94 per unit. Earth does not list Fuel and Victory I does not list Food, so not every commodity is available everywhere.

Development starting values: 500,000 credits (`starting_credits` on the `Main` node) and 500 cargo capacity (`cargo_capacity` in `resources/ships/shuttle_stats.tres`).

---

## 10. Testing

Two headless scripts cover the rules and the real scene:

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/economy_test.gd
& $godot --headless --path . --script res://scripts/tests/trading_ui_smoke_test.gd
```

- `economy_test.gd` checks independent markets, price and stock differences, buying and selling effects, each refusal (credits, cargo space, stock, cargo owned, not accepted, invalid quantity), and that refused trades change nothing.
- `trading_ui_smoke_test.gd` loads `main.tscn`, docks at Earth, opens the trading screen, buys through the buttons, and checks the HUD credits, the feedback text, and that cargo persists after departing.

Both exit with code 1 if a check fails. The smoke test also checks that the HUD and trading screen cargo lists show what was bought. Godot prints "leaked at exit" warnings after headless script runs; these come from running scripts without the full engine shutdown and are not game errors.

Layout and appearance cannot be judged headless, so check the screen visually by running the project.

---

## 11. Extending the system

The structure leaves clear places for the planned features:

| Feature | Where it goes |
|---|---|
| Dynamic prices, supply and demand, scarcity | `Market.get_buy_price()` / `get_sell_price()` and stock changes in `Market`. UI and `EconomyManager` need no changes |
| Stock regeneration | A timer or tick that calls `Market.add_stock()`; `market_changed` refreshes the UI |
| Economic events | Change a market's `MarketData` multipliers or call `Market` methods; listen to `transaction_completed` for reactions |
| Trade routes | Read `Market` prices through `EconomyManager.get_market()`; no storage changes needed |
| Saving the game | `PlayerData` (`credits`, `cargo.get_manifest()`) and each `Market`'s stock are the state to serialise |
| Reputation or taxes | Adjust the total inside `EconomyManager.quote_buy()` / `quote_sell()` |


Contract cargo (see [missions.md](missions.md)) is held in the same `CargoHold` as separate lots: it counts toward capacity and appears in the cargo list as "<Name> (contract, <Place> in the <System> system)", but `get_quantity()` ignores it, so it can never be sold.

Credits, cargo (including contract lots) and the stock of every visited market are saved and restored by `EconomyManager.save_state()` / `load_state()`; prices are not saved because they are recomputed from the static data and the stock. See [save-system.md](save-system.md).

## Ships and upgrades

Ship and upgrade purchases use `EconomyManager.try_spend(amount)` (checks the balance, then deducts and emits `credits_changed`), so there is one wallet. The hold's capacity is set from the active ship with `EconomyManager.set_cargo_capacity()`. See [ships-and-upgrades.md](ships-and-upgrades.md).

## Passengers (Phase 2.5)

`passengers` is a commodity only so that ferry contracts can carry people as contract cargo. It has no price, is in no market and cannot be traded.

## New commodities (Phase 2.4)

Medical Supplies, Luxury Goods, Industrial Chemicals, Rare Isotopes and Water were added (`resources/commodities/`), traded at Earth, Mars and Victory I (their export and import lists and market listings were extended) and used by the new delivery contracts. See [missions.md](missions.md).