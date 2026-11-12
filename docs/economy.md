# Trading and Economy

How buying and selling works in Orbit Blast, how a settlement's goods, stock and prices follow from its population and planet type, and how to change them. For scene inheritance and adding planets/systems, see [scene-inheritance-and-content.md](scene-inheritance-and-content.md). For the calendar that moves stock, see [game_clock.md](game_clock.md).

Contents

1. [Overview](#1-overview)
2. [The economic model](#2-the-economic-model)
3. [Stock over time](#3-stock-over-time)
4. [Prices](#4-prices)
5. [Transaction rules](#5-transaction-rules)
6. [Runtime architecture](#6-runtime-architecture)
7. [The trading interface](#7-the-trading-interface)
8. [Recipes](#8-recipes)
9. [Saving](#9-saving)
10. [Testing and tuning](#10-testing-and-tuning)
11. [Extending the system and war hooks](#11-extending-the-system-and-war-hooks)

---

## 1. Overview

Every inhabited, dockable location (a planet or station with people) has a market. Nothing about a market is authored by hand. What a settlement **makes** and **uses** each day is worked out from its **population** and its **economy profile** (which comes from its planet type). Those daily flows drive its **stock**, and stock drives **prices**. Change a population or a planet type in a `.tres` and its goods, stock limits and prices follow.

| Responsibility | Class | File |
|---|---|---|
| Commodity definition | `Commodity` | `scripts/resources/commodity.gd` |
| Kinds of economy | `EconomyProfile`, `EconomyProfileGood` | `scripts/resources/economy_profile.gd`, `economy_profile_good.gd` |
| Tunable numbers | `EconomyConfig` | `scripts/resources/economy_config.gd`, `resources/economy/economy_config.tres` |
| Daily flows of a settlement | `EconomyModel`, `LocationEconomy` | `scripts/economy/economy_model.gd`, `location_economy.gd` |
| Live market (stock, prices) | `Market` | `scripts/economy/market.gd` |
| Calendar | `GameClock` | `scripts/time/game_clock.gd` |
| Damage to locations | `InfrastructureManager` | `scripts/economy/infrastructure_manager.gd` |
| Player money and cargo | `PlayerData`, `CargoHold` | `scripts/resources/player_data.gd`, `scripts/economy/cargo_hold.gd` |
| Transactions | `EconomyManager`, `TradeQuote` | `scripts/economy/` |
| Interface | `TradingScreen` | `scripts/ui/trading_screen.gd` |

---

## 2. The economic model

`EconomyModel.compute(location)` returns a `LocationEconomy`: for every commodity, units **produced** and units **consumed** per day.

```
ratio       = max(population / reference_population, min_scale)
scale_made  = ratio ^ production_exponent      (0.9: big worlds make slightly less per person)
scale_used  = ratio ^ demand_exponent          (1.0: people eat in proportion)

production(good)  = profile.production(good) * scale_made
consumption(good) = profile.industrial_demand(good) * scale_made
                    + commodity.civilian_demand * scale_used
```

- **Profile** (`EconomyProfile`, `resources/economy/profiles/*.tres`): which goods a kind of settlement makes (`production`) and which its industry burns (`industrial_demand`), in units per day for a settlement of the reference population (1,000,000). Profiles today: agricultural, industrial, mining, commercial, resort, frontier, military and arsenal (the last two are for war: see [system_classes.md](system_classes.md)).
- **Which profile a location gets:** its own `InhabitedData.economy_profile` if set; otherwise its planet type's `PlanetType.economy_profile`; otherwise (stations) `EconomyConfig.station_profile` (commercial). `PlanetData.get_economy_profile()` does the lookup.

| Planet type | Profile |
|---|---|
| terrestrial, jungle, ocean | agricultural |
| desert | industrial |
| rocky, moon | mining |
| arctic | frontier |
| resort | resort |
| gas giants | none (cannot be landed on) |

- **Civilian demand** (`Commodity.civilian_demand`): units per day per million people, for goods every settlement needs (food, water, fuel, medical supplies, electronics, luxury goods). It is why a mining world must import food.
- **Exports and imports are derived.** A good is an *export* when production beats consumption by more than `balance_threshold` (10%) of the larger of the two, an *import* when it falls short by that much. In between, the place is self-sufficient. `LocationEconomy.exports()` / `imports()` feed the settlement screen, the galaxy map, and contract generation.
- **Specialties.** A location's own `exported_goods` / `imported_goods` lists are *specialties*, applied on top of the model so hand-built places keep their identity. A listed export makes at least `specialty_export_flow` units a day (scaled by population) and at least `specialty_export_margin` times what the place uses; a listed import stops being produced and is consumed at least `specialty_import_flow`. Generated locations have no specialty lists and are purely derived.
- **Minimum size.** `min_scale` (0.02) stops tiny outposts shrinking to nothing: below a population of 20,000 the rates stop falling.
- **Not an economy:** an uninhabited or undockable place has none (`LocationEconomy.has_economy()` is false) and no market.

`EconomyModel.of(location)` caches the result and recomputes it when the population, profile or specialty lists change. `EconomyModel.shared()` is the model built from the game's own config and every commodity, for code that is not handed one.

---

## 3. Stock over time

Each `Market` keeps a floating-point stock per good and the **last day** it was brought up to date. Nothing runs on a timer. On any read (stock, price, quote, save), the market first catches up to the calendar's day by running the daily rule once per missing day. A market nobody visits costs nothing, and the result does not depend on when or how often it was read (a test checks that reading every day equals reading once after 60 days).

Per day, per good (`capacity = max(production, consumption, min_flow) * cover_days`):

```
made    = production  * (1 - stock / capacity)          production slows as the warehouse fills
used    = consumption * min(1, stock / (consumption * reserve_days))   consumers go short when stock is low
freight = max(consumption - production, 0) * ambient_share * (1 - stock / normal)   background supply while short of normal
stock  += made + freight - used          (never below 0)
```

- A new market runs `warmup_days` (90) of this from empty, so it starts at a natural level.
- **Damage.** A location's production is multiplied each day by the share it makes that day (`InfrastructureManager.production_scale`, 1.0 undamaged). The market is given a production-scale function and uses it inside each simulated day, so damage and its recovery are followed day by day however the market is read. Before damage changes, the market is brought up to date (`Market.catch_up()`), so earlier days use the old rate. Only production is scaled: capacity, normal stock, consumption and the exports and imports lists are not, so prices stay comparable. See [system_classes.md](system_classes.md).
- **Dumping goods:** a large sale puts stock above capacity, production stops, and the surplus is used up only at the consumption rate, so a big dump into a small market depresses prices for a long time, and into a large market barely matters.
- **Emptying a market:** buying everything leaves stock at zero; local production and freight refill it.
- **Time away:** the player may be elsewhere for any number of days; the market catches up (at most `max_sync_days`, by which point it has settled) the next time it is read.
- Rates are never rounded; display uses whole units (`Market.get_stock()` floors).

---

## 4. Prices

```
normal = max(production, consumption, min_flow) * target_cover_days
ratio  = stock / normal
factor = clamp(max(ratio, min_supply_ratio) ^ -price_exponent, min_price_factor, max_price_factor)
price  = base_price * factor
```

- `ratio` 1 is normal and costs the base price. Scarcity raises the price (up to `max_price_factor`, 2x); a glut lowers it (down to `min_price_factor`, 0.5x).
- The market **charges** `price * (1 + spread/2)` and **pays** `price * (1 - spread/2)`, so buying and selling back at the same place always loses money.
- **Trades move the price.** A quote prices each unit at the stock left after the one before (`Market.buy_total()`, `sell_total()`), so `TradeQuote.unit_price` is the *average* and a large order costs more per unit than a small one. `get_buy_price()` / `get_sell_price()` give the price of the next single unit.
- A market takes **any good it deals in**, so a producer will buy its own export, at a poor price. It refuses and does not sell goods it neither makes nor uses.

Typical positions: an exporter sits above normal (cheap), an importer below it (dear), a self-sufficient good near the base price. A route from an exporter to an importer is where the profit is.

---

## 5. Transaction rules

`EconomyManager` is the only way to trade. Each trade is first **quoted**, a check that changes nothing, and is applied only if the quote is valid.

**Buy** is refused (in this order) when: the quantity is below 1; the market does not deal in the commodity; the quantity exceeds the stock; the total cost exceeds credits; the quantity exceeds free cargo space.

**Sell** is refused when: the quantity is below 1; the market does not deal in the commodity; the quantity exceeds what the player carries.

A successful trade updates credits, cargo and market stock and emits `credits_changed` and `transaction_completed`. `TradeQuote` carries `quantity`, `unit_price` (average), `total`, `reason` and `get_message()`.

---

## 6. Runtime architecture

```
main.tscn
 ├── Clock            (GameClock)        the calendar day
 ├── Economy          (EconomyManager)   owns live markets; changes money/cargo/stock
 ├── SettlementScreen                    emits trading_requested
 ├── TradingScreen                       asks Economy for quotes; calls buy()/sell()
 └── Hud                                 credits and cargo list
```

- `Main` creates `PlayerData` and calls `Economy.setup(player_data, clock)`. There are no Autoloads.
- `EconomyManager.get_market(location)` builds a `Market` the first time a location is visited (from `EconomyModel`) and returns the same one afterwards. It returns `null` for a place with no economy.
- `EconomyManager.get_model()` returns the model, for tools and later systems.

| Signal | Emitted by | Used by |
|---|---|---|
| `credits_changed(credits)` | `EconomyManager` | HUD credits; trading screen |
| `cargo_changed` | `EconomyManager` | HUD cargo list; trading screen |
| `market_changed(market)` | `EconomyManager` (from `Market.changed`) | trading screen |
| `transaction_completed(quote)` | `EconomyManager` | autosave; available for future systems |
| `trading_requested` | `SettlementScreen` | `Main` |

Trading is not a separate game state. The trading screen is a layer above the settlement screen.

---

## 7. The trading interface

Open it with **TRADING FLOOR** on the settlement screen (disabled where nobody lives). The table lists every good the market deals in, sorted by id:

| Column | Shows |
|---|---|
| COMMODITY, IN STOCK | the good and whole units in stock |
| SUPPLY | **Scarce / Low / Normal / Plentiful / Glut**, coloured (`Market.get_supply_level()`; limits are the "Supply labels" in `EconomyConfig`). An importer usually reads Low, an exporter Plentiful |
| BUY PRICE, SELL PRICE | the price of the next single unit |
| VS BASE PRICE | how far today's price is from the commodity's base price (`Market.get_price_factor()`); green is cheap, orange is dear |
| YOU OWN | quantity in the hold |

**MAX BUY** asks the market what the credits buy (`Market.max_buyable()`), taking the rising price into account. The selected good's supply is repeated beside its name in the trade panel, and the BUY and SELL rows show the total for the entered quantity plus, for more than one unit, the average price per unit and how far it is from the first unit's price (the slippage). The BUY and SELL rows show the total for the entered quantity or, in red, why it is refused.

The screen reads quotes and calls `buy()` / `sell()`; it owns no state. `CargoList` shows the hold on both the HUD and this screen.

---

## 8. Recipes

### Add a commodity

Create `resources/commodities/<id>.tres` (`id`, `display_name`, `description`, `base_price`, optional `civilian_demand`) and add the commodity to the profiles that make or use it (`EconomyProfileGood`). It appears in the markets of every settlement whose profile or people involve it. A commodity with `base_price = 0` (passengers) is never traded. Set `military = true` on goods of war: civilian contracts never carry them.

### Change what a settlement makes

- Edit its `population` or `planet_type`. Everything follows.
- Or give it its own `economy_profile` (for example Earth is commercial although it is a terrestrial planet).
- Or list `exported_goods` / `imported_goods` for a specialty.

### Add or change a profile

Add a file to `resources/economy/profiles/` with `id`, `display_name` and a list of `EconomyProfileGood` (commodity, `production`, `industrial_demand` per day at 1M people), then point a planet type or location at it. Run `tools/economy_report.gd` to see the effect on the whole galaxy.

### Tune the numbers

Everything about stock limits, the price curve and the spread is in `resources/economy/economy_config.tres`.

---

## 9. Saving

`EconomyManager.save_state()` saves credits, cargo and, for each **visited** market, its stock and the day it was brought up to (`{"stock": {id: units}, "day": n}`). Prices are not saved. Unvisited markets are recreated deterministically from the data. The clock is its own section and loads first.

Older saves (whole-number stock, an `extra` object, no `day`) still load: a market with no saved day starts from today, and stock of goods the market no longer deals in is ignored. See [save-system.md](save-system.md).

---

## 10. Testing and tuning

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/economy_model_test.gd </dev/null
& $godot --headless --path . --script res://scripts/tests/market_sim_test.gd </dev/null
& $godot --headless --path . --script res://scripts/tests/economy_save_test.gd </dev/null
& $godot --headless --path . --script res://scripts/tests/economy_test.gd </dev/null
& $godot --headless --path . --script res://scripts/tests/trading_ui_smoke_test.gd </dev/null
```

- `economy_model_test.gd`: flows scale with population, profiles decide exports and imports, planet type and profile overrides, specialties, no economy where nobody lives, caching.
- `market_sim_test.gd`: starting stock, catching up lazily and identically however often it is read, a glut being used up at the consumption rate, buying a market out, the price curve, the spread, per-unit pricing, and no profit from a round trip.
- `economy_save_test.gd`: round trip through JSON, markets following the calendar after a load, older saves, damaged data.
- `economy_test.gd`, `trading_ui_smoke_test.gd`: the trading rules and the real scene.

**Balance report:** `tools/economy_report.gd` prints every settlement's derived exports and imports, how many settlements export and import each good, and the galaxy-wide total made versus used per good. Keep each good's total made at or above what is used (roughly 1.0 to 2.0 times).

---

## 11. Extending the system and war hooks

The structure leaves clear places for the war system (see `wars_system.md`). These are **not built yet**:

| Feature | Where it goes |
|---|---|
| War demand (more military production) | **Not built.** A per-location, per-good consumption or production multiplier applied in `Market._step_day()`. Raise military goods' consumption at military profile settlements |
| Blockade | **Not built.** Stop background freight and refuse trade at a market; a new `TradeQuote.Reason` |
| Bombardment, infrastructure raids | **Built (the foundation):** `InfrastructureManager.apply_damage()` lowers a location's production and it recovers by itself; see [system_classes.md](system_classes.md) |
| Faction differences | Emerge from the locations a faction owns: sum `LocationEconomy` over the settlements `TerritoryManager` says it holds |
| Reputation or taxes | Adjust the total inside `EconomyManager.quote_buy()` / `quote_sell()` |

Whenever a market's inputs change, call the market's catch-up first (any read does it), so the days before the change use the old rates.

Contract cargo (see [missions.md](missions.md)) is held in the same `CargoHold` as separate lots: it counts toward capacity but `get_quantity()` ignores it, so it can never be sold.

## Ships and upgrades

Ship and upgrade purchases use `EconomyManager.try_spend(amount)`, so there is one wallet. The hold's capacity is set from the active ship with `EconomyManager.set_cargo_capacity()`. See [ships-and-upgrades.md](ships-and-upgrades.md).

## Passengers

`passengers` is a commodity only so that ferry contracts can carry people as contract cargo. It has no price, is in no market and cannot be traded.
