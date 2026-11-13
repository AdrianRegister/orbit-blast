extends SceneTree
## Tests who counts as an ally (Allegiance, AllegianceRules) and the evasive flag on
## ship classes. Pure: no scenes are run.
##   Godot --headless --path . --script res://scripts/tests/allegiance_test.gd </dev/null

var _failures: int = 0
var _reputation: Dictionary = {}  # faction id -> the player's reputation


func _init() -> void:
	var rules := AllegianceRules.shared()
	_check(rules != null and rules.validate().is_empty(), "the allegiance rules load and validate %s" % [rules.validate()])
	_check(rules.min_reputation == 40, "the player is an ally from Friendly upward (40)")
	var registry := ContentRegistry.new()
	_check(registry.problems.is_empty(), "the content registry builds with no problems %s" % [registry.problems])
	var standings: ReputationStandings = load(ReputationManager.STANDINGS_PATH)
	_check(standings.get_standing_name(rules.min_reputation) == "Friendly", "40 is where Friendly begins")

	_test_factions(rules)
	_test_player(rules)
	_test_bad_rules()
	_test_evasive_classes(registry)

	print("ALLEGIANCE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _ship(faction: StringName, is_player: bool = false) -> Combatant:
	var combatant := Combatant.new()
	combatant.faction_id = faction
	combatant.is_player = is_player
	return combatant


func _lookup(faction_id: StringName):
	return _reputation.get(faction_id)


func _test_factions(rules: AllegianceRules) -> void:
	var allegiance := Allegiance.new()
	allegiance.setup(rules)
	var first := _ship(&"faction_1")
	var second := _ship(&"faction_1")
	var other := _ship(&"faction_2")
	var nobody := _ship(&"")
	var also_nobody := _ship(&"")
	_check(allegiance.are_allies(first, second), "two ships of the same faction are allies")
	_check(allegiance.are_allies(second, first), "... both ways")
	_check(not allegiance.are_allies(first, other), "ships of different factions are not")
	_check(not allegiance.are_allies(other, first), "... both ways")
	_check(not allegiance.are_allies(nobody, also_nobody), "two ships that belong to nobody are not allies")
	_check(not allegiance.are_allies(nobody, first) and not allegiance.are_allies(first, nobody), "nor is a ship with no faction an ally of one with a faction")
	_check(allegiance.are_allies(first, first) and allegiance.are_allies(nobody, nobody), "a ship is its own ally")
	_check(not allegiance.are_allies(null, first) and not allegiance.are_allies(first, null), "nothing is an ally of null")
	for combatant in [first, second, other, nobody, also_nobody]:
		combatant.free()


func _test_player(rules: AllegianceRules) -> void:
	var allegiance := Allegiance.new()
	allegiance.setup(rules, _lookup)
	var player := _ship(&"", true)
	var friendly := _ship(&"faction_1")
	var other := _ship(&"faction_2")
	var nobody := _ship(&"")

	_reputation = {&"faction_1": 40, &"faction_2": 0}
	_check(allegiance.are_allies(player, friendly), "the player is an ally of a faction at the threshold")
	_check(allegiance.are_allies(friendly, player), "... and the faction's ships are the player's allies (symmetric)")
	_check(not allegiance.are_allies(player, other), "the player is not an ally of a faction they are neutral with")
	_reputation[&"faction_1"] = 39
	_check(not allegiance.are_allies(player, friendly), "one below the threshold is not enough")
	_reputation[&"faction_1"] = 100
	_check(allegiance.are_allies(player, friendly), "well above it is")
	_reputation[&"faction_1"] = -100
	_check(not allegiance.are_allies(player, friendly), "a hated faction is not an ally")
	_reputation[&"faction_2"] = 80
	_check(allegiance.are_allies(player, other) and not allegiance.are_allies(player, friendly), "each faction is judged by its own reputation")
	_check(not allegiance.are_allies(player, nobody), "a ship that belongs to nobody is never the player's ally")
	_reputation = {}
	_check(not allegiance.are_allies(player, friendly), "a faction the lookup does not know is not an ally")

	var without := Allegiance.new()
	without.setup(rules)
	_check(not without.are_allies(player, friendly), "with no reputation (the sandbox) the player has no allies")
	_check(without.are_allies(friendly, friendly), "... but ships still have their own factions")

	# The threshold is data.
	var strict := AllegianceRules.new()
	strict.min_reputation = 90
	var strict_allegiance := Allegiance.new()
	strict_allegiance.setup(strict, _lookup)
	_reputation = {&"faction_1": 60}
	_check(allegiance.are_allies(player, friendly) and not strict_allegiance.are_allies(player, friendly), "the threshold comes from the rules, not from code")
	_reputation = {}
	for combatant in [player, friendly, other, nobody]:
		combatant.free()


func _test_bad_rules() -> void:
	var bad := AllegianceRules.new()
	bad.min_reputation = 0
	_check(not bad.validate().is_empty(), "a threshold at the starting reputation (everyone an ally) is invalid")
	bad.min_reputation = 500
	_check(not bad.validate().is_empty(), "a threshold above the scale is invalid")


func _test_evasive_classes(registry: ContentRegistry) -> void:
	for id in [&"fighter", &"heavy_fighter"]:
		_check(registry.ship_class(id).is_evasive(), "%s ships slip past medium and heavy weapons" % id)
	for id in [&"interceptor", &"gunboat", &"corvette", &"light_frigate", &"frigate", &"cruiser", &"capital_ship",
			&"freighter", &"bulk_freighter", &"shuttle", &"warship", &"cargo_ship"]:
		_check(not registry.ship_class(id).is_evasive(), "%s does not" % id)
	for model in registry.all_ship_stats():
		var expected: bool = model.ship_class.id in [&"fighter", &"heavy_fighter"]
		_check(model.ship_class.is_evasive() == expected, "%s: evasive is %s" % [model.id, expected])
	# It is inherited from a parent, like the other flags.
	var parent := ShipClass.new()
	parent.id = &"x"
	parent.evades_heavy_fire = true
	var child := ShipClass.new()
	child.id = &"y"
	child.parent = parent
	_check(child.is_evasive(), "a class inherits evasiveness from its parent")
	_check(not ShipClass.new().is_evasive(), "a new class is not evasive")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
