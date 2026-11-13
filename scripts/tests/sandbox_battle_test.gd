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

	print("SANDBOX BATTLE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _frames(count: int = 2) -> void:
	for i in count:
		await process_frame


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
	_check(_formations.visible, "...and the two panels can be open together")
	_toolbar._unhandled_input(_key(KEY_G))
	await _frames()
	_check(_battle.open and _formations.open, "other keys do nothing")

	paused = true
	await _frames()
	_check(not _battle.visible and not _formations.visible and not _toolbar.visible, "everything hides while the game is paused")
	paused = false
	await _frames()
	_check(_battle.visible and _formations.visible and _toolbar.visible, "...and comes back")
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
	_battle._on_spawn()
	await _frames()
	var text := _battle.describe()
	_check(text.contains("A: 1 ships, B: 1 ships"), "it spawns one ship a side by default (%s)" % text.replace("\n", " | "))
	_check(text.contains("A and B: HOSTILE (at war)"), "and says the sides are at war")
	_check(text.contains("You and A: not hostile") and text.contains("You and B: not hostile"), "and that the player is nobody's enemy here")
	_battle._side_faction[1].select(3)  # pirates
	_check(_battle.get_side_faction(1) == &"faction_3", "side B can be the Pirates")
	_battle._side_faction[0].select(0)  # no faction
	_check(_battle.get_side_faction(0) == &"", "...and side A no faction")
	_battle._side_count[0].value = 2
	_battle._on_spawn()
	await _frames()
	text = _battle.describe()
	_check(text.contains("A: 2 ships, B: 1 ships"), "a second battle replaces the first in the panel (%s)" % text.replace("\n", " | "))
	_check(text.contains("A and B: HOSTILE (pirates attack everyone)"), "pirates are hostile to ships that belong to nobody")
	_check(text.contains("You and B: HOSTILE (pirates attack everyone)"), "...and to the player")
	_check(_system.get_ships_root().get_child_count() == 5, "both battles' ships are still there until cleared (%d)" % _system.get_ships_root().get_child_count())
	_battle._on_clear()
	await _frames()
	_check(_system.get_ships_root().get_child_count() == 0 and _battle.describe() == "Nothing spawned.", "CLEAR removes them all")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
