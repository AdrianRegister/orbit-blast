# System Classes, Zones, Damage and Military Value

How a star system's role, a faction's strategic geography, damage to locations and military value work. These are the foundations for the faction wars in [wars_system.md](../wars_system.md): none of them fights anything, and all of them can be read by a war simulation. For the economy they sit on, see [economy.md](economy.md); for the calendar, [game_clock.md](game_clock.md).

Contents

1. [The one-way chain](#1-the-one-way-chain)
2. [System classes](#2-system-classes)
3. [The jump graph](#3-the-jump-graph)
4. [Military value](#4-military-value)
5. [Zones and centres of power](#5-zones-and-centres-of-power)
6. [Damage and recovery](#6-damage-and-recovery)
7. [Military goods and markets](#7-military-goods-and-markets)
8. [Saving](#8-saving)
9. [Current content](#9-current-content)
10. [Tests and tools](#10-tests-and-tools)
11. [For the war system](#11-for-the-war-system)
12. [Displayed population](#12-displayed-population)

---

## 1. The one-way chain

Everything flows in one direction. Nothing later in the chain changes anything earlier, so nothing can loop or become unstable.

```
jump links (static)  ->  class (designer-set, in the table)  ->  location data
        (population, planet type, profile, specialties)
   ->  LocationEconomy: production and consumption (undamaged)
   ->  x infrastructure (damage, runtime)
   ->  system assessment: military value, production, population, importance
   ->  centres of power (use the undamaged importance)
   ->  zones: capital, core, inner, frontier
```

"Traffic" is not simulated. A system's transit is its number of jump links (and, in the design tools, how many shortest routes pass through it). A test checks that conquest and zone changes alter no location's production, consumption or population.

## 2. System classes

A **class** says what a system *is*: critical, economic centre, military centre, military output, rural or frontier. It is set by the designer and never changes while playing. A **zone** (section 5) says where a system sits relative to a faction's centres, and does change. A frontier-class system is normally in a frontier zone, but the zone can change with conquest and the class cannot.

`SystemClass` (`scripts/galaxy/system_class.gd`, one `.tres` per class in `resources/system_classes/`). Nothing in code names a class id: behaviour comes from these fields, so a new class is a new file.

| Field | Meaning |
|---|---|
| `id`, `display_name`, `description` | identity. Never change an id |
| `parent` | the class this is a kind of. `economic_centre` and `military_centre` are kinds of `critical`; `is_a(id)` walks the chain |
| `centre_of_power` | systems of this class (or a subtype) can be a centre of power; `can_be_centre()` |
| `min_links`, `requires_inhabited` | what a system must have to be of the class. Economic centres need 4 links; military centres are exempt (they are chokepoints) |
| `military_value_multiplier` | scales the military value of the system's locations |
| `max_objects` | most planets, moons and stations the system may hold (3 for ordinary systems, 6 at most) |
| generation hints | settlement and station counts, `population_scale`, `station_profile` for the generator |

**Setting a class.** Add `"class": "<id>"` to a system's row in `data/galaxy/galaxy_map.json`. The generator checks it and writes it into `galaxy.tres` (`GalaxySystem.system_class`). Read it with `Galaxy.get_system_class(id)`. (Not `get_class`: every Object has that method.) No class means an ordinary system.

**Validation** (generator `validate()` and `Galaxy.validate()`): the class exists; `SystemClass.check_system(inhabited, links)` holds; each object count fits the class limit (`StarSystem.validate(max_objects)`); each faction's `capital_system` is an inhabited system whose class can be a centre of power (`ContentRegistry`). The table's `inhabited` flag is unreliable for hand built systems, so the generator trusts their scenes (`Galaxy.validate` checks them).

## 3. The jump graph

`GalaxyGraph` (`scripts/galaxy/galaxy_graph.gd`) is plain graph analysis on an adjacency table, so it is tested on small made-up networks and used on the real galaxy with `from_galaxy()`: `degree`, `hops_from(sources, allowed)` (multi-source, over only the systems a filter allows), `components`, `articulation_points` (chokepoints) and `betweenness` (how much transit a system carries). Distances are always jumps, never map distance.

**Report tool.** `tools/system_class_report.gd` lists every inhabited system with its links, hops from the capital, transit, chokepoint flag, settlements, stations and population, and a **suggested** class. It assigns nothing: use it to choose the `class` field. The Federation network is nearly a tree (98 links for 92 systems), so almost every hub is a chokepoint; the real military centres have to be designed, ideally against another faction's border.

## 4. Military value

`MilitaryValueRules` (`resources/military/military_value_rules.tres`) turns locations into value:

```
location  = profile.military_value * size_factor + shipyard (30) + outfitter (20) + location.military_value_bonus
size_factor = clamp((population / reference) ^ 0.5, 0.25, 3.0)
system    = sum over its inhabited locations * class.military_value_multiplier
```

- `EconomyProfile.military_value` is what a kind of settlement is worth: resort 1, frontier 4, commercial 5, agricultural 8, mining 10, industrial 15, military 25, arsenal 40.
- `InhabitedData.military_value_bonus` is for designed fortresses and hubs (Elysium 60, Aegis Station 40, and so on).
- Damage lowers the **current** value by `damage_weight` (0.5), never the structural one.

`SystemAssessor` (`scripts/military/system_assessor.gd`) builds a `SystemAssessment` for any system: `military_value`, `current_military_value`, `production_value` and `consumption_value` (credits of goods a day), `population`, `infrastructure` (the share of production made now), `connectivity`, and `importance`, a weighted sum used to pick centres of power. Importance is **structural**: damage does not change it, so a raid cannot make a centre appear or vanish. The assessor takes the damage and production-scale lookups as Callables, so it knows nothing about the InfrastructureManager.

## 5. Zones and centres of power

`ZoneManager` (a node in `main.tscn`) and `ZoneRules` (`resources/zones/zone_rules.tres`). The pure calculation is `ZoneMap` (`scripts/galaxy/zone_map.gd`).

**Zones.** CAPITAL, CORE, INNER, FRONTIER (and NONE where a faction is not present):

| Rule | Default |
|---|---|
| core: up to this many jumps from a centre | 1 |
| inner: up to this many jumps | 2 in the game's rules file (the script default is 3); beyond that, frontier |
| a centre with fewer links than this projects no core | 2 |
| a system with at least this many links is promoted one zone toward the core | 4 (0 turns it off) |

**Algorithm.** A search spreads from every centre of power at once, one jump at a time, walking only through systems where the faction owns a settlement (supply lines). A system takes the nearest centre as its **region** (a tie goes to the more important centre), and its zone from the jumps. A system cut off from every centre is frontier. A contested system has a zone for each faction present.

**Centres of power.** The faction's capital (`Faction.capital_system`) while it holds it, plus every system whose class can be a centre that the faction controls outright, that scores at least `centre_min_importance` (25), and that it has held for `establish_days` (10). A system held since the start, or retaken by its starting owner, counts at once; losing control ends the centre at once. So a conquered enemy capital or critical system becomes a **mini-core** a while after the conquest, with its own region around it, and the zones of both factions redraw. If the capital is lost, the most important remaining centre acts as the capital (`relocate_capital`).

**API** (`ZoneManager`): `zone_of(system, faction)`, `zone_name_of`, `region_centre_of`, `hops_from_centre`, `centres_of(faction)`, `is_centre`, `capital_of`, plus front line data for wars: `is_border`, `hops_to_enemy`, `is_chokepoint`. The signal `zones_changed(faction_id)` fires when a faction's zones change. Zones are rebuilt when ownership or the day changes (about 90 systems, trivial).

**State.** Only `claims`: the day each system last changed hands. Everything else is derived.

## 6. Damage and recovery

`InfrastructureManager` (a node in `main.tscn`) and `InfrastructureConfig` (`resources/infrastructure/infrastructure_config.tres`). Damage is 0 (undamaged) to 1 (devastated) per location, shown as a percent. It lowers **production only**: nothing is destroyed, nobody dies, nothing is permanent.

- `apply_damage(location_id, amount, source)` (negative repairs), `set_damage`, `get_damage(id, day)`, `get_damage_percent`, `production_scale(id, day)`, `get_damaged_locations`.
- **Recovery** is linear and lazy: `damage(day) = max(0, stored - recovery_per_day * (day - stored_day))`, with `recovery_per_day` 0.02 (a devastated location is whole in 50 days). Nothing ticks, so it is identical whether the player is nearby or away. `max_production_loss` (1.0) is how much production a fully damaged location loses.
- **Markets follow it day by day.** `Market` takes a production-scale function and applies it inside each simulated day. Just before damage changes, the manager emits `damage_about_to_change`; `EconomyManager` brings that market up to date first, so the days up to now use the old rate. `LocationEconomy` stays undamaged, so a place's exports and imports do not change with damage.
- **Target panel.** A `DAMAGE` row (`35%`) appears on inhabited locations, through a second Callable on `Targetable` (`extra_rows_lookup`, set through `StarSystem` and `InhabitedNode` exactly like the owner name). The HUD refreshes it when damage changes and when a day passes. The settlement screen shows it too; the day of a landing passes before it opens, so it shows the day's figures.

## 7. Military goods and markets

Five goods, flagged `Commodity.military`: **Munitions** (130), **Armour Plating** (240), **Field Rations** (65), **Combat Medkits** (200), **Reactor Cores** (520). They are traded like any good and simulated like any good, but civilian contracts never carry them, and a future smuggling or blockade system can key on the flag.

Two profiles: **military** (garrison stations: uses all five heavily, makes none) and **arsenal** (military output: makes munitions, armour plating and reactor cores). A little is made by civilian profiles (field rations by farms, munitions and armour by industry, medkits by commercial stations) so ordinary markets can deal in them.

**No reputation or faction input anywhere.** Availability and price come from the simulation alone, so a free trader can carry munitions from an arsenal to a garrison on any side. A test checks that the economy code does not read reputation. In a war, raising a garrison's consumption (or lowering an arsenal's production through damage) moves prices without any new code.

`tools/economy_report.gd` prints made against used for every good and flags any outside 1.0 to 2.0 (rare isotopes are exempt: rare by design).

## 8. Saving

Two optional sections, both registered after the data they depend on, both with `reset_state()` for older saves:

- `infrastructure`: `{"locations": {id: {"damage": 0.35, "day": 12}}}`, only damaged locations.
- `zones`: `{"claims": {system id: {"faction": id, "day": n}}}`.

See [save-system.md](save-system.md).

## 9. Current content

- **Classes.** Economic centres: Sol, Nesre Primus, Sirius, Vega, Lalande 21185, Tau Ceti, Procyon, Kerella. Military centre: Alphara (`epsilon_eridani`). Military output: Merrynne, Bloodstone, Unin. Frontier: Nadir, Eeniar, Rimshot, Galvan, Koria. Rural: Journey's End, Sanddown, Arcturus (six links, but only two lead onward) and every other inhabited system with three or fewer links. Unclassified: Fomalhaut, Aldebaran, Archenar, Nesre Secundus, Tichel.
- **Military stations** (profile `military`): Aegis Station (Sol), Bastion Station, Citadel Platform and Styx Platform (Alphara). Elysium and Lethe are fortified (`military_value_bonus`).
- **Arsenals** (profile `arsenal`): Oceanus Station (Merrynne), Loki Platform (Bloodstone), Rhodes Platform (Unin). These systems, Kerella and Lotus (for Narcissa Port's display scale) are `locked`: they were generated once and edited by hand.
- **Kerella** grew into the hub its five links make it: Electra now holds 1.5M people, with a new planet (Tarn) and station (Kerella Junction).
- **Zones today.** With `inner_max_hops` 2 and nine centres, the inhabited systems are 1 capital, 28 core, 19 inner and 9 frontier. Nadir, Galvan and Koria are frontier; Eeniar is inner; Rimshot, Journey's End, Sanddown and Arcturus are core (each one jump from a centre). With `inner_max_hops` 3 they would be 27 inner and 1 frontier.

**Locked systems and names.** The generator never rebuilds a locked system, but it keeps the names its locations hold taken (and the pool name behind a station name), because otherwise another system would pick one and its locations and ids would change.

## 10. Tests and tools

`system_class_test`, `galaxy_graph_test`, `infrastructure_test`, `military_value_test`, `zone_map_test` (made-up networks) and `zone_manager_test` (the real galaxy with a second faction made in the test). Tools: `tools/system_class_report.gd`, `tools/economy_report.gd`.

## 11. For the war system

| A war needs | Where |
|---|---|
| how much a system or location is worth | `SystemAssessor.assess(system)` (`military_value`, `current_military_value`, `importance`) |
| what bombardment and raids do | `InfrastructureManager.apply_damage`; production falls and recovers by itself |
| where the front is | `ZoneManager.is_border`, `hops_to_enemy`, `is_chokepoint` |
| what a conquest changes | `TerritoryManager.transfer_settlement`; zones, centres and mini-cores follow |
| war demand and supply | raise a military profile's consumption; the market and prices respond |
| news | `ZoneManager.zones_changed`, `InfrastructureManager.damage_changed`, the territory signals |

Not built: wars, campaigns, operations, blockades (stopping trade), fortification strength, defenders, and what a lost capital means politically.

---

## 12. Displayed population

A location's `population` is its **economic weight**: markets, production, military value, importance and zones are all tuned around it (`reference_population` 1,000,000), so it is never rescaled to make the galaxy feel bigger. What the player *reads* is a separate, display-only figure: the real number times a scale, rounded to two significant figures and written in words. Earth keeps 8,500,000 in every calculation and reads **2.6 billion**. Nothing displayed is saved or fed back into anything.

`PopulationDisplay` (`scripts/galaxy/population_display.gd`) works out the figure from `PopulationDisplayRules` (`resources/economy/population_display_rules.tres`). The scale comes from, in order:

1. `InhabitedData.population_display_scale` on the location (Earth x300; Kerella Junction and Narcissa Port x2 to tame outliers);
2. `EconomyProfile.population_display_scale` (military stations x4, arsenals x1.5);
3. the entry for the system's class, planets and stations separately: critical (and its subtypes) planets x40, stations x10; rural planets x4, stations x8; frontier x0.5 for both;
4. the defaults (planets x4, stations x8), for unclassified systems.

A scale of 0 means "not set". Written as "2.6 billion", "320 million", "4.8 million", and full digits with commas below a million ("480,000").

| Place | Reads |
|---|---|
| Earth | 2.6 billion |
| Aries, Elysium, Persephone, Cernunnos | 320, 310, 200, 170 million |
| Aurelia, Talos, Electra, Tarn | 96, 68, 60, 36 million |
| a typical rural planet | 2 to 6 million (up to 14 million) |
| frontier places | 69,000 to 960,000 |
| Aegis, Bastion, Styx, Citadel | 320,000, 480,000, 360,000, 240,000 |
| Rhodes, Loki, Oceanus (arsenals) | 900,000, 600,000, 380,000 |

**Where it appears.** Only the POPULATION row of the target panel and the settlement screen. `Main._extra_target_rows` supplies it through the same lookup as the DAMAGE row; a lookup row now *replaces* a location row with the same caption, so the lookup's POPULATION replaces the raw one. `InhabitedData.get_rows()` itself still shows the real number (used by tests and tools). The dev tools print real populations.

**To change how big a place reads:** change a class entry, a profile scale or one location's `population_display_scale`, never `population`. A new generated system gets sensible numbers from its class automatically. `scripts/tests/population_display_test.gd` checks the tiers (Earth in the billions, core planets tens to hundreds of millions, rural planets in the millions, frontier and military places below a million) against the real data.
