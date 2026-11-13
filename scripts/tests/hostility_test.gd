extends SceneTree
## Tests who is hostile to whom (Hostility, HostilityRules): war, pirates, the
## player's reputation, grudges between sides, and that allies are never hostile.
## Pure: no scenes are run.
##   Godot --headless --path . --script res://scripts/tests/hostility_test.gd </dev/null

var _failures: int = 0
var _reputation: Dictionary = {}  # faction id -> the player's reputation
var _factions: Dictionary = {}  # faction id -> Faction
var _time: float = 0.0
var _next_id: int = 0


func _init() -> void:
	var rules := HostilityRules.shared()
	_check(rules != null and rules.validate().is_empty(), "the hostility rules load and validate %s" % [rules.validate()])
	var registry := ContentRegistry.new()
	_check(registry.problems.is_empty(), "the content registry builds with no problems %s" % [registry.problems])
	var standings: ReputationStandings = load(ReputationManager.STANDINGS_PATH)
	_check(standings.get_standing_name(rules.attack_player_reputation) == "Hostile", "the player is attacked on sight from Hostile downward (%d)" % rules.attack_player_reputation)
	for faction in registry.factions():
		_factions[faction.id] = faction
	_add_faction(&"x")  # (made-up factions with no relations)
	_add_faction(&"y")
	_add_faction(&"z")

	_test_rules()
	_test_war()
	_test_pirates()
	_test_player_reputation(rules)
	_test_grudges(rules)
	_test_sides()
	_test_allies_and_edges()

	print("HOSTILITY TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------------- helpers

func _add_faction(id: StringName) -> Faction:
	var faction := Faction.new()
	faction.id = id
	faction.display_name = str(id)
	_factions[id] = faction
	return faction


func _faction(id: StringName) -> Faction:
	return _factions.get(id)


func _rep(faction_id: StringName):
	return _reputation.get(faction_id)


func _clock() -> float:
	return _time


## A Hostility wired like the CombatManager wires it. `with_reputation` false is the
## sandbox, where there is no reputation.
func _hostility(with_reputation: bool = true) -> Hostility:
	_reputation = {}
	_time = 0.0
	var allegiance := Allegiance.new()
	allegiance.setup(AllegianceRules.shared(), _rep if with_reputation else Callable())
	var hostility := Hostility.new()
	hostility.setup(HostilityRules.shared(), allegiance, _faction, _rep if with_reputation else Callable(), _clock)
	return hostility


func _ship(faction: StringName, is_player: bool = false) -> Combatant:
	var combatant := Combatant.new()
	combatant.faction_id = faction
	combatant.is_player = is_player
	_next_id += 1
	combatant.combat_id = StringName("ship_%d" % _next_id)
	return combatant


# ----------------------------------------------------------------------- tests

func _test_rules() -> void:
	var bad := HostilityRules.new()
	bad.attack_player_reputation = 0
	_check(not bad.validate().is_empty(), "attacking at neutral reputation is rejected")
	bad.attack_player_reputation = 50
	_check(not bad.validate().is_empty(), "attacking friendly players is rejected")
	bad.attack_player_reputation = -500
	_check(not bad.validate().is_empty(), "a reputation off the scale is rejected")
	bad.attack_player_reputation = -80
	bad.grudge_seconds = 0.0
	_check(not bad.validate().is_empty(), "a grudge that lasts no time is rejected")


func _test_war() -> void:
	var hostility := _hostility()
	var federation := _ship(&"faction_1")
	var other_federation := _ship(&"faction_1")
	var hegemony := _ship(&"faction_2")
	_check(hostility.are_hostile(federation, hegemony), "the Federation and the Hegemony are at war, so their ships are hostile")
	_check(hostility.are_hostile(hegemony, federation), "...both ways")
	_check(hostility.get_reason(federation, hegemony) == Hostility.REASON_WAR, "...because of the war")
	_check(not hostility.are_hostile(federation, other_federation), "ships of one faction are not hostile to each other")

	var x := _ship(&"x")
	var y := _ship(&"y")
	var z := _ship(&"z")
	_check(not hostility.are_hostile(x, y) and not hostility.are_hostile(y, x), "factions with no relation are at peace")
	var relation := FactionRelation.new()
	relation.other_faction_id = &"y"
	relation.at_war = true
	_faction(&"x").relations = [relation]
	_check(hostility.are_hostile(x, y) and hostility.are_hostile(y, x), "a war declared by one faction alone makes both sides hostile")
	_check(not hostility.are_hostile(x, z) and not hostility.are_hostile(y, z), "...and only those two")
	relation.at_war = false
	relation.attitude = -100
	_check(not hostility.are_hostile(x, y), "a bad attitude without a war is not hostility")
	_faction(&"x").relations = []
	for ship in [federation, other_federation, hegemony, x, y, z]:
		ship.free()


func _test_pirates() -> void:
	var hostility := _hostility()
	var pirates := _faction(&"faction_3")
	_check(pirates != null and pirates.hostile_to_all and pirates.validate().is_empty(), "the Pirates exist and are hostile to all")
	_check(not _faction(&"faction_1").hostile_to_all and not _faction(&"faction_2").hostile_to_all, "...and nobody else is")
	var pirate := _ship(&"faction_3")
	var other_pirate := _ship(&"faction_3")
	var federation := _ship(&"faction_1")
	var hegemony := _ship(&"faction_2")
	var civilian := _ship(&"")
	var player := _ship(&"", true)
	_check(hostility.get_reason(pirate, federation) == Hostility.REASON_PIRATES and hostility.are_hostile(federation, pirate), "pirates are hostile to a Federation ship, both ways")
	_check(hostility.are_hostile(pirate, hegemony), "...and to a Hegemony ship")
	_check(hostility.are_hostile(pirate, civilian) and hostility.are_hostile(civilian, pirate), "...and to a ship that belongs to nobody")
	_check(hostility.are_hostile(pirate, player), "...and to the player, whatever the player's reputation")
	_check(not hostility.are_hostile(pirate, other_pirate), "pirates are allies of each other")
	for ship in [pirate, other_pirate, federation, hegemony, civilian, player]:
		ship.free()


func _test_player_reputation(rules: HostilityRules) -> void:
	var hostility := _hostility()
	var player := _ship(&"", true)
	var federation := _ship(&"faction_1")
	var other := _ship(&"x")
	_check(not hostility.are_hostile(player, federation), "a new player (reputation 0) is not attacked")
	_reputation[&"faction_1"] = rules.attack_player_reputation + 1
	_check(not hostility.are_hostile(player, federation), "...nor one just above the threshold")
	_reputation[&"faction_1"] = rules.attack_player_reputation
	_check(hostility.are_hostile(player, federation) and hostility.are_hostile(federation, player), "at the threshold (Hostile) the faction's ships attack the player, both ways")
	_check(hostility.get_reason(player, federation) == Hostility.REASON_REPUTATION, "...because of reputation")
	_reputation[&"faction_1"] = -100
	_check(hostility.are_hostile(player, federation), "at the bottom of the scale too")
	_check(not hostility.are_hostile(player, other), "reputation with one faction does not turn another faction hostile")
	_reputation[&"faction_1"] = 40
	_check(not hostility.are_hostile(player, federation), "a friendly player is the faction's ally, not hostile")
	_check(not hostility.are_hostile(player, _ship(&"")), "a ship that belongs to nobody is never hostile to the player by reputation")
	var other_player := _ship(&"", true)
	_check(not hostility.are_hostile(player, other_player), "two players are not hostile")

	# The sandbox has no reputation: the player is simply nobody's enemy.
	var sandbox := _hostility(false)
	_check(not sandbox.are_hostile(player, federation), "with no reputation at all the player is not attacked")
	for ship in [player, federation, other, other_player]:
		ship.free()


func _test_grudges(rules: HostilityRules) -> void:
	var hostility := _hostility()
	var player := _ship(&"", true)
	var first := _ship(&"x")
	var second := _ship(&"x")
	var bystander := _ship(&"y")
	_check(not hostility.are_hostile(player, first), "(setup) the player and a faction at peace")
	hostility.record_attack(player, first)
	_check(hostility.are_hostile(player, first) and hostility.are_hostile(first, player), "when the player attacks a ship, it and the player are hostile, both ways")
	_check(hostility.get_reason(first, player) == Hostility.REASON_GRUDGE, "...because of a grudge")
	_check(hostility.are_hostile(player, second), "...and so is the rest of its faction")
	_check(not hostility.are_hostile(player, bystander), "...but not another faction")
	_check(not hostility.are_hostile(first, bystander), "...and the factions stay at peace with each other")

	_time = rules.grudge_seconds - 1.0
	_check(hostility.are_hostile(player, first), "the grudge lasts for its time")
	hostility.record_attack(player, second)
	_time = rules.grudge_seconds + 30.0
	_check(hostility.are_hostile(player, first), "...and another attack renews it")
	_time = rules.grudge_seconds - 1.0 + rules.grudge_seconds + 1.0
	_check(not hostility.are_hostile(player, first), "...but it ends in the end")

	hostility.record_attack(player, first)
	_check(hostility.are_hostile(player, first), "(setup) a new grudge")
	hostility.clear()
	_check(not hostility.are_hostile(player, first), "clearing forgets every grudge (the system changed)")

	# An NPC that attacks another starts a grudge between their sides too.
	hostility.record_attack(first, bystander)
	_check(hostility.are_hostile(first, bystander) and hostility.are_hostile(second, bystander), "when one faction's ship attacks another's, the two factions are hostile")
	_check(not hostility.are_hostile(player, bystander), "...which does not involve the player")
	for ship in [player, first, second, bystander]:
		ship.free()


func _test_sides() -> void:
	var hostility := _hostility()
	var player := _ship(&"", true)
	var friend := _ship(&"x")
	var victim := _ship(&"y")
	var neutral := _ship(&"z")
	_reputation[&"x"] = 40  # a friend of the player
	hostility.record_attack(player, victim)
	_check(hostility.are_hostile(friend, victim), "a friend of the player takes up the player's quarrel")
	_check(not hostility.are_hostile(neutral, victim), "...a faction that is not a friend does not")
	_check(hostility.get_reason(friend, victim) == Hostility.REASON_GRUDGE, "...because of the grudge")
	_reputation[&"x"] = 0
	_check(not hostility.are_hostile(friend, victim), "...and stops being a friend when the reputation falls")
	hostility.clear()

	# A ship that belongs to nobody is a side by itself.
	var loner := _ship(&"")
	var other_loner := _ship(&"")
	hostility.record_attack(victim, loner)
	_check(hostility.are_hostile(victim, loner), "a faction's ship that attacks a lone ship has a grudge with it")
	_check(not hostility.are_hostile(victim, other_loner), "...but not with another lone ship")
	_check(not hostility.are_hostile(loner, other_loner), "lone ships are not hostile to each other")
	_check(hostility.side_of(player) == Hostility.PLAYER_SIDE and hostility.side_of(victim) == &"y" and hostility.side_of(loner) == loner.combat_id, "a side is the player's, a faction, or the lone ship itself")
	for ship in [player, friend, victim, neutral, loner, other_loner]:
		ship.free()


func _test_allies_and_edges() -> void:
	var hostility := _hostility()
	var first := _ship(&"faction_1")
	var second := _ship(&"faction_1")
	hostility.record_attack(first, second)
	_check(not hostility.are_hostile(first, second), "allies never start a grudge against each other")
	var player := _ship(&"", true)
	_reputation[&"faction_1"] = 40
	hostility.record_attack(player, first)
	_check(not hostility.are_hostile(player, first), "...nor does the player against a faction they are friends with")
	_reputation[&"faction_1"] = 0
	_check(not hostility.are_hostile(player, first), "...and that records nothing")
	hostility.record_attack(player, first)
	_reputation[&"faction_1"] = 40
	_check(not hostility.are_hostile(player, first), "a grudge never makes allies hostile")
	_check(not hostility.are_hostile(first, first), "a ship is not hostile to itself")
	_check(not hostility.are_hostile(null, first) and not hostility.are_hostile(first, null), "nothing is hostile to null")
	hostility.record_attack(null, first)
	hostility.record_attack(first, null)
	hostility.record_attack(first, first)
	_check(true, "recording an attack with null or the same ship does nothing")
	var bare := Hostility.new()
	_check(not bare.are_hostile(first, _ship(&"faction_2")), "with nothing set up nobody is hostile")
	for ship in [first, second, player]:
		ship.free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
