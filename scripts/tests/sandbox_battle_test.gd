extends SceneTree
## Tests the combat sandbox's dev tools: the toolbar that opens and closes the
## formations panel (button and F2) and the battle panel (button and F3), and the
## battle builder that spawns two sides facing each other. Uses the real game scene.
##   Godot --headless --path . --script res://scripts/tests/sandbox_battle_test.gd </dev/null

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _sandbox: CombatSandbox
var _toolbar: DevToolbar
var _formations: SandboxPanel
var _battle: BattlePanel


func _init() -> void:
	seed(20260414)
	_main = CombatSandbox.build_main()
	root.add_child(_main)
	for i in 5:
		await process_frame
	_system = _main.get_system()
	_player = _main.get_player_ship()
	for child in _main.get_children():
		if child is CombatSandbox:
			_sandbox = child
		elif child is DevToolbar:
			_toolbar = child
		elif child is SandboxPanel:
			_formations = child
		elif child is BattlePanel:
			_battle = child
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	await process_frame

	await _test_toolbar()
	await _test_spawn_battle()
	await _test_battle_panel()
	await _test_presets()

	print("SANDBOX BATTLE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


## Waits some frames, with every ship held still (and so its pilot: this test is about
## what is spawned, not what the ships then do).
func _frames(count: int = 2) -> void:
	for i in count:
		await process_frame
		for ship in _system.get_ships_root().get_children():
			ship.set_physics_process(false)


# ----------------------------------------------------------------------- tests

func _test_toolbar() -> void:
	_check(_sandbox != null and _toolbar != null and _formations != null and _battle != null, "the sandbox has a toolbar, a formations panel and a battle panel")
	if _toolbar == null:
		return
	_check(_toolbar.get_button(0).text.contains("FORMATIONS") and _toolbar.get_button(0).text.contains("F2"), "the first button is FORMATIONS, on F2 (%s)" % _toolbar.get_button(0).text)
	_check(_toolbar.get_button(1).text.contains("BATTLE") and _toolbar.get_button(1).text.contains("F3"), "the second is BATTLE, on F3 (%s)" % _toolbar.get_button(1).text)
	await _frames()
	_check(_toolbar.visible, "the toolbar shows while flying")
	_check(_formations.open and _formations.visible and _toolbar.get_button(0).button_pressed, "the formations panel starts open")
	_check(not _battle.open and not _battle.visible and not _toolbar.get_button(1).button_pressed, "the battle panel starts closed")

	_toolbar.get_button(0).button_pressed = false  # (a click on the button)
	await _frames()
	_check(not _formations.open and not _formations.visible, "the FORMATIONS button closes the formations panel")
	_check(_toolbar.visible, "...and the toolbar stays, so it can be opened again")
	_toolbar.get_button(0).button_pressed = true
	await _frames()
	_check(_formations.open and _formations.visible, "...and opens it again")

	_toolbar._unhandled_input(_key(KEY_F2))
	await _frames()
	_check(not _formations.open and not _formations.visible and not _toolbar.get_button(0).button_pressed, "F2 closes the formations panel and the button follows")
	_toolbar._unhandled_input(_key(KEY_F2, true, true))
	await _frames()
	_check(not _formations.open, "a held key (echo) does not toggle again")
	_toolbar._unhandled_input(_key(KEY_F2, false))
	await _frames()
	_check(not _formations.open, "releasing the key does nothing")
	_toolbar._unhandled_input(_key(KEY_F2))
	await _frames()
	_check(_formations.open and _formations.visible and _toolbar.get_button(0).button_pressed, "F2 opens it again")

	_toolbar._unhandled_input(_key(KEY_F3))
	await _frames()
	_check(_battle.open and _battle.visible and _toolbar.get_button(1).button_pressed, "F3 opens the battle panel")
	_check(not _formations.open and not _formations.visible and not _toolbar.get_button(0).button_pressed, "...and it replaces the formations panel")
	_toolbar._unhandled_input(_key(KEY_G))
	await _frames()
	_check(_battle.open and not _formations.open, "other keys do nothing")
	_toolbar._unhandled_input(_key(KEY_F2))
	await _frames()
	_check(_formations.open and not _battle.open and not _toolbar.get_button(1).button_pressed, "F2 replaces the battle panel in turn")
	_toolbar._unhandled_input(_key(KEY_F3))
	await _frames()

	paused = true
	await _frames()
	_check(not _battle.visible and not _formations.visible and not _toolbar.visible, "everything hides while the game is paused")
	paused = false
	await _frames()
	_check(_battle.visible and not _formations.visible and _toolbar.visible, "...and comes back")
	_check(_toolbar.get_button(0).focus_mode == Control.FOCUS_NONE and _toolbar.get_button(1).focus_mode == Control.FOCUS_NONE, "toolbar buttons never hold the keyboard focus, so Space cannot press them")
	var buttons_unfocusable := true
	for node in _battle.find_children("*", "BaseButton", true, false) + _formations.find_children("*", "BaseButton", true, false):
		buttons_unfocusable = buttons_unfocusable and (node as Control).focus_mode == Control.FOCUS_NONE
	_check(buttons_unfocusable, "no button in a panel can hold the keyboard focus")
	_toolbar.toggle_panel(1)
	await _frames()
	_check(not _battle.open, "the battle panel is closed again")
	_toolbar.toggle_panel(7)  # (no such panel: nothing happens)
	_check(true, "toggling a panel that does not exist does nothing")


func _test_spawn_battle() -> void:
	var before := _system.get_ships_root().get_child_count()
	var sides := _sandbox.spawn_battle(
			{"faction": &"faction_1", "model": &"federation_frigate", "count": 3},
			{"faction": &"faction_2", "model": &"hegemony_gunboat", "count": 2})
	var a: Array = sides["a"]
	var b: Array = sides["b"]
	# (Before anything moves: until the AI takes over, ships drift and turn.)
	var across := _player.rotation + PI / 2.0  # (the line the two sides face along)
	var facing := absf(angle_difference(a[0].get_heading(), across)) < 0.05 and absf(angle_difference(b[0].get_heading(), across + PI)) < 0.05
	for ship: NpcShip in a:
		facing = facing and absf(angle_difference(ship.get_heading(), across)) < 0.05
	for ship: NpcShip in b:
		facing = facing and absf(angle_difference(ship.get_heading(), across + PI)) < 0.05
	await _frames()
	_check(a.size() == 3 and b.size() == 2 and _system.get_ships_root().get_child_count() == before + 5, "a battle of 3 against 2 puts five ships in the system")
	var factions_ok := true
	var models_ok := true
	for ship: NpcShip in a:
		factions_ok = factions_ok and ship.faction_id == &"faction_1" and ship.get_combatant().faction_id == &"faction_1" and ship.faction_name == "Federation"
		models_ok = models_ok and ship.ship_type.stats.id == &"federation_frigate"
	for ship: NpcShip in b:
		factions_ok = factions_ok and ship.faction_id == &"faction_2" and ship.get_combatant().faction_id == &"faction_2" and ship.faction_name == "Hegemony"
		models_ok = models_ok and ship.ship_type.stats.id == &"hegemony_gunboat"
	_check(factions_ok and models_ok, "each side's ships are the model and faction asked for")
	var armed := true
	for ship: NpcShip in a + b:
		armed = armed and ship.get_combatant().is_armed() and ship.get_combatant().health.state.hull > 0.0
	_check(armed, "they carry their model's weapons and full defences, like any ship")
	var ids := {}
	for ship: NpcShip in a + b:
		ids[ship.combat_id] = true
	_check(ids.size() == 5, "every ship has its own combat id")

	var centre_a := Vector2.ZERO
	for ship: NpcShip in a:
		centre_a += ship.global_position / a.size()
	var centre_b := Vector2.ZERO
	for ship: NpcShip in b:
		centre_b += ship.global_position / b.size()
	_check(absf(centre_a.distance_to(centre_b) - CombatSandbox.BATTLE_SEPARATION) < 5.0, "the sides start %d px apart (%d)" % [CombatSandbox.BATTLE_SEPARATION, roundi(centre_a.distance_to(centre_b))])
	_check(facing, "they start facing each other")
	var apart := true
	for index in a.size():
		for other in range(index + 1, a.size()):
			var gap: float = a[index].global_position.distance_to(a[other].global_position)
			apart = apart and gap >= a[index].get_hit_radius() * 2.0
	_check(apart, "the ships of a side do not overlap")
	var exits := true
	for ship: NpcShip in a + b:
		exits = exits and ship.can_flee_by_jump()
	_check(exits, "the battle's ships know the ways out of the system, so one that retreats can jump out")
	var player_distance := _player.global_position.distance_to((centre_a + centre_b) / 2.0)
	_check(absf(player_distance - CombatSandbox.BATTLE_DISTANCE) < 5.0, "the battle is ahead of the player (%d px)" % roundi(player_distance))
	var hostile := (a[0] as NpcShip).get_combatant().is_hostile_to((b[0] as NpcShip).get_combatant())
	_check(hostile, "the Federation and Hegemony sides are hostile")

	_sandbox.clear_battle()
	await _frames()
	_check(_system.get_ships_root().get_child_count() == before, "clearing the battle removes its ships")
	_sandbox.clear_battle()
	_check(true, "clearing again does nothing")


func _test_battle_panel() -> void:
	_check(_battle.get_side_faction(0) == &"faction_1" and _battle.get_side_faction(1) == &"faction_2", "the panel starts with the Federation against the Hegemony")
	_check(_battle.describe() == "Nothing spawned.", "it starts with nothing spawned")
	var first_model: StringName = _battle.get_side_units(0)[0]["model"]
	_check(_battle.get_side_units(0).size() == 1 and _battle.get_side_units(0)[0]["count"] == 1, "each side starts with one ship of the first model")
	_check(_battle._paused_box.button_pressed, "the battle starts paused by default")
	_battle._on_spawn()
	await _frames()
	_check(_sandbox.is_battle_held() and _sandbox.get_tracker().elapsed == 0.0, "...so a spawned battle is held until START")
	var text := _battle.describe()
	_check(text.contains("A: 1 ships, B: 1 ships"), "it spawns one ship a side by default (%s)" % text.replace("\n", " | "))
	_check(text.contains("A and B: HOSTILE (at war)"), "and says the sides are at war")
	_check(text.contains("You and A: not hostile") and text.contains("You and B: not hostile"), "and that the player is nobody's enemy here")
	_battle._on_start_pressed()
	_check(not _sandbox.is_battle_held(), "START releases it")
	_battle._side_faction[1].select(3)  # pirates
	_check(_battle.get_side_faction(1) == &"faction_3", "side B can be the Pirates")
	_battle._side_faction[0].select(0)  # no faction
	_check(_battle.get_side_faction(0) == &"", "...and side A no faction")
	_battle._paused_box.button_pressed = false
	_battle.set_side_units(0, [{"model": first_model, "count": 2}])
	_battle._on_spawn()
	await _frames()
	_check(not _sandbox.is_battle_held(), "with the box off a battle goes at once")
	text = _battle.describe()
	_check(text.contains("A: 2 ships, B: 1 ships"), "a second battle replaces the first in the panel (%s)" % text.replace("\n", " | "))
	_check(text.contains("A and B: HOSTILE (pirates attack everyone)"), "pirates are hostile to ships that belong to nobody")
	_check(text.contains("You and B: HOSTILE (pirates attack everyone)"), "...and to the player")
	_check(_system.get_ships_root().get_child_count() == 5, "both battles' ships are still there until cleared (%d)" % _system.get_ships_root().get_child_count())
	_battle._on_clear()
	await _frames()
	_check(_system.get_ships_root().get_child_count() == 0 and _battle.describe() == "Nothing spawned.", "CLEAR removes them all")
	_battle._paused_box.button_pressed = true

	# --- The unit list: ships and composed units are added and removed.
	_battle._side_faction[0].select(1)
	_battle._side_faction[1].select(2)
	_battle.set_side_units(0, [])
	_battle._kind[0].select(0)
	_battle._fill_choice(0)
	_battle._choice[0].select(0)
	_battle._count[0].value = 3
	_battle._on_add(0)
	_battle._kind[0].select(1)
	_battle._fill_choice(0)
	var recipe_index := -1
	for index in _battle._recipes.size():
		if _battle._recipes[index].id == &"squadron":
			recipe_index = index
	_battle._choice[0].select(recipe_index)
	_battle._on_add(0)
	var units: Array = _battle.get_side_units(0)
	_check(units.size() == 2 and units[0]["count"] == 3 and units[1] == {"recipe": &"squadron"}, "units are added: 3 ships of a model, and a composed squadron (%s)" % [units])
	_check(_battle._side_list[0].item_count == 2 and _battle._side_list[0].get_item_text(1).begins_with("Unit:"), "...and listed")
	_battle._side_list[0].select(0)
	_battle._on_remove(0)
	_check(_battle.get_side_units(0).size() == 1 and _battle.get_side_units(0)[0].has("recipe"), "...and removed")
	_battle._side_profile[0].select(_profile_index(&"pirate") + 1)
	_check(_battle.get_side_spec(0)["profile"] == &"pirate" and _battle.get_side_spec(0)["faction"] == &"faction_1", "a side's spec carries its faction and its profile")
	_battle._side_profile[0].select(0)
	_check(not _battle.get_side_spec(0).has("profile"), "...and no profile when it is left as the unit's own")
	_battle.set_side_units(1, [{"model": first_model, "count": 1}])
	_battle._on_spawn()
	await _frames()
	var tracker := _sandbox.get_tracker()
	_check(tracker.start_count(0) >= 3 and tracker.start_count(1) == 1, "a battle with a composed unit spawns its ships (%d against %d)" % [tracker.start_count(0), tracker.start_count(1)])

	# --- The readout shows the score, and the overlay can be switched on.
	var readout: BattleReadout = _sandbox._readout
	await _frames(8)
	readout.refresh()  # (it redraws every 0.2 s: do not depend on how fast the frames go)
	_check(readout.visible and readout._text.text.contains("A: ") and readout._text.text.contains("HELD"), "the readout shows the held battle (%s)" % readout._text.text.replace("\n", " | "))
	readout._on_start_pressed()
	await _frames(8)
	readout.refresh()
	_check(readout._text.text.contains("FIGHTING") and readout._start_button.text == "HOLD", "...and its button starts it")
	_toolbar.toggle_panel(2)
	await _frames(3)
	_check(_sandbox.get_overlay().visible and _toolbar.get_button(2).button_pressed, "the overlay button turns the overlay on")
	_toolbar._unhandled_input(_key(KEY_F4))
	await _frames(2)
	_check(not _sandbox.get_overlay().visible and not _toolbar.get_button(2).button_pressed, "...and F4 turns it off")
	_toolbar._unhandled_input(_key(KEY_F4))
	await _frames(8)
	_check(_sandbox.get_overlay().visible and _battle.visible == _battle.open, "(the overlay is drawn without trouble)")
	_toolbar._unhandled_input(_key(KEY_F4))
	_battle._on_clear()
	await _frames(4)
	_check(not readout.visible, "the readout goes away when the battle is cleared")

	# --- The player's side, through the panel.
	var reputation: ReputationManager = _sandbox._main.get_node("Reputation")
	var federation: Faction = ContentRegistry.new().faction(&"faction_1")
	var before := reputation.get_reputation(federation)
	_battle._side_faction[0].select(1)
	_battle._side_faction[1].select(2)
	_battle.set_side_units(0, [{"model": first_model, "count": 1}])
	_battle._stance.select(1)  # with side A
	_battle._on_spawn()
	await _frames()
	_check(reputation.get_reputation(federation) >= CombatSandbox.STANCE_FRIENDLY, "standing with side A makes the player Friendly with its faction")
	_battle._stance_box.button_pressed = false
	_check(reputation.get_reputation(federation) == before, "...and the switch turns that off")
	_battle._stance_box.button_pressed = true
	_battle._on_clear()
	_battle._stance.select(0)
	_sandbox.set_player_stance(CombatSandbox.Stance.NEUTRAL)
	_check(reputation.get_reputation(federation) == before, "clearing leaves the reputation as it was")
	await _frames()


func _profile_index(id: StringName) -> int:
	for index in _battle._profiles.size():
		if _battle._profiles[index].id == id:
			return index
	return -1


func names_of(presets: Array) -> Array:
	return presets.map(func(preset: Dictionary) -> String: return preset["name"])


func _test_presets() -> void:
	var registry := ContentRegistry.new()
	var presets: Array = CombatSandbox.BATTLE_PRESETS
	_check(presets.size() >= 6, "the battle panel has presets (%d)" % presets.size())
	var valid := true
	for preset in presets:
		for side in [preset["a"], preset["b"]]:
			valid = valid and (side["faction"] == &"" or registry.faction(side["faction"]) != null)
			if side.has("units"):
				for entry in side["units"]:
					valid = valid and (registry.formation_recipe(entry["recipe"]) != null if entry.has("recipe") else registry.ship_stats(entry["model"]) != null)
				valid = valid and (not side.has("profile") or registry.tactical_profile(side["profile"]) != null)
				continue
			if side.has("plan"):
				valid = valid and registry.formation_recipe(side["plan"]["recipe"]) != null
				continue
			if side.has("formation"):
				valid = valid and registry.formation_shape(side["formation"]["shape"]) != null
				for model in side["formation"]["ships"]:
					valid = valid and registry.ship_stats(model) != null
				continue
			var entries: Array = side["ships"] if side.has("ships") else [side]
			for entry in entries:
				valid = valid and registry.ship_stats(entry["model"]) != null and entry["count"] >= 1
	_check(valid, "every preset names real ships and factions")
	var capitals := names_of(presets).filter(func(name: String) -> bool: return name.contains("capital"))
	_check(not capitals.is_empty(), "there is a capital ship v capital ship preset")
	var names := presets.map(func(preset: Dictionary) -> String: return preset["name"])
	_check(names.any(func(name: String) -> bool: return name.begins_with("1v1")) and names.any(func(name: String) -> bool: return name.begins_with("2v1")), "there are 1v1 and 2v1 presets")
	var before := _system.get_ships_root().get_child_count()
	var sides := _sandbox.spawn_battle_preset(0)
	await _frames()
	_check(sides["a"].size() == 1 and sides["b"].size() == 1 and _system.get_ships_root().get_child_count() == before + 2, "the first preset (1v1) spawns two ships")
	_sandbox.clear_battle()

	# --- A preset whose sides are squadrons under their commanders.
	var squads := 0
	for index in CombatSandbox.BATTLE_PRESETS.size():
		if CombatSandbox.BATTLE_PRESETS[index]["name"].begins_with("Squadrons"):
			squads = index
	await _frames(3)  # (the first preset's ships are freed)
	before = _system.get_ships_root().get_child_count()
	var units := _sandbox.spawn_battle_preset(squads)
	await _frames()
	_check(units["a"].size() == 4 and units["b"].size() == 4 and _system.get_ships_root().get_child_count() == before + 8, "the squadron preset spawns two squadrons of four (%d, %d, root %d from %d)" % [units["a"].size(), units["b"].size(), _system.get_ships_root().get_child_count(), before])
	var unit: Formation = units["a"][0].led_formation if units["a"][0].led_formation != null else units["a"][0].formation
	_check(unit != null and unit.commander != null, "...each in a formation with a commander")
	var formations_before := _system.get_formations_root().get_child_count()
	_sandbox.clear_battle()
	await _frames(3)
	_check(_system.get_formations_root().get_child_count() < formations_before, "clearing the battle removes the formations too")

	# --- Presets with a whole battle group, and a whole fleet, on each side.
	for index in CombatSandbox.BATTLE_PRESETS.size():
		var preset_name: String = CombatSandbox.BATTLE_PRESETS[index]["name"]
		if preset_name.begins_with("Battle groups") or preset_name.begins_with("Capital fleets"):
			var big_sides := _sandbox.spawn_battle_preset(index)
			await _frames(3)
			var key := "Battle groups" if preset_name.begins_with("Battle groups") else "Capital fleets"
			var a_ships: Array = big_sides["a"]
			var fleet_ok := true
			if key == "Capital fleets":
				fleet_ok = a_ships[0].fleet != null and a_ships[0].fleet.commander != null
			else:
				fleet_ok = a_ships[0].formation != null or a_ships[0].led_formation != null
			_check(big_sides["a"].size() >= 8 and big_sides["b"].size() >= 8 and fleet_ok, "the %s preset spawns two big units under their commanders (%d and %d ships)" % [key.to_lower(), big_sides["a"].size(), big_sides["b"].size()])
			var apart: float = (big_sides["a"][0] as NpcShip).global_position.distance_to((big_sides["b"][0] as NpcShip).global_position)
			_check(apart > 2000.0, "...far enough apart not to overlap (%d px)" % apart)
			_sandbox.clear_battle()
			await _frames(3)
	await _frames()
	var two_on_one := _sandbox.spawn_battle_preset(1)
	await _frames()
	_check(two_on_one["a"].size() == 2 and two_on_one["b"].size() == 1, "the 2v1 preset spawns two against one")
	_sandbox.clear_battle()
	await _frames()
	# The mixed fleets: 1 cruiser, 2 frigates and 5 fighters against 1 cruiser, 2 frigates,
	# 1 heavy fighter and 3 fighters, in ranks.
	var fleets := -1
	for index in presets.size():
		if str(presets[index]["name"]).begins_with("Fleets"):
			fleets = index
	_check(fleets >= 0, "there is a preset of two mixed fleets")
	var big := _sandbox.spawn_battle_preset(fleets)
	await _frames()
	var counts := {}
	for ship: NpcShip in big["a"]:
		counts[ship.ship_type.stats.id] = counts.get(ship.ship_type.stats.id, 0) + 1
	_check(big["a"].size() == 8 and counts.get(&"federation_fighter", 0) == 5 and counts.get(&"federation_frigate", 0) == 2 and counts.get(&"federation_cruiser", 0) == 1, "side A is 1 cruiser, 2 frigates and 5 fighters (%s)" % [counts])
	counts = {}
	for ship: NpcShip in big["b"]:
		counts[ship.ship_type.stats.id] = counts.get(ship.ship_type.stats.id, 0) + 1
	_check(big["b"].size() == 7 and counts.get(&"hegemony_fighter", 0) == 3 and counts.get(&"hegemony_heavy_fighter", 0) == 1 and counts.get(&"hegemony_frigate", 0) == 2 and counts.get(&"hegemony_cruiser", 0) == 1, "side B is 1 cruiser, 2 frigates, 1 heavy fighter and 3 fighters (%s)" % [counts])
	var all_federation := true
	for ship: NpcShip in big["a"]:
		all_federation = all_federation and ship.faction_id == &"faction_1"
	for ship: NpcShip in big["b"]:
		all_federation = all_federation and ship.faction_id == &"faction_2"
	_check(all_federation, "...each side under its own faction")
	# The big ship is at the back of its side, the fighters in front (nearer the enemy).
	var fighter_a: NpcShip = big["a"][0]
	var cruiser_a: NpcShip = big["a"][big["a"].size() - 1]
	var enemy_middle: Vector2 = (big["b"][0] as NpcShip).global_position
	_check(fighter_a.global_position.distance_to(enemy_middle) < cruiser_a.global_position.distance_to(enemy_middle), "the fighters start in front of their cruiser")
	_sandbox.clear_battle()
	await _frames()
	_battle._preset.select(1)
	_battle._on_spawn_preset()
	await _frames()
	_check(_battle.describe().contains("A: 2 ships, B: 1 ships"), "the panel spawns a preset from its list (%s)" % _battle.describe().replace("
", " | "))
	_battle._on_clear()
	await _frames()
	_check(_system.get_ships_root().get_child_count() == 0, "...and clears it")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
