class_name BattleHarness
extends RefCounted
## Runs sandbox battles headless, fast and repeatably, and reports who won. Used by the balancing
## tools (tools/balance_matrix.gd) and by tests that must not depend on the luck of one fight.
##
## It builds the combat sandbox (the real game scene), parks the player far away so nobody
## notices them, and for each run: seeds the random numbers, spawns the two sides centred on the
## middle of the system, raises the time scale, waits for the BattleTracker to name a winner (or
## for the time limit), reads the score, and clears everything. A side is a battle side as in
## BattlePresets. Everything it does is async: call it with `await` from a SceneTree script.
##
##   var harness := BattleHarness.new()
##   await harness.start(self)               # `self` is the SceneTree
##   var result := await harness.run(side_a, side_b, 1)
##   harness.finish()
##
## A result is {"winner": &"a" / &"b" / &"draw" / &"timeout", "time": game seconds, and for each of
## "a" and "b": "alive", "lost", "withdrawn", "kills", "rating_left", "rating_start", "start"}.

const PARKED := Vector2(30000.0, 30000.0)

var time_scale: float = 5.0
var tree: SceneTree
var main: Main
var sandbox: CombatSandbox
var tracker: BattleTracker
var _combat: CombatManager


## Builds the sandbox. Call first, with the SceneTree.
func start(scene_tree: SceneTree) -> void:
	tree = scene_tree
	main = CombatSandbox.build_main()
	tree.root.add_child(main)
	for i in 6:
		await tree.process_frame
	for child in main.get_children():
		if child is CombatSandbox:
			sandbox = child
	tracker = sandbox.get_tracker()
	_combat = main.get_node("Combat")
	main.get_player_ship().global_position = PARKED
	await _clear()


## Runs one battle and returns its result (see above). `time_limit` is in game seconds.
func run(side_a: Dictionary, side_b: Dictionary, battle_seed: int, time_limit: float = 180.0) -> Dictionary:
	seed(battle_seed)
	await _clear()
	var centre: Vector2 = main.get_system().global_position
	sandbox.spawn_battle(side_a, side_b, {"anchor": centre})
	Engine.time_scale = time_scale
	while tracker.winner() == &"" and tracker.elapsed < time_limit:
		await tree.create_timer(0.5).timeout
	var result := _result()
	Engine.time_scale = 1.0
	await _clear()
	return result


## Puts the time scale back and removes the sandbox. Call when done.
func finish() -> void:
	Engine.time_scale = 1.0
	if main != null and is_instance_valid(main):
		main.queue_free()


func _result() -> Dictionary:
	var winner := tracker.winner()
	if winner == &"":
		winner = &"timeout"
	var result := {"winner": winner, "time": tracker.elapsed}
	for side in 2:
		result["ab"[side]] = {
			"alive": tracker.alive_count(side), "lost": tracker.lost_count(side),
			"withdrawn": tracker.withdrawn_count(side), "kills": tracker.kills(side),
			"rating_left": tracker.rating_left(side), "rating_start": tracker.start_rating(side),
			"start": tracker.start_count(side),
		}
	return result


func _clear() -> void:
	sandbox.clear_formations()
	sandbox.clear_battle()
	for ship in main.get_system().get_ships_root().get_children():
		ship.queue_free()
	await tree.process_frame
	await tree.process_frame
	_combat.get_hostility().clear()
	_combat.get_picture().refresh()
