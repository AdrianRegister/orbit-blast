# Orbit Blast - Project Instructions

## Project Overview

Orbit Blast is a 2D top-down space exploration,
trading and combat game inspired by Escape Velocity.

## Current Development Phase

Phase 2.9 – Advanced economy

Phases 2.2 to 2.8 are done (ships and upgrades, galaxy map and travel, expanded and procedural contracts, the EV Nova galaxy, settlement ownership and contested systems, factions and reputation). Each has a document in docs/ describing how it works; read the relevant one before changing that system.

## Technology

- Engine: Godot 4.x
- Language: GDScript
- Platform: Windows PC initially
- Input: Keyboard and mouse
- Genre: Single-player space simulation

## Architecture

- Use Godot's native scene and node architecture.
- Use reusable scenes for game objects.
- Use custom Resources for static game data.
- Use signals for communication between independent systems.
- Keep gameplay logic separate from UI.
- Avoid unnecessary global state and Autoloads.
- Use typed GDScript where practical.

## Project Structure

- scenes/: Godot scenes (.tscn)
- scripts/: GDScript files (.gd)
- resources/: Static game resources (.tres)
- assets/: Graphics, audio and fonts
- data/: Game configuration and external data (the galaxy table and name pools are in data/galaxy/)
- docs/: How each system works. Keep the relevant document up to date when changing a system.
- tools/: Content generators, run with Godot (see Galaxy content below)

## Patterns Already Used

- Runtime systems are Nodes in scenes/main.tscn wired by scripts/main.gd (no Autoloads). Examples: Economy, Contracts, Travel, Territory, Reputation, Ships.
- Static content is Resources (.tres) and is never changed while playing. Anything that changes at runtime (ownership, reputation, discovery) lives in a manager and is saved.
- Save data is JSON in registered sections (scripts/save/). A section validates before it applies, is optional if older saves must still load, and refers to content by permanent id, never by name or path. Ids must never change once saves exist.
- Compare factions, locations and systems by id. Faction, location and system names are for display only.
- Who owns a settlement comes from TerritoryManager, and a system's control is derived from its settlements. Reputation comes from ReputationManager. Do not read `faction` fields directly for current ownership.
- Damage to planets and stations comes from InfrastructureManager and only lowers production; it recovers by itself and is never permanent. Military value comes from SystemAssessor. Neither reads reputation.
- Contracts come from a ContractSource (procedural today). Tunable numbers live in resources (resources/contracts/), not in code. Civilian contracts never change reputation.

## Galaxy content

- The galaxy is generated from data/galaxy/galaxy_map.json by tools/galaxy_generator.gd. Edit the table, then run `tools/generate_galaxy.gd` (see docs/galaxy.md). Do not hand edit files in the `generated/` folders unless the system is marked `locked` in the table.
- Hand built systems (`hand_built`) are only listed in the table; their scenes and locations are written by hand.
- Naming: the system whose id is `epsilon_eridani` is called **Alphara** in design discussions (the id is a leftover from early development and must not change). Treat "Alphara" and `epsilon_eridani` as the same system.
- System roles (built, see docs/system_classes.md): a system's class (critical, economic centre, military centre, military output, rural, frontier) is designer-set with the `class` field of its table row and never changes. Economic centres need 4 jump links; military centres are exempt. Zones (capital, core, inner, frontier, and mini-cores around conquered critical systems) are derived from the jump graph and ownership and never feed back into the economy: the chain is graph -> class -> economy -> value -> importance -> centres -> zones.
- A `locked` system keeps its generated files, and the generator keeps the names its locations hold reserved. If you lock a system, run the generator and check that no other generated scene or location changed (`git status` on `scenes/systems/generated`).

## Development Rules

- Do not implement features that haven't been requested.
- Inspect existing code before modifying it.
- Avoid rewriting unrelated files.
- Explain architectural decisions.
- Keep features modular and maintainable.
- Test changes using Godot.
- Resolve parser errors before considering a feature complete.

## Wars

Galactic war between factions is a major end goal of this project. Refer to wars_system.md before implementing a game system. This will ensure its implementation with the end goal in mind.

## Collaboration

Before implementing a substantial feature:

1. Explain the proposed implementation.
2. Identify affected scenes and scripts.
3. Wait for approval.
4. Implement incrementally.
5. Explain how to test the result.

## Godot executable

- Windows executable: C:\Users\Adrian\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
- Use this path when executing Godot commands.

## Testing

- Tests are scripts in scripts/tests/ named `*_test.gd`, run headless one at a time:
  `Godot --headless --path . --script res://scripts/tests/<name>_test.gd </dev/null`
  A passing test prints "... all passed" and exits 0. Always redirect stdin from /dev/null.
- After adding a script with a `class_name`, run `Godot --headless --path . --import` once, or other scripts will not find it.
- The full suite (every *_test.gd) takes 30 minutes or more. Run only the tests for what changed while working, and the full suite when finishing a phase. Run it in the background and read the results when it finishes.
- Tests that need a fixed set of contracts use scripts/tests/support/fixed_contract_source.gd instead of the random generator.
- Tests must not hard-code the galaxy layout (which systems are neighbours); read it from the galaxy or the table.
- For a look at the real UI, run the game non-headless with `--resolution 1600x900 --script` and save `root.get_texture().get_image()` to a PNG.

## Gotchas

- StringName arrays do not sort alphabetically with `sort()`. Sort with `sort_custom(func(a, b): return str(a) < str(b))`.
- Node already has `get_owner()` and `set_owner()`; do not use those names on a Node subclass.
- Edit .tres and .gd files with the tools, not shell heredocs containing apostrophes or quotes, which break in this environment (write a script file instead).
- Git commits and pushes happen only when the user asks.
