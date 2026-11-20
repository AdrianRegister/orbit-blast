class_name BattlePresets
extends RefCounted
## DEVELOPMENT ONLY. The battles the combat sandbox's battle panel can spawn in one go. Each is a
## name and two sides ("a" and "b"). A side is one of:
##   {"faction", "model", "count"}                      one kind of ship
##   {"faction", "ships": [{"model", "count"}, ...]}    a mixed force, front rank first
##   {"faction", "units": [...]}                        a list of units, front first: each
##       {"model", "count"} (ships in a rank) or {"recipe": id, "shape": id (optional)} (a unit
##       composed from a formation recipe, with its commander)
##   {"faction", "formation": {"shape", "ships", "kind"}}   one hand-picked unit
##   {"faction", "plan": {"recipe", "ships", "shape", "children": [plan, ...]}}   a whole
##       battle group or fleet, written out
## Any side may add "profile" (a tactical profile id, overriding the one its recipe or the default
## gives) and "separation" (pixels; keeps big sides apart). To add a battle, add an entry here.

const PRESETS := [
	{"name": "1v1: fighters", "a": {"faction": &"faction_1", "model": &"federation_fighter", "count": 1},
			"b": {"faction": &"faction_2", "model": &"hegemony_fighter", "count": 1}},
	{"name": "2v1: 2 Federation fighters, 1 Hegemony fighter", "a": {"faction": &"faction_1", "model": &"federation_fighter", "count": 2},
			"b": {"faction": &"faction_2", "model": &"hegemony_fighter", "count": 1}},
	{"name": "1v1: frigates", "a": {"faction": &"faction_1", "model": &"federation_frigate", "count": 1},
			"b": {"faction": &"faction_2", "model": &"hegemony_frigate", "count": 1}},
	{"name": "1v1: cruisers", "a": {"faction": &"faction_1", "model": &"federation_cruiser", "count": 1},
			"b": {"faction": &"faction_2", "model": &"hegemony_cruiser", "count": 1}},
	{"name": "3 fighters v cruiser", "a": {"faction": &"faction_1", "model": &"federation_fighter", "count": 3},
			"b": {"faction": &"faction_2", "model": &"hegemony_cruiser", "count": 1}},
	{"name": "1v1: capital ships", "a": {"faction": &"faction_1", "model": &"federation_capital_ship", "count": 1},
			"b": {"faction": &"faction_2", "model": &"hegemony_capital_ship", "count": 1}},
	{"name": "Fleets: cruiser, 2 frigates, 5 fighters v cruiser, 2 frigates, heavy fighter, 3 fighters",
			"a": {"faction": &"faction_1", "ships": [
					{"model": &"federation_fighter", "count": 5}, {"model": &"federation_frigate", "count": 2},
					{"model": &"federation_cruiser", "count": 1}]},
			"b": {"faction": &"faction_2", "ships": [
					{"model": &"hegemony_fighter", "count": 3}, {"model": &"hegemony_heavy_fighter", "count": 1},
					{"model": &"hegemony_frigate", "count": 2}, {"model": &"hegemony_cruiser", "count": 1}]}},
	{"name": "Pirate v freighter", "a": {"faction": &"faction_3", "model": &"interceptor", "count": 1},
			"b": {"faction": &"", "model": &"freighter", "count": 1}},
	{"name": "Squadrons: heavy fighter + 3 fighters each",
			"a": {"faction": &"faction_1", "formation": {"shape": &"wedge", "ships": [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"]}},
			"b": {"faction": &"faction_2", "formation": {"shape": &"wedge", "ships": [&"hegemony_heavy_fighter", &"hegemony_fighter", &"hegemony_fighter", &"hegemony_fighter"]}}},
	{"name": "Squadron of 4 fighters v a Hegemony cruiser",
			"a": {"faction": &"faction_1", "formation": {"shape": &"screen", "ships": [&"federation_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"]}},
			"b": {"faction": &"faction_2", "model": &"hegemony_cruiser", "count": 1}},
	{"name": "Battle groups: cruiser, frigate, 2 squadrons each",
			"a": {"faction": &"faction_1", "separation": 3500.0, "plan": {"recipe": &"battle_group", "shape": &"screen", "ships": [&"federation_cruiser", &"federation_frigate"], "children": [
					{"recipe": &"squadron", "shape": &"wedge", "ships": [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"]},
					{"recipe": &"squadron", "shape": &"wedge", "ships": [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"]}]}},
			"b": {"faction": &"faction_2", "separation": 3500.0, "plan": {"recipe": &"battle_group", "shape": &"screen", "ships": [&"hegemony_cruiser", &"hegemony_frigate"], "children": [
					{"recipe": &"squadron", "shape": &"wedge", "ships": [&"hegemony_heavy_fighter", &"hegemony_fighter", &"hegemony_fighter"]},
					{"recipe": &"squadron", "shape": &"wedge", "ships": [&"hegemony_heavy_fighter", &"hegemony_fighter", &"hegemony_fighter"]}]}}},
	{"name": "Capital fleets: 2 capital ships and 2 battle groups each",
			"a": {"faction": &"faction_1", "separation": 9000.0, "plan": {"recipe": &"fleet", "ships": [&"federation_capital_ship", &"federation_capital_ship"], "children": [
					{"recipe": &"battle_group", "shape": &"screen", "ships": [&"federation_cruiser", &"federation_frigate"], "children": [
							{"recipe": &"squadron", "shape": &"wedge", "ships": [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"]}]},
					{"recipe": &"battle_group", "shape": &"screen", "ships": [&"federation_cruiser", &"federation_frigate"], "children": [
							{"recipe": &"squadron", "shape": &"wedge", "ships": [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"]}]}]}},
			"b": {"faction": &"faction_2", "separation": 9000.0, "plan": {"recipe": &"fleet", "ships": [&"hegemony_capital_ship", &"hegemony_capital_ship"], "children": [
					{"recipe": &"battle_group", "shape": &"screen", "ships": [&"hegemony_cruiser", &"hegemony_frigate"], "children": [
							{"recipe": &"squadron", "shape": &"wedge", "ships": [&"hegemony_heavy_fighter", &"hegemony_fighter", &"hegemony_fighter"]}]},
					{"recipe": &"battle_group", "shape": &"screen", "ships": [&"hegemony_cruiser", &"hegemony_frigate"], "children": [
							{"recipe": &"squadron", "shape": &"wedge", "ships": [&"hegemony_heavy_fighter", &"hegemony_fighter", &"hegemony_fighter"]}]}]}}},
	{"name": "Convoy (2 freighters, 2 fighters) v 3 pirate fighters",
			"a": {"faction": &"faction_1", "formation": {"shape": &"convoy_diamond", "kind": Formation.Kind.CONVOY, "ships": [&"freighter", &"freighter", &"federation_fighter", &"federation_fighter"]}},
			"b": {"faction": &"faction_3", "model": &"federation_fighter", "count": 3}},
	{"name": "Every ship: one of each model, Federation v Hegemony",
			"a": {"faction": &"faction_1", "units": [
					{"model": &"federation_fighter", "count": 1}, {"model": &"federation_heavy_fighter", "count": 1},
					{"model": &"federation_frigate", "count": 1}, {"model": &"federation_cruiser", "count": 1},
					{"model": &"federation_capital_ship", "count": 1}]},
			"b": {"faction": &"faction_2", "units": [
					{"model": &"hegemony_fighter", "count": 1}, {"model": &"hegemony_heavy_fighter", "count": 1},
					{"model": &"hegemony_gunboat", "count": 1}, {"model": &"hegemony_frigate", "count": 1},
					{"model": &"hegemony_cruiser", "count": 1}, {"model": &"hegemony_capital_ship", "count": 1}]}},
	{"name": "Composed squadrons: a patrol each, Federation v Hegemony",
			"a": {"faction": &"faction_1", "units": [{"recipe": &"patrol"}]},
			"b": {"faction": &"faction_2", "units": [{"recipe": &"patrol"}]}},
	{"name": "Composed battle groups, Federation v Hegemony",
			"a": {"faction": &"faction_1", "units": [{"recipe": &"battle_group"}]},
			"b": {"faction": &"faction_2", "units": [{"recipe": &"battle_group"}]}},
	{"name": "Composed fleets, Federation v Hegemony",
			"a": {"faction": &"faction_1", "units": [{"recipe": &"fleet"}]},
			"b": {"faction": &"faction_2", "units": [{"recipe": &"fleet"}]}},
	{"name": "Pirate raid on a composed convoy",
			"a": {"faction": &"faction_1", "units": [{"recipe": &"convoy"}]},
			"b": {"faction": &"faction_3", "profile": &"pirate", "units": [{"recipe": &"squadron"}]}},
]
