# Scene Inheritance and Adding Planets / Systems

This document explains how Orbit Blast uses Godot's **scene inheritance** and **custom Resources** to build star systems and the objects inside them, and gives step-by-step recipes for adding new planets, stations, planet types and star systems.

Contents

1. [Core idea](#1-core-idea)
2. [Scene inheritance in this project](#2-scene-inheritance-in-this-project)
3. [Script inheritance](#3-script-inheritance)
4. [Data inheritance (Resources)](#4-data-inheritance-resources)
5. [How the pieces connect at runtime](#5-how-the-pieces-connect-at-runtime)
6. [Recipe: add a planet to an existing system](#6-recipe-add-a-planet-to-an-existing-system)
7. [Recipe: add a new planet type](#7-recipe-add-a-new-planet-type)
8. [Recipe: add a space station](#8-recipe-add-a-space-station)
9. [Recipe: create a new star system](#9-recipe-create-a-new-star-system)
10. [Recipe: add a new kind of object](#10-recipe-add-a-new-kind-of-object)
11. [Validation and troubleshooting](#11-validation-and-troubleshooting)
12. [Quick reference](#12-quick-reference)

---

## 1. Core idea

Content is split into three layers, so adding content rarely requires writing code:

| Layer | What it holds | Where it lives |
|-------|---------------|----------------|
| **Scene** (`.tscn`) | Structure and *placement*: which nodes exist, where objects sit in a system | `scenes/` |
| **Script** (`.gd`) | Shared *behaviour* | `scripts/` |
| **Resource** (`.tres`) | Per-instance *data*: name, faction, population, goods, size, sprite | `resources/` |

The rule of thumb:

- **Position** belongs to the **system scene** (the object's `position`).
- **Identity and statistics** belong to a **`.tres` data resource**.
- **Appearance and behaviour** belong to the **object scene and script**, and are shared by every instance.

This is why one `planet.tscn` serves Earth, Mars and every future planet.

---

## 2. Scene inheritance in this project

Godot has two ways to reuse a scene: **instancing** (placing a scene as a child node of another) and **inheritance** (creating a new scene that *extends* another and inherits its whole node tree). This project uses both.

### 2.1 How to recognise each in a `.tscn` file

```ini
# Instancing: a child node whose source is another scene
[node name="Targetable" parent="." instance=ExtResource("2")]

# Inheritance: the ROOT node has no `type`, only `instance=`
[node name="Planet" instance=ExtResource("1")]
```

A root node written with `instance=` (and no `type=`) means "this scene inherits from that scene". In the editor, use **Scene → New Inherited Scene…** to create one.

### 2.2 The inheritance trees

**Space objects** (things placed in a system that the player can select and dock with):

```
targetable.tscn             Area2D component: click area + selection brackets + HUD info
        ▲ (instanced as child "Targetable")
inhabited_node.tscn         Node2D  [inhabited_node.gd]  + Targetable child
        ├── planet.tscn          inherits inhabited_node.tscn  [planet.gd]  + Sprite2D
        └── space_station.tscn   inherits inhabited_node.tscn  [space_station.gd]
```

**Star systems:**

```
star_system.tscn            Node2D [star_system.gd]
        │                     ├── Background (NearStars, DistantStars parallax)
        │                     ├── Objects   ← planets/stations go here
        │                     ├── Ships     ← NPC ships (added at runtime)
        │                     └── Traffic   ← TrafficManager; see npc-traffic.md
        └── sol_system.tscn      inherits star_system.tscn, adds Earth, Mars, Victory I
```

**Composition root** (not inherited, only assembled):

```
main.tscn
  ├── StarSystem   (instance of sol_system.tscn)
  ├── PlayerShip   (instance of player_ship.tscn)
  ├── Camera2D
  ├── Targeting / GameState / Docking   (manager nodes)
  ├── Hud
  └── SettlementScreen
```

### 2.3 What inheritance gives you

An inherited scene:

- **Keeps** every node, property and script of its parent.
- **Can add** new nodes (e.g. `planet.tscn` adds a `Sprite2D`; `sol_system.tscn` adds planets under `Objects`).
- **Can override** properties and the root script (`planet.tscn` replaces the root script with `planet.gd`; `sol_system.tscn` sets `system_name`).
- **Picks up changes** made later to the parent automatically. Add a node to `star_system.tscn` and every system gets it.

Note how `sol_system.tscn` adds children *into a node it inherited*:

```ini
[node name="Earth" parent="Objects" index="0" instance=ExtResource("2")]
position = Vector2(-700, -250)
data = ExtResource("4")
```

`parent="Objects"` refers to the `Objects` node that exists only because `star_system.tscn` defines it.

### 2.4 Why `Targetable` is a component, not a base class

Targeting is an **instanced child scene** rather than an inherited base, because Godot allows only one base class per node. Ships are `CharacterBody2D`, planets are `Node2D`; neither can also *be* an `Area2D`. Making `Targetable` a child lets any object type become selectable by instancing it and calling `configure(...)`. The `TargetingManager` and `DockingManager` only ever talk to `Targetable`, so they know nothing about planets or stations.

---

## 3. Script inheritance

Scene inheritance is paired with matching script inheritance:

```
Node2D
 └── SpaceObject        (space_object.gd)      wires the Targetable; virtual getters
      └── InhabitedNode (inhabited_node.gd)    adds `data: InhabitedData`, validation, dock range
           ├── Planet        (planet.gd)       sprite from data.planet_type.texture, round click area
           └── SpaceStation  (space_station.gd) code-drawn placeholder visual
```

### 3.1 `SpaceObject`: the virtual getters

`SpaceObject` owns the connection to the `Targetable` child and pushes information into it in `_ready()`. Subclasses customise it by overriding small `_get_*` methods:

| Override | Purpose | Default |
|----------|---------|---------|
| `_get_object_name()` | Name shown in HUD | node name |
| `_get_object_type()` | `ObjectType` enum value (`PLANET`, `STATION`) | `PLANET` |
| `_get_target_bounds()` | Visual size in px (click area + selection box) | `64 × 64` |
| `_is_target_round()` | Circle (true) or box (false) click area | `false` |
| `_get_target_details()` | `TargetDetails` for the HUD rows | `null` |
| `_get_dock_range()` | Docking distance; `0` = automatic | `0.0` |
| `_type_label()` | HUD type text, e.g. `"Planet (Terrestrial)"` | enum name |

### 3.2 `InhabitedNode`: data-driven behaviour

`InhabitedNode` adds `@export var data: InhabitedData` and implements the getters from that data: name from `data.display_name`, HUD rows from `data`, dock range from `data.docking_range`. In `_ready()` it also calls `data.validate()` and reports problems with `push_error`.

### 3.3 `Planet` and `SpaceStation`: only the visual differs

- **`Planet`** requires a `PlanetData`. It reads `data.planet_type.texture` into its `Sprite2D` and scales it so the sprite's width equals `data.size` pixels. It is round for click detection.
- **`SpaceStation`** draws itself in code (`_draw()`), sized from `data.size`. It has no texture requirement and works with plain `InhabitedData`.

When overriding `_ready()`, always call `super()` so the parent's setup (including the Targetable wiring) still runs.

---

## 4. Data inheritance (Resources)

Static data is stored in custom `Resource` classes that also form a hierarchy:

```
Resource
 ├── TargetDetails           get_rows(), is_dockable()   (what the HUD shows)
 │    └── InhabitedData      display_name, faction_name, population,
 │         │                 exported_goods, imported_goods, market, picture,
 │         │                 size, docking_range, get_picture(), validate()
 │         └── PlanetData    + planet_type
 ├── PlanetType              display_name, texture, settlement_picture
 ├── ShipStats               thrust, turn_rate, max_speed
 └── PlayerData              runtime player state
```

Key points:

- `InhabitedData` extends `TargetDetails`, so the object's data resource **is** what the HUD reads. `Targetable` calls `get_rows()` and never needs to know the concrete type.
- `PlanetData` extends `InhabitedData`; a planet has everything a station has, plus a `planet_type`.
- `PlanetType` is a separate resource shared by many planets. Choosing the type picks the sprite *and* the default settlement-screen background (`settlement_picture`). Later it can also hold shared trade modifiers.
- Setters on `InhabitedData` fields call `emit_changed()`, which makes the HUD refresh if data changes at runtime.
- `faction_name` is currently a plain string until factions exist. `exported_goods` and `imported_goods` are arrays of `Commodity` resources (see [economy.md](economy.md)). A commodity must not appear in both.
- `market` is an optional `MarketData`. Without one, the location has no trading floor.

### Data files

```
resources/
  locations/       earth.tres (PlanetData), mars.tres (PlanetData), victory_i.tres (InhabitedData)
  planet_types/    terrestrial, rocky, desert, moon, arctic, ocean, resort  (PlanetType .tres)
  ships/           shuttle_stats.tres            (ShipStats)
```

---

## 5. How the pieces connect at runtime

1. `main.tscn` instances a system scene (currently `sol_system.tscn`) as the `StarSystem` node.
2. Each object in the system's `Objects` node runs `_ready()`:
   - `InhabitedNode` validates its `data`.
   - `SpaceObject` calls `Targetable.configure(...)` with name, type label, bounds, details and dock range.
   - `Planet` applies its sprite and scale.
3. The `Targetable` joins the `targetable` group. `TargetingManager` finds clickable ones via a physics point query on layer 2 and cycles through the group with the `cycle_target` action.
4. Selecting a target sends it to the HUD (`target_changed` signal). The HUD shows `name`, `type`, distance and `details.get_rows()`.
5. Pressing the `dock` action calls `DockingManager.try_dock()`, which checks that the target `is_dockable()`, that the ship is within `dock_range`, and that it is slower than `max_dock_speed`. On success the `SettlementScreen` opens, showing the data's name, rows and background picture (see [section 7.1](#71-settlement-pictures)).

None of this needs editing when you add content. If it is wired through `Targetable` and `InhabitedData`, it just works.

---

## 6. Recipe: add a planet to an existing system

Example: add **Venus** to the Sol system.

### Step 1: Create the data resource

1. In the FileSystem dock, right-click `resources/locations/` → **New Resource…**
2. Choose **PlanetData**, save as `venus.tres`.
3. Fill in the Inspector:

| Field | Example | Notes |
|-------|---------|-------|
| `planet_type` | `resources/planet_types/terrestrial.tres` | **Required.** Chooses the sprite |
| `display_name` | `Venus` | **Required** |
| `faction_name` | `TestFaction_1` | free text for now |
| `population` | `250000` | |
| `exported_goods` | `[electronics.tres]` | `Commodity` resources; must not overlap imports |
| `imported_goods` | `[fuel.tres]` | |
| `market` | `resources/markets/venus_market.tres` | optional; see [economy.md](economy.md). No market = Trading Floor button disabled |
| `size` | `380` | planet diameter in world pixels |
| `docking_range` | `0` | `0` = automatic (edge of selection box) |
| `picture` | *(optional)* | settlement screen image for this planet only; empty uses the planet type's `settlement_picture` |

Or write the file by hand, following the existing format:

```ini
[gd_resource type="Resource" script_class="PlanetData" format=3]

[ext_resource type="Script" path="res://scripts/resources/planet_data.gd" id="1"]
[ext_resource type="Resource" path="res://resources/planet_types/terrestrial.tres" id="2"]
[ext_resource type="Script" path="res://scripts/resources/commodity.gd" id="cs"]
[ext_resource type="Resource" path="res://resources/commodities/electronics.tres" id="c_electronics"]
[ext_resource type="Resource" path="res://resources/commodities/fuel.tres" id="c_fuel"]
[ext_resource type="Resource" path="res://resources/markets/venus_market.tres" id="market"]

[resource]
script = ExtResource("1")
planet_type = ExtResource("2")
display_name = "Venus"
faction_name = "TestFaction_1"
population = 250000
exported_goods = Array[ExtResource("cs")]([ExtResource("c_electronics")])
imported_goods = Array[ExtResource("cs")]([ExtResource("c_fuel")])
market = ExtResource("market")
size = 380.0
```

### Step 2: Place it in the system scene

1. Open `scenes/systems/sol_system.tscn`.
2. Right-click the **Objects** node → **Instantiate Child Scene…** → `scenes/objects/planet.tscn`.
3. Rename the node (e.g. `Venus`).
4. Set its **Position** in the Inspector (or drag it in the 2D view).
5. Drag `venus.tres` into the node's **Data** slot.
6. Save.

Or, in text form, append to `sol_system.tscn` (add a matching `ext_resource` line for `venus.tres` with a unique id):

```ini
[ext_resource type="Resource" path="res://resources/locations/venus.tres" id="7"]

[node name="Venus" parent="Objects" index="3" instance=ExtResource("2")]
position = Vector2(-1500, 600)
data = ExtResource("7")
```

### Step 3: Test

Run the project (F5). Fly to the planet, click it or press the cycle-target key, and confirm that the sprite, name, type label (`Planet (Terrestrial)`) and rows appear in the HUD. Slow down, get within range, and dock.

> **Do not share one `.tres` between two placed objects** unless you want them to be identical. Give each location its own data file.

---

## 7. Recipe: add a new planet type

Example: an **Ice** planet.

1. Add the sprite to `assets/sprites/planets/Ice.png` (square image works best; the width is scaled to the planet's `size`).
2. Create `resources/planet_types/ice.tres`: right-click → **New Resource…** → **PlanetType**.
3. Set `display_name = "Ice"`, assign `texture`, and assign `settlement_picture` (see the table in [7.1](#71-settlement-pictures)).
4. In any `PlanetData`, set `planet_type` to `ice.tres`.

```ini
[gd_resource type="Resource" script_class="PlanetType" format=3]

[ext_resource type="Script" path="res://scripts/resources/planet_type.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/sprites/planets/Ice.png" id="2"]
[ext_resource type="Texture2D" path="res://assets/sprites/settlements/arctic_city.png" id="3"]

[resource]
script = ExtResource("1")
display_name = "Ice"
texture = ExtResource("2")
settlement_picture = ExtResource("3")
```

No scene or script changes are needed. The HUD label automatically becomes `Planet (Ice)`.

### 7.1 Settlement pictures

The background shown on the settlement screen when docked is chosen in this order:

1. The planet's own `PlanetData.picture`, if set (a one-off background for that planet).
2. Its type's `PlanetType.settlement_picture`.
3. The settlement screen's `default_picture` (`inhabited_city.png`), used for stations and anything with no picture.

This is done by `InhabitedData.get_picture()`, which `PlanetData` overrides to add the planet-type fallback; `SettlementScreen.open()` just calls it.

Current type → background mapping:

| Planet type | `settlement_picture` |
|-------------|----------------------|
| Terrestrial | `inhabited_city.png` |
| Rocky, Desert, Moon | `desert_city.png` |
| Arctic, Ocean, Resort | `arctic_city.png` |

Jungle and the gas giants have sprites in `assets/sprites/planets/` but no `PlanetType` yet. To add one, follow the recipe above.

---

## 8. Recipe: add a space station

Stations use the same `InhabitedData` as planets but **plain `InhabitedData`**, not `PlanetData`, since they have no planet type.

1. Create `resources/locations/<name>.tres` as an **InhabitedData** (see `victory_i.tres`). `size` is the ring diameter; total width is about 2.2× that.
2. In the system scene, instance `scenes/objects/space_station.tscn` under **Objects**.
3. Set its position and assign the data.

```ini
[node name="VictoryI" parent="Objects" index="2" instance=ExtResource("3")]
position = Vector2(600, 350)
data = ExtResource("6")
```

The station is currently a code-drawn placeholder. Replacing it with a sprite later means changing only `space_station.tscn`/`.gd`; nothing else depends on how it is drawn.

---

## 9. Recipe: create a new star system

Example: a system called **Alpha Centauri**.

### Step 1: Create the inherited scene

In the editor: **Scene → New Inherited Scene…** → pick `scenes/systems/star_system.tscn`, then **Save As** `scenes/systems/alpha_centauri_system.tscn`.

Minimum file content (it is this small by design):

```ini
[gd_scene format=3]

[ext_resource type="PackedScene" path="res://scenes/systems/star_system.tscn" id="1"]

[node name="AlphaCentauriSystem" instance=ExtResource("1")]
system_name = "Alpha Centauri"
```

`system_name` is shown in the HUD. Leave it empty to show no name.

### Step 2: Add objects

Follow [section 6](#6-recipe-add-a-planet-to-an-existing-system) and [section 8](#8-recipe-add-a-space-station): create data resources, then instance `planet.tscn` / `space_station.tscn` under the inherited **Objects** node, set positions, and assign data.

Every system inherits ambient NPC traffic from `star_system.tscn` (the `Ships` and `Traffic` nodes). New planets and stations placed under `Objects` automatically become destinations for it. See [npc-traffic.md](npc-traffic.md) to tune or override a system's traffic.

Keep these in mind when laying out a system:

- Positions are in **world pixels**, relative to the system origin `(0, 0)`.
- The player ship currently starts at the world origin, so keep the origin area clear.
- Sizes are real pixel sizes (Earth is 450, Mars 600), so leave room between objects and think about how long travel takes at the ship's `max_speed` (500 px/s for the shuttle).
- Object order under `Objects` is the order of `cycle_target` selection.

### Step 3: Customise the background (optional)

The inherited `Background` contains two `star_field.gd` layers (`NearStars` and a parallax `DistantStars`). Override their exported properties in your system scene for a different feel:

| Property | Meaning |
|----------|---------|
| `star_count` | number of stars |
| `half_extent` | scatter area half-size, px (default 8000) |
| `seed_value` | change for a different star pattern |
| `brightness_scale` | below 1.0 looks more distant |
| `size_scale` | below 1.0 looks more distant |

In the editor, select `NearStars` or `DistantStars/StarField` in your inherited scene and change the values in the Inspector.

> The star fields are drawn within `half_extent` of the origin. If a system extends beyond about ±8000 px, raise `half_extent` or the player will leave the stars behind.

### Step 4: Load it

Currently `main.tscn` hard-codes `sol_system.tscn` as its `StarSystem` child. To test a new system:

1. Open `main.tscn`, delete the `StarSystem` node.
2. Right-click `Main` → **Instantiate Child Scene…** → your new system scene.
3. Rename the new node to `StarSystem` (`main.gd` finds it with `$StarSystem`) and move it to the top of the tree so it draws behind the ship.

Switching systems *during play* (hyperspace jumps, stargates) is not yet implemented. When it is, the likely design is for `Main` to free the current system and instance another, emitting a signal so the HUD and targeting reset. Ask before building it.

---

## 10. Recipe: add a new kind of object

Example: an **asteroid field** or **jump gate**. Pick the closest parent:

| If the object… | Extend |
|----------------|--------|
| has population, faction, goods, can be docked | `InhabitedNode` |
| is just selectable, with no docking data | `SpaceObject` |
| isn't a `Node2D` (e.g. a ship body) | add a `Targetable` child and call `configure(...)` |

For an `InhabitedNode` child (the common case):

1. **Script** `scripts/objects/my_thing.gd`:
   ```gdscript
   class_name MyThing
   extends InhabitedNode

   func _ready() -> void:
       super()   # always call super so Targetable wiring and validation run
       queue_redraw()

   func _get_object_type() -> ObjectType:
       return ObjectType.STATION   # or add a new value to SpaceObject.ObjectType

   func _get_target_bounds() -> Vector2:
       return Vector2(data.size, data.size)
   ```
2. **Scene** `scenes/objects/my_thing.tscn`: **New Inherited Scene** from `inhabited_node.tscn`, attach the script, add any visual nodes.
3. If a new type label is needed, add it to the `ObjectType` enum in `space_object.gd`.
4. If it needs extra data, create a `Resource` that extends `InhabitedData` (as `PlanetData` does), override `validate()` and call `super()` first.
5. Place instances in a system scene as in the other recipes.

Following the project rules: don't add features nobody asked for. Propose the design first for anything substantial.

---

## 11. Validation and troubleshooting

`InhabitedNode._ready()` runs `data.validate()` and prints problems to the Godot **Output / Debugger** panel.

| Message | Cause and fix |
|---------|---------------|
| `<Node> has no InhabitedData assigned.` | The `data` slot is empty. Assign a `.tres` |
| `<Node>: display_name is empty` | Fill in `display_name` in the data resource |
| `<Node>: 'X' is both imported and exported` | Remove the good from one of the lists |
| `<Node>: planet_type is not set` | Assign a `PlanetType` to the `PlanetData` |
| `<Node>: planet_type 'X' has no texture` | Give the `PlanetType` a texture |
| `<Node>: a Planet needs PlanetData, not plain InhabitedData.` | Planets need a `PlanetData` resource; create the `.tres` using the PlanetData type |

Other common problems:

- **Planet is invisible**: no `planet_type`/`texture`, or `size` is `0`.
- **Can't click the object**: the object's `Targetable` didn't configure. Check the Output panel for earlier errors and make sure any `_ready()` override calls `super()`.
- **"Can't dock" when you expect to**: the ship must be within `dock_range` (default is half the object's size plus 14 px) *and* below `max_dock_speed` (100 px/s). The data must be `is_dockable()`; all `InhabitedData` is.
- **Edited the parent scene but the child didn't change**: the child overrides that property locally. In the Inspector, use the revert arrow next to the property.
- **Child scene shows "missing parent"**: the node was placed under a parent path that doesn't exist in the base scene. Only inherited nodes (`Objects`, `Background`, …) can be targeted.
- **Parser errors after adding a script**: resolve them before considering the feature complete. Run Godot from the command line to check (see below).

### Checking from the command line

Per `CLAUDE.md`, the Godot executable is:

```
C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
```

Run the project, or check the scripts without opening the editor:

```powershell
& "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path . --check-only --headless --script scripts/objects/planet.gd
```

---

## 12. Quick reference

**New planet:** `PlanetData .tres` (+ existing or new `PlanetType`) → instance `planet.tscn` under the system's `Objects` → set `position` and `data`.

**New station:** `InhabitedData .tres` → instance `space_station.tscn` under `Objects` → set `position` and `data`.

**New planet type:** sprite in `assets/sprites/planets/` → `PlanetType .tres` (with `texture` and `settlement_picture`) → reference it from `PlanetData`.

**New system:** *New Inherited Scene* from `star_system.tscn` → set `system_name` → add objects under `Objects` → optionally tweak star fields → point `main.tscn` at it.

**File locations**

| Content | Folder |
|---------|--------|
| Object scenes (planet, station, targetable) | `scenes/objects/` |
| System scenes | `scenes/systems/` |
| Location data (`PlanetData`, `InhabitedData`) | `resources/locations/` |
| Planet types | `resources/planet_types/` |
| Planet sprites | `assets/sprites/planets/` |
| Settlement pictures | `assets/sprites/settlements/` |
| Resource classes | `scripts/resources/` |
