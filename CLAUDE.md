# Orbit Blast - Project Instructions

## Project Overview

Orbit Blast is a 2D top-down space exploration,
trading and combat game inspired by Escape Velocity.

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
- data/: Game configuration and external data

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
