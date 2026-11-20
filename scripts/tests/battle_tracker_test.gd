extends SceneTree
## Tests the battle tracker, the sandbox's player stance and held battles, and the headless battle
## harness, in the real game scene: ships left, strength left, losses, ships that got away, kills,
## the clock, the winner; the player on a side of the battle through reputation (and the switch that
## turns it off); battles that start held and are released; and that the harness gives a repeatable
## winner across seeds and a mirrored battle the mirrored winner. Run with:
##   Godot --headless --path . --script res://scripts/tests/battle_tracker_test.gd </dev/null

var _failures: int = 0
var _harness: BattleHarness
var _sandbox: CombatSandbox
var _tracker: BattleTracker
var _main: Main


func _init() -> void:
	_harness = BattleHarness.new()
	await _harness.start(self)
	_sandbox = _harness.sandbox
	_tracker = _harness.tracker
	_main = _harness.main

	await _test_tracker()
	await _test_held()
	await _test_stance()
	await _test_harness()
	_harness.finish()

	print("BATTLE TRACKER TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _side(faction: StringName, model: StringName, count: int) -> Dictionary:
	return {"faction": faction, "model": model, "count": count}


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_until(condition: Callable, limit: float) -> bool:
	Engine.time_scale = 5.0
	var waited := 0.0
	while waited < limit and not condition.call():
		await create_timer(0.5).timeout
		waited += 0.5
	Engine.time_scale = 1.0
	return condition.call()


func _test_tracker() -> void:
	var centre := _main.get_system().global_position
	_sandbox.spawn_battle(_side(&"faction_1", &"federation_fighter", 3), _side(&"faction_2", &"hegemony_fighter", 2), {"anchor": centre, "held": true})
	await process_frame
	_check(_tracker.has_battle() and _tracker.start_count(0) == 3 and _tracker.start_count(1) == 2, "a spawned battle is tracked: 3 ships against 2")
	_check(_tracker.alive_count(0) == 3 and _tracker.alive_count(1) == 2 and _tracker.winner() == &"", "all of them are in the fight and nobody has won")
	var rating: float = CombatRating.of(load("res://resources/ships/federation_fighter_stats.tres"))
	_check(is_equal_approx(_tracker.start_rating(0), 3.0 * rating) and is_equal_approx(_tracker.rating_left(0), _tracker.start_rating(0)), "the strength of a side is the sum of its ships' ratings (%d)" % _tracker.start_rating(0))
	_check(_tracker.elapsed == 0.0, "the clock has not started: the battle is held")
	var ships: Array = _tracker._ships[1]
	_sandbox.kill_ship(ships[0])
	await process_frame
	await process_frame
	_check(_tracker.alive_count(1) == 1 and _tracker.lost_count(1) == 1 and _tracker.withdrawn_count(1) == 0, "a destroyed ship is lost, not withdrawn")
	_check(_tracker.rating_left(1) < _tracker.start_rating(1) and _tracker.winner() == &"", "...and its strength goes down")
	# A ship that jumps out has withdrawn.
	var leaver: NpcShip = ships[1]
	leaver.process_mode = Node.PROCESS_MODE_INHERIT
	leaver.global_position = centre + Vector2(_main.get_system().jump_radius + 100.0, 0.0)
	leaver.begin_jump_out()
	await process_frame
	_check(_tracker.alive_count(1) == 0 and _tracker.withdrawn_count(1) == 1 and _tracker.winner() == &"a", "a ship that jumps out has withdrawn, and with nothing left side B is beaten: A wins")
	_check(_tracker.describe_side(0).begins_with("A: 3 of 3 ships") and _tracker.describe_side(1).contains("1 lost") and _tracker.describe_side(1).contains("1 away"), "the readout says it (%s)" % _tracker.describe_side(1))
	_sandbox.clear_battle()
	await process_frame
	_check(not _tracker.has_battle() and _tracker.winner() == &"", "clearing the battle clears the score")
	# Kills are credited to the side whose ship made them.
	_sandbox.spawn_battle(_side(&"faction_1", &"federation_cruiser", 1), _side(&"faction_2", &"hegemony_fighter", 1), {"anchor": centre})
	var decided := await _wait_until(func() -> bool: return _tracker.winner() != &"", 120.0)
	_check(decided and _tracker.winner() != &"draw", "a battle between a cruiser and a fighter is decided (%s)" % _tracker.winner())
	var winner_side := 0 if _tracker.winner() == &"a" else 1
	var loser_side := 1 - winner_side
	# (The beaten ship was either destroyed, which is the winner's kill, or it ran and jumped out.)
	_check(_tracker.kills(loser_side) == 0 and _tracker.kills(winner_side) + _tracker.withdrawn_count(loser_side) == 1 and _tracker.lost_count(loser_side) == _tracker.kills(winner_side), "the beaten ship was destroyed and the winning side credited, or it got away (kills %d, away %d)" % [_tracker.kills(winner_side), _tracker.withdrawn_count(loser_side)])
	_check(_tracker.elapsed > 0.0, "the clock ran")
	_sandbox.clear_battle()
	await process_frame


func _test_held() -> void:
	var centre := _main.get_system().global_position
	_sandbox.spawn_battle(_side(&"faction_1", &"federation_fighter", 1), _side(&"faction_2", &"hegemony_fighter", 1), {"anchor": centre, "held": true})
	var ship: NpcShip = _tracker._ships[0][0]
	var start := ship.global_position
	await _wait(2.0)
	_check(_sandbox.is_battle_held() and ship.global_position.distance_to(start) < 1.0 and _tracker.elapsed == 0.0, "a held battle does not move or run the clock")
	_sandbox.start_battle()
	await _wait(3.0)
	_check(not _sandbox.is_battle_held() and ship.global_position.distance_to(start) > 20.0 and _tracker.elapsed > 1.0, "...and starts when released")
	_sandbox.hold_battle(true)
	await process_frame
	var frozen_at := ship.global_position
	await _wait(1.0)
	_check(ship.global_position.distance_to(frozen_at) < 1.0, "...and can be held again in the middle of the battle")
	_sandbox.clear_battle()
	await process_frame
	# Composed units are held too, with their commanders.
	_sandbox.spawn_battle({"faction": &"faction_1", "units": [{"recipe": &"squadron"}]}, {"faction": &"faction_2", "units": [{"recipe": &"squadron"}]}, {"anchor": centre, "held": true})
	var lead: NpcShip = _tracker._ships[0][0]
	var lead_start := lead.global_position
	await _wait(2.0)
	var unit: Formation = lead.led_formation if lead.led_formation != null else lead.formation
	_check(lead.global_position.distance_to(lead_start) < 1.0 and unit != null and unit.process_mode == Node.PROCESS_MODE_DISABLED, "composed units are held with their commanders")
	_check(_tracker.start_count(0) >= 3 and _tracker.start_count(1) >= 3, "(setup) the composed squadrons have ships (%d, %d)" % [_tracker.start_count(0), _tracker.start_count(1)])
	_sandbox.clear_battle()
	await process_frame


func _test_stance() -> void:
	var centre := _main.get_system().global_position
	var registry := ContentRegistry.new()
	var reputation: ReputationManager = _main.get_node("Reputation")
	var federation: Faction = registry.faction(&"faction_1")
	var hegemony: Faction = registry.faction(&"faction_2")
	var combat: CombatManager = _main.get_node("Combat")
	var before_f := reputation.get_reputation(federation)
	var before_h := reputation.get_reputation(hegemony)
	_sandbox.set_stance_uses_reputation(true)
	_sandbox.set_player_stance(CombatSandbox.Stance.SIDE_A)
	_sandbox.spawn_battle(_side(&"faction_1", &"federation_fighter", 1), _side(&"faction_2", &"hegemony_fighter", 1), {"anchor": centre, "held": true})
	await process_frame
	var a: Combatant = _tracker._ships[0][0].get_combatant()
	var b: Combatant = _tracker._ships[1][0].get_combatant()
	var player: Combatant = _main.get_player_ship().combatant
	var hostility := combat.get_hostility()
	_check(reputation.get_reputation(federation) >= CombatSandbox.STANCE_FRIENDLY and reputation.get_reputation(hegemony) <= CombatSandbox.STANCE_HOSTILE, "standing with side A is made Friendly and with side B Hostile through reputation (%d, %d)" % [reputation.get_reputation(federation), reputation.get_reputation(hegemony)])
	_check(hostility.are_hostile(b, player) and not hostility.are_hostile(a, player), "...so side B is hostile to the player and side A is not (the real rules)")
	_sandbox.set_player_stance(CombatSandbox.Stance.SIDE_B)
	_check(hostility.are_hostile(a, player) and not hostility.are_hostile(b, player), "standing with side B turns it round")
	_sandbox.set_stance_uses_reputation(false)
	_check(reputation.get_reputation(federation) == before_f and reputation.get_reputation(hegemony) == before_h, "with the switch off the reputation is put back")
	_check(not hostility.are_hostile(a, player) and not hostility.are_hostile(b, player), "...and the player is neutral to both")
	_sandbox.set_stance_uses_reputation(true)
	_sandbox.set_player_stance(CombatSandbox.Stance.NEUTRAL)
	_check(reputation.get_reputation(federation) == before_f and reputation.get_reputation(hegemony) == before_h and not hostility.are_hostile(b, player), "a neutral stance changes nothing")
	_sandbox.set_player_stance(CombatSandbox.Stance.SIDE_A)
	_sandbox.clear_battle()
	await process_frame
	_check(reputation.get_reputation(federation) == before_f and reputation.get_reputation(hegemony) == before_h, "clearing the battle restores the reputation")
	_sandbox.set_player_stance(CombatSandbox.Stance.NEUTRAL)


func _test_harness() -> void:
	var strong := {"faction": &"faction_1", "model": &"federation_heavy_fighter", "count": 3}
	var weak := {"faction": &"faction_2", "model": &"hegemony_fighter", "count": 1}
	var wins := 0
	var consistent := true
	for battle_seed in [1, 2, 3]:
		var result := await _harness.run(strong, weak, battle_seed, 120.0)
		wins += 1 if result["winner"] == &"a" else 0
		var a: Dictionary = result["a"]
		var b: Dictionary = result["b"]
		consistent = consistent and a["alive"] + a["lost"] + a["withdrawn"] == a["start"] and b["alive"] + b["lost"] + b["withdrawn"] == b["start"]
		consistent = consistent and result["time"] > 0.0 and result["time"] < 120.0
	_check(wins == 3, "three heavy fighters beat one fighter on every seed (%d of 3)" % wins)
	_check(consistent, "every result adds up (alive + lost + withdrawn = start) and ends before the limit")
	var mirrored := await _harness.run(weak, strong, 1, 120.0)
	_check(mirrored["winner"] == &"b", "the same battle with the sides swapped is won by the other side")
	_check(mirrored["b"]["alive"] > 0 and mirrored["b"]["rating_left"] <= mirrored["b"]["rating_start"], "the survivors' strength is reported")
	# A battle that cannot be decided in time says so.
	var stalemate := await _harness.run({"faction": &"faction_1", "model": &"federation_capital_ship", "count": 1}, {"faction": &"faction_2", "model": &"hegemony_capital_ship", "count": 1}, 1, 5.0)
	_check(stalemate["winner"] == &"timeout" and stalemate["time"] >= 5.0, "a battle not decided within the time limit says so (%s after %d s)" % [stalemate["winner"], stalemate["time"]])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
