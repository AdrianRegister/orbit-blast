# Combat (Phase 3.1: foundations)

How ship combat works: weapons, shots, the layered damage model, destruction, repairs, what the player's death does, and where later systems (NPC combat AI, formations, convoys, wars) plug in. Phase 3.1 builds the ship-level parts only. NPC ships carry weapons and can be destroyed, but they do not fire or fight back yet.

Read this before changing combat. Read [wars_system.md](../wars_system.md) before designing anything that fleets or wars will use.

---

## 1. Overview

- A **weapon** (`WeaponDefinition`) is static data. A ship model (`ShipStats`) lists its **mounts** (`WeaponMount`); an owned ship has one weapon (or none) per mount.
- Every flying ship, the player's or an NPC's, has a **`Combatant`**: its defences, its weapons and its hit area. It is the one interface the HUD, the `CombatManager` and (later) AI and formations talk to. It holds no input or decision logic.
- Firing makes a **`Projectile`**. A projectile sweeps a ray along its path each frame, so fast shots never skip a target.
- A hit goes through the **layered damage model** (shields, then armour, then hull) in `DamageModel`, which is pure data maths and is configured by `resources/combat/damage_rules.tres` and by each weapon.
- Hull at zero destroys the ship. The `CombatManager` announces it and charges reputation. The player's own destruction ends in an **escape pod** (section 8).
- Shields and energy recharge by themselves. Armour and hull damage on the player's ships is saved and is repaired for a fee at a shipyard.

---

## 2. Static data

| Piece | File | Role |
|---|---|---|
| `WeaponDefinition` | `scripts/resources/weapon_definition.gd`, `resources/weapons/*.tres` | One weapon: price, mount size, damage, fire interval, energy per shot, shot speed, range, spread, per-layer multipliers, shield bypass |
| `WeaponMount` | `scripts/resources/weapon_mount.gd` (sub-resources of the ship `.tres`) | One place for a weapon: fixed or turret, size, offset from the ship's centre, turret arc |
| `ShipStats` (combat fields) | `scripts/resources/ship_stats.gd` | `shield_capacity`, `shield_regen`, `shield_regen_delay`, `armour`, `hull`, `energy_capacity`, `energy_regen`, `hit_radius`, `weapon_mounts`, `default_loadout` |
| `DamageRules` | `scripts/combat/damage_rules.gd`, `resources/combat/damage_rules.tres` | Armour reduction, bleed-through, repair prices, weapon sell fraction |

- A weapon fits a mount of **its own size or larger** (`WeaponDefinition.fits`). Fixed mounts fire straight ahead; turret mounts aim at the target within their arc.
- `default_loadout` is parallel to `weapon_mounts` (entry N goes in mount N, null = empty). It is what NPCs fly with and what a newly bought ship has. The shuttle has one small mount with a light blaster, so a new game can fight.
- `ShipSpecs` carries the same numbers (and the number of mounts). It is still the only place that combines a model with its upgrades; no upgrade changes defences yet.
- Weapon `kind` (only `PROJECTILE` exists) is the extension point for beams and missiles.

---

## 3. The damage model

`DamageModel.resolve(state, hit, rules)` works on plain data (`DefenceState`, `Hit`, `DamageResult`), so it can be tested without a scene. The order:

1. A share of the damage (`shield_bypass`) skips the shields.
2. The rest hits the shields, multiplied by the weapon's `shield_multiplier`. What the shields cannot absorb carries on (turned back into raw damage).
3. Damage reaching the armour is reduced by `armour_damage_reduction` and multiplied by the weapon's `armour_multiplier`, and taken from the armour. Overflow past zero carries on to the hull. While armour holds, `armour_bleed_through` of the absorbed damage also reaches the hull.
4. The hull takes the rest. Hull at zero means destroyed.

`DamageResult` reports shield, armour and hull damage; `penetrated()` is true once a hit got past the shields (the HUD uses it for its red flash). A destroyed ship takes no further damage.

All the numbers are in `damage_rules.tres` and in the weapon files. To make armour tougher, raise `armour_damage_reduction`; to make an ion weapon good against shields, raise its `shield_multiplier` and lower its `armour_multiplier`.

---

## 4. Runtime: the parts of a ship's combat

`scenes/combat/combatant.tscn` is added to both `player_ship.tscn` and `npc_ship.tscn`.

| Node | Script | Role |
|---|---|---|
| `Combatant` | `scripts/combat/combatant.gd` | The interface: `setup`, `set_target`, `get_target`, `fire`, `take_hit`; signals `damaged`, `destroyed`, `target_changed`. Holds `combat_id` (unique per ship in play), `faction_id`, `is_player` |
| `Health` | `ship_health.gd` | Live shield, armour, hull and energy. Recharges shields (after `shield_regen_delay`) and energy. Mirrors armour and hull into the owned ship's `ShipCondition` |
| `Weapons` | `weapon_system.gd` | One `WeaponSlot` per mount; cooldowns, energy, aim. `fire()` fires every weapon that is ready and affordable |
| `Hurtbox` | `hurtbox.gd` | An `Area2D` circle on physics layer 3 that shots can hit. It detects and blocks nothing |

The ship tells its `Combatant` how to read its heading and velocity (two callables passed to `setup`), because the player is a `CharacterBody2D` and NPCs are plain `Node2D`s that move themselves.

**Projectiles** (`projectile.gd`, `scenes/combat/projectile.tscn`) live under the system's new `Projectiles` node, so a jump frees them with the rest of the system. A shot's velocity is its muzzle velocity plus `inherit_velocity` times the shooter's velocity. Each physics frame it casts a ray (mask: layer 3, `hit_from_inside`) over the distance it is about to travel and hits the first hurtbox, ignoring its own shooter's.

**Aiming.** Fixed mounts fire along the heading. Turrets aim at the intercept point of the combatant's target (`Intercept.solve`, which accounts for both ships' velocities and the shot speed), clamped to the mount's arc; with no target they fire ahead. The HUD's lead marker (`LeadIndicator`, a child of the player ship) shows the same point for the nose.

**Collision layers** (named in `project.godot`): 1 world, 2 targetable (click selection, unchanged), 3 ship hurtbox.

**Targeting.** There is no separate "lock": the existing selection (Tab, T, R, click) is the target. `CombatManager.on_target_changed` gives the selected ship's `Combatant` to the player's combatant, so turrets follow it and the HUD shows its defences. Selecting a planet or nothing clears it.

**Firing.** Hold **Space** (`fire_primary`). It fires every ready weapon, only while flying (not docked, not warping, not during a menu pause).

---

## 5. `CombatManager`

A node in `main.tscn` (`$Combat`), wired in `Main._ready`. It watches every combatant in the current system and tells the rest of the game. It registers the player's combatant once and each NPC's as it enters the system's `Ships` node (`set_system` is called on every system swap).

Signals (transient notifications; anything that must outlive them is stored by its own system):

- `ship_attacked(victim, attacker, result)`
- `ship_destroyed(report: DestructionReport)`
- `player_destroyed(report)`

`DestructionReport` is plain data: victim and attacker ids, model and faction, whether either was the player, the system, the position and the game day. The war system will read reports like this to turn fights into strategic losses.

**Reputation.** When the player attacks a ship the first hit calls `ReputationManager.report_hostile_action(attack_ship, ...)` and destroying it reports `destroy_ship`; each uses an event id built from the victim's `combat_id`, so a ship is charged once per kind of act however many times it is hit. The victim faction is the ship's `faction_id`. A ship with no faction (one just passing through) is charged to the faction that controls the system, through `report_hostile_action_in_system`; a contested or unclaimed system charges nobody. NPC ships get their `faction_id` from the current owner of the location they came from (`StarSystem.get_owner_id`, set to `TerritoryManager.owner_id_of`), never from `faction` fields.

Effects (hit sparks, explosions) are `BurstEffect` particles added to the system's `Projectiles` node.

---

## 6. NPC ships

NPC ships (`NpcShip`) carry the same `Combatant` with their model's default loadout and full defences. In 3.1 they are **passive**: they keep flying their traffic routes and never fire. They can be shot at and destroyed: a destroyed NPC disables its `Targetable` (which clears the player's selection), hides and frees itself; the traffic manager counts it as gone and replaces it later.

To add NPC combat later, drive the same `Combatant` from an AI: call `set_target` and `fire`, and add combat states to `NpcShip.State` as [npc-traffic.md](npc-traffic.md) describes. Nothing in the combat code assumes the controller is the player.

---

## 7. The player's ships: weapons, condition, outfitters, repairs

- `OwnedShip.weapons` holds one entry per mount (null = empty). `OwnedShip.condition` (`ShipCondition`) holds the armour and hull left; `-1` means undamaged. The running ship's `Health` writes into the same object, so a save always sees the current condition.
- `InhabitedData.outfitter_weapons` lists the weapons a location sells; `has_outfitter()` is true for upgrades, weapons or both (use it, not the lists), and `has_shipyard()` for ships.
- `ShipManager` (the only code that changes the fleet): `quote_weapon` / `install_weapon` (checks: docked, offered here, `max_per_ship`, a free mount that fits, credits), `quote_sell_weapon` / `sell_weapon` (any outfitter buys back a fitted weapon for `weapon_sell_fraction` of its price), `get_repair_cost` / `quote_repair` / `repair` (only at a location with a shipyard; the cost is the missing armour and hull at the rule's prices; never permanent damage), `lose_active_ship`.
- Buying a ship gives it the model's default loadout and an undamaged condition.
- Shields and energy are not saved: they are full whenever a ship is applied (start, load, purchase, repair, respawn).

Outfitter screen: weapons are listed with the upgrades (TYPE "WEAPON"), with the numbers (`WeaponDefinition.get_stats_text`), the mounts in use, an INSTALL button and a SELL button. Shipyard screen: a REPAIR button with the price appears when the ship is damaged. `SpecComparison` shows shields, armour, hull, energy and mounts.

---

## 8. Destroying the player's ship: the escape pod

`CombatManager.player_destroyed` calls `Main._on_player_destroyed`:

1. While it happens, flight, targeting, jumping, maps, the pause menu and autosave are all off (nothing can save the ship that no longer exists).
2. After `POD_DELAY` (2 seconds) the screen flashes (`JumpFlash`) and, at its peak, `Main.respawn_in_escape_pod()` runs.
3. The destroyed ship, with its weapons and upgrades, is removed from the fleet; **all cargo is lost**, so delivery and ferry contracts fail (`ContractManager.fail_lost_cargo_contracts`; exploration contracts stay).
4. The player's **most valuable remaining ship** (even one stored away) becomes active. With none left, a new ship of `Main.starting_ship_stats` is given, so the player is never stranded.
5. The player wakes **docked at the last place they landed** (`Main.get_last_landed`, saved in the `player` section). With no landing yet they go to `Main.fallback_respawn` (Earth, set in `main.tscn`). No game time passes and nothing happens on arrival (it is a restore, not a landing).
6. **Credits and reputation are kept.** An event popup says what was lost and what the player flies now.
7. The game is **saved immediately**, so the loss cannot be undone by reloading an older autosave.

---

## 9. HUD

All data is read from the player's ship each frame (like velocity), with the existing theme and `StatBar` / `InfoRow` pieces:

- Shield, armour, hull and energy bars; the weapon names; a FIRE row (READY, RELOADING, NO ENERGY, NO WEAPONS) with a cooldown bar.
- The target panel, for a ship target, adds shield, armour and hull bars and a RANGE row (IN RANGE / OUT OF RANGE against the longest weapon).
- A red screen flash when a hit gets past the shields and a faint blue one when the shields take it; "TARGET DESTROYED" and "SHIP DESTROYED" messages under the weapon readout (`Hud.show_combat_message`).
- In the world: the lead marker, hit sparks and explosions.

---

## 10. Saving

No version bump: everything new is optional (see [save-system.md](save-system.md)).

- `fleet`, per ship: optional `weapons` (one id per mount, `""` for an empty mount), `armour` and `hull` (only for a damaged ship). Missing = the model's default loadout, undamaged. Validation checks the ids, the mount count, that each weapon fits its mount, `max_per_ship`, and that armour and hull are within the model's numbers (hull above zero).
- `player`: optional `last_landed` (a location id).
- `contracts`: failed contracts are saved in the existing `failed` list.
- Weapons are referred to by `id` (permanent, like every other content id).

---

## 11. For the war system and combat AI

| Later system | Where it plugs in |
|---|---|
| NPC combat AI, squadrons, convoy escorts | Drive the NPC's `Combatant` (`set_target`, `fire`); add `NpcShip.State` values. The registry of combatants is in `CombatManager`; `faction_id` says whose side a ship is on |
| Formations | Only need to give a ship a position and heading; the combat parts do not care who steers |
| Fleet strength for abstract battles | A ship's stats, defences and loadout are all data: a `combat_rating()` can be computed from them without touching the runtime code. `Faction.military_strength` can be derived from it later |
| Losses in strategic battles | `ship_destroyed(report)` and `DestructionReport` carry the faction, system and day. When the player joins a fleet engagement, its result should feed the strategic simulation (`wars_system.md`) |
| Other weapon types (beams, missiles, mines) | New `WeaponDefinition.Kind` values and a `Hit` source; `DamageModel` and `Combatant.take_hit` do not change |
| Ship damage in the world (hazards) | Build a `Hit` and call `Combatant.take_hit` |

Combat never reads `faction` fields for ownership: it asks the territory manager through `StarSystem`, as the rest of the game does.

---

## 12. Recipes

**Add a weapon.** Copy a file in `resources/weapons/`, give it a unique `id` (never change it once saves exist), set the numbers, and add it to locations' `outfitter_weapons`. The content registry finds it by `id`. For generated outfitters, edit `tools/galaxy_generator.gd` and run it (see [galaxy.md](galaxy.md)); locked systems are edited by hand.

**Give a ship more or different mounts.** In its `resources/ships/<name>_stats.tres`, add `WeaponMount` sub-resources to `weapon_mounts` and extend `default_loadout` to match. Existing saves keep working: a ship's saved `weapons` list must match the mount count, so changing the mount count of a model that players already own invalidates their saves for that ship. Add mounts only to models no save can hold yet, or add a migration.

**Tune the damage rules or repair prices.** Edit `resources/combat/damage_rules.tres`.

---

## 13. Testing

```powershell
$godot = "C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://scripts/tests/damage_model_test.gd
& $godot --headless --path . --script res://scripts/tests/weapon_test.gd
& $godot --headless --path . --script res://scripts/tests/combat_test.gd
& $godot --headless --path . --script res://scripts/tests/ship_combat_test.gd
& $godot --headless --path . --script res://scripts/tests/escape_pod_test.gd
& $godot --headless --path . --script res://scripts/tests/combat_sandbox_test.gd
```

- `damage_model_test.gd`: the layers, multipliers, bypass, bleed-through, destruction.
- `weapon_test.gd`: every weapon and ship file validates, `fits`, `Intercept`, the specs.
- `combat_test.gd` (real scene): firing, cooldown, energy, projectile hits, shields then hull, destruction events and removal, deselection, reputation once per act, turret aim and arc, no self-hits, shield recharge.
- `ship_combat_test.gd`: loadouts, fitting and selling, limits, repairs, saving and loading weapons and damage, old saves, invalid data.
- `escape_pod_test.gd` (real scene): the whole sequence, cargo and contracts, the replacement ship, the respawn place, the immediate save.

The look of the shots, the HUD and the explosions is best checked by running the game (hold Space with a ship selected).

---

## 14. The dev combat sandbox

For trying combat by hand. **DEV COMBAT SANDBOX** on the main menu starts it; Esc then Quit to Menu leaves it. It never reads or writes the real save.

- **What it is:** the normal game (`main.tscn`) with `Main.sandbox_mode` on, built by `CombatSandbox.build_main()` (`scripts/dev/combat_sandbox.gd`). It swaps in one made-up star system, `scenes/dev/combat_sandbox_system.tscn` (id `dev_combat_sandbox`; not on the galaxy map, no traffic), with one planet, the Proving Ground (`resources/dev/sandbox_planet.tres`, at (1500, 0)).
- **Everything is for sale:** the planet's shipyard sells every ship model (faction restrictions ignored, `ShipManager.ignore_ship_factions`), its outfitter every upgrade and weapon. The lists are filled from the content registry (`ContentRegistry.all_ship_stats / all_upgrades / all_weapons`) when the sandbox starts, so new content appears without editing anything. Repairs work too.
- **The player** starts with 500,000,000 credits in a Light Frigate, near the planet.
- **The target:** one freighter that drifts around the centre of the system (`NpcShip.State.WANDERING`, `begin_wandering`). It never fires, belongs to nobody, and a new one appears 3 seconds after it is destroyed.
- **Formation panel:** a dev panel on the left spawns formations (squadron, battle group and convoy presets, or any ship times a count) in a chosen shape, shows the targeted ship's formation, changes its shape, kills its leader or a member, and clears them. See [formations.md](formations.md) section 3.
- **Isolation:** no reputation is ever charged (the `CombatManager` is given none), no contracts, no jumping or galaxy map or Factions screen, and saving and loading from the pause menu are refused. If the player's ship is destroyed the escape pod brings them back to the Proving Ground, in the most valuable ship they still own (or a new Light Frigate).
- **Changing it:** edit the constants at the top of `combat_sandbox.gd` (the player's ship and credits, the target's ship type, wander radius, respawn delay) or the system scene. When a combat feature needs something new in the sandbox (more targets, armed enemies, hazards), add it to `CombatSandbox`.
- **Test:** `scripts/tests/combat_sandbox_test.gd` starts it from the menu button and checks all of the above.

## 15. Current limits

NPC ships never fire. No missiles or beams. No ammunition. No collisions between ships. No shield or armour upgrades at the outfitter (the numbers come from the model). No insurance (the escape pod costs the ship and cargo, never credits). No area damage. The enemy sides of combat (faction hostility, who attacks whom) come with the AI and war phases. All numbers are first guesses.
