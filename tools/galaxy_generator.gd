class_name GalaxyGenerator
extends RefCounted
## Builds the galaxy's content from the table in data/galaxy/galaxy_map.json:
## the star system scenes, their locations and markets, and resources/universe/
## galaxy.tres. Pure: build() returns {file path: file text} and touches nothing,
## so tools/generate_galaxy.gd writes the files and a test can check that the
## files on disk are exactly what the table produces.
##
## Everything is deterministic (seeded from the system id). Systems flagged
## `hand_built` are only listed in galaxy.tres; their scenes and locations are
## written by hand. Systems flagged `locked` are generated once and then left
## alone, so they can be edited by hand.
##
## Content is deliberately light: 1 to 3 bodies per system (a star system holds at
## most StarSystem.MAX_OBJECTS), each inhabited one built from an archetype.
## Richer systems later means changing the archetypes here and regenerating.

const MAP_PATH := "res://data/galaxy/galaxy_map.json"
const POOLS_PATH := "res://data/galaxy/name_pools.json"
const SCENE_DIR := "res://scenes/systems/"
const GENERATED_SCENE_DIR := "res://scenes/systems/generated/"
const LOCATION_DIR := "res://resources/locations/generated/"
const MARKET_DIR := "res://resources/markets/generated/"
const GALAXY_PATH := "res://resources/universe/galaxy.tres"
const FACTION_DIR := "res://resources/factions/"

## Archetypes of inhabited places: what they export and import, how many people.
const ARCHETYPES := {
	"farming": {"weight": 3, "exports": ["food", "water"], "imports": ["machinery", "electronics", "medical_supplies"],
			"population": [40000, 3000000], "planets": ["terrestrial", "jungle", "ocean"]},
	"mining": {"weight": 3, "exports": ["ore", "rare_isotopes"], "imports": ["food", "machinery", "water", "fuel"],
			"population": [5000, 400000], "planets": ["rocky", "desert", "arctic"]},
	"industrial": {"weight": 3, "exports": ["machinery", "industrial_chemicals", "electronics"], "imports": ["ore", "food", "fuel"],
			"population": [200000, 6000000], "planets": ["terrestrial", "desert", "rocky"]},
	"trade": {"weight": 2, "exports": ["luxury_goods", "medical_supplies", "electronics"], "imports": ["food", "fuel", "ore", "water"],
			"population": [500000, 9000000], "planets": ["resort", "terrestrial", "ocean"]},
	"outpost": {"weight": 3, "exports": ["fuel"], "imports": ["food", "water", "medical_supplies"],
			"population": [1000, 20000], "planets": []},
}
## Bodies nobody lives on (cannot be landed on).
const BARREN_TYPES := ["rocky", "desert", "arctic", "moon", "gas_giant_blue", "gas_giant_green", "gas_giant_red"]
const GAS_GIANTS := ["gas_giant_blue", "gas_giant_green", "gas_giant_red"]
const UNCLAIMED := ""

var _map: Dictionary
var _pools: Dictionary
var _factions: Dictionary = {}  # faction id -> resource path
var _used_names: Dictionary = {}
var _files: Dictionary = {}


func _init() -> void:
	_map = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	_pools = JSON.parse_string(FileAccess.get_file_as_string(POOLS_PATH))
	for file in DirAccess.get_files_at(FACTION_DIR):
		if file.ends_with(".tres"):
			var faction := load(FACTION_DIR + file) as Faction
			if faction != null:
				_factions[str(faction.id)] = FACTION_DIR + file


## Problems with the table itself; empty when it is sound.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var ids := {}
	var names := {}
	for row in _map["systems"]:
		var id: String = row["id"]
		if ids.has(id):
			problems.append("system id '%s' is used twice" % id)
		ids[id] = row
		if names.has(row["name"]):
			problems.append("system name '%s' is used twice" % row["name"])
		names[row["name"]] = true
		if row["faction"] != "" and not _factions.has(row["faction"]):
			problems.append("system '%s' has an unknown faction '%s'" % [id, row["faction"]])
		if row.get("hand_built", false) and not FileAccess.file_exists("%s%s.tscn" % [SCENE_DIR, row["scene"]]):
			problems.append("hand built system '%s' has no scene" % id)
	for row in _map["systems"]:
		for other in row["links"]:
			if not ids.has(other):
				problems.append("'%s' links to unknown system '%s'" % [row["id"], other])
			elif not ids[other]["links"].has(row["id"]):
				problems.append("link %s - %s is not listed on both ends" % [row["id"], other])
	if not ids.has(_map["origin_system"]):
		problems.append("origin_system is not a system")
	# Connected?
	if problems.is_empty():
		var reached := {_map["origin_system"]: true}
		var queue: Array = [_map["origin_system"]]
		while not queue.is_empty():
			var current: String = queue.pop_back()
			for other in ids[current]["links"]:
				if not reached.has(other):
					reached[other] = true
					queue.append(other)
		if reached.size() != ids.size():
			problems.append("%d systems cannot be reached from the origin" % (ids.size() - reached.size()))
	return problems


func get_rows() -> Array:
	return _map["systems"]


## {path: text} for everything the table generates.
func build() -> Dictionary:
	_files = {}
	_used_names = {}
	# Names already taken by hand-made locations and by systems.
	for row in _map["systems"]:
		_used_names[str(row["name"]).to_lower()] = true
	for file in DirAccess.get_files_at("res://resources/locations/"):
		if file.ends_with(".tres"):
			var data = load("res://resources/locations/" + file)
			if data != null and data.get("display_name") != null:
				_used_names[str(data.display_name).to_lower()] = true
	for row in _map["systems"]:
		if row.get("hand_built", false) or row.get("locked", false):
			continue
		_build_system(row)
	_files[GALAXY_PATH] = _galaxy_text()
	return _files


# -------------------------------------------------------------------- systems

func _build_system(row: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = str(row["id"]).hash()
	var inhabited: bool = row["inhabited"]
	var count := 1
	if inhabited:
		var roll := rng.randf()
		count = 1 if roll < 0.3 else (2 if roll < 0.75 else 3)
	else:
		count = 1 if rng.randf() < 0.6 else 2
	var archetype := _pick_archetype(rng)
	var bodies: Array[Dictionary] = []
	for i in count:
		var body := {}
		if inhabited and i == 0:
			body = _inhabited_body(row, archetype, rng)
		elif inhabited and rng.randf() < 0.35:
			body = _inhabited_body(row, _pick_archetype(rng), rng)  # a second settlement
		else:
			body = _barren_body(row, rng)
		bodies.append(body)
	# A system needs at least one planet; if the only body is a station, add a barren planet.
	var has_planet := false
	for body in bodies:
		has_planet = has_planet or body["kind"] == "planet"
	if not has_planet:
		if bodies.size() >= 3:
			bodies[bodies.size() - 1] = _barren_body(row, rng)
		else:
			bodies.append(_barren_body(row, rng))
	var slots := bodies.size()
	var base_angle := rng.randf() * TAU
	for i in slots:
		var angle := base_angle + TAU * i / slots + rng.randf_range(-0.3, 0.3)
		var distance := rng.randf_range(700.0, 1500.0)
		bodies[i]["position"] = Vector2(cos(angle), sin(angle)) * distance
	for body in bodies:
		_files[LOCATION_DIR + "%s.tres" % body["id"]] = _location_text(body, row)
		if body.has("exports"):
			_files[MARKET_DIR + "%s_market.tres" % body["id"]] = _market_text(body)
	_files[GENERATED_SCENE_DIR + "%s_system.tscn" % row["id"]] = _scene_text(row, bodies)


func _pick_archetype(rng: RandomNumberGenerator) -> String:
	var total := 0
	for key in ARCHETYPES:
		total += ARCHETYPES[key]["weight"]
	var roll := rng.randi_range(1, total)
	for key in ARCHETYPES:
		roll -= ARCHETYPES[key]["weight"]
		if roll <= 0:
			return key
	return "farming"


func _inhabited_body(row: Dictionary, archetype: String, rng: RandomNumberGenerator) -> Dictionary:
	var rules: Dictionary = ARCHETYPES[archetype]
	var is_station: bool = rules["planets"].is_empty() or rng.randf() < 0.15
	var name := _next_name(row, rng, is_station)
	var exports := _pick_some(rules["exports"], rng, 1, mini(2, rules["exports"].size()))
	var imports: Array = []
	for good in _pick_some(rules["imports"], rng, 1, mini(3, rules["imports"].size())):
		if not exports.has(good):
			imports.append(good)
	if imports.is_empty():
		imports.append("fuel" if not exports.has("fuel") else "food")
	var population := int(exp(rng.randf_range(log(rules["population"][0]), log(rules["population"][1]))))
	population = int(round(population / 100.0)) * 100
	var body := {
		"id": _slug(name), "name": name, "archetype": archetype, "kind": "station" if is_station else "planet",
		"population": population, "exports": exports, "imports": imports,
		"size": 180.0 if is_station else rng.randf_range(260.0, 560.0),
		"planet_type": "" if is_station else str(rules["planets"][rng.randi_range(0, rules["planets"].size() - 1)]),
		"shipyard": archetype in ["trade", "industrial"] and rng.randf() < 0.18,
		"outfitter": population >= 100000 and rng.randf() < 0.3,
		"stock": rng.randi_range(60, 160),
	}
	return body


func _barren_body(row: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var name := _next_name(row, rng, false)
	var type: String = BARREN_TYPES[rng.randi_range(0, BARREN_TYPES.size() - 1)]
	if type == "moon":
		type = "rocky"  # a moon needs a planet beside it; keep it simple
	return {"id": _slug(name), "name": name, "kind": "planet", "barren": true, "planet_type": type,
			"size": rng.randf_range(650.0, 1000.0) if GAS_GIANTS.has(type) else rng.randf_range(250.0, 480.0)}


func _next_name(row: Dictionary, rng: RandomNumberGenerator, station: bool) -> String:
	var pool: Dictionary = _pools[row["region"]]
	var names: Array = pool["planets"]
	var start := rng.randi_range(0, names.size() - 1)
	for i in names.size():
		var candidate: String = names[(start + i) % names.size()]
		if not _used_names.has(candidate.to_lower()):
			_used_names[candidate.to_lower()] = true
			if station:
				var suffixes: Array = pool["station_suffixes"]
				var named: String = "%s %s" % [candidate, suffixes[rng.randi_range(0, suffixes.size() - 1)]]
				_used_names[named.to_lower()] = true
				return named
			return candidate
	push_error("name pool '%s' ran out" % row["region"])
	return "Body %d" % _used_names.size()


func _pick_some(options: Array, rng: RandomNumberGenerator, low: int, high: int) -> Array:
	var pool := options.duplicate()
	var result: Array = []
	var count := rng.randi_range(low, high)
	while result.size() < count and not pool.is_empty():
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


func _slug(text: String) -> String:
	var result := ""
	var last_underscore := true
	for character in text.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			result += character
			last_underscore = false
		elif not last_underscore:
			result += "_"
			last_underscore = true
	return result.trim_suffix("_")


func _pascal(text: String) -> String:
	var result := ""
	for word in text.split(" ", false):
		var clean := ""
		for character in word:
			if (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9"):
				clean += character
		result += clean.capitalize() if clean.to_lower() == clean else clean
	return result


# ----------------------------------------------------------------- file text

func _scene_text(row: Dictionary, bodies: Array[Dictionary]) -> String:
	var text := "[gd_scene format=3]\n\n"
	text += "[ext_resource type=\"PackedScene\" path=\"res://scenes/systems/star_system.tscn\" id=\"1\"]\n"
	text += "[ext_resource type=\"PackedScene\" path=\"res://scenes/objects/planet.tscn\" id=\"2\"]\n"
	text += "[ext_resource type=\"PackedScene\" path=\"res://scenes/objects/space_station.tscn\" id=\"3\"]\n"
	for i in bodies.size():
		text += "[ext_resource type=\"Resource\" path=\"%s%s.tres\" id=\"loc_%d\"]\n" % [LOCATION_DIR, bodies[i]["id"], i]
	text += "\n[node name=\"%sSystem\" instance=ExtResource(\"1\")]\n" % _pascal(row["name"])
	text += "system_id = &\"%s\"\nsystem_name = \"%s\"\n" % [row["id"], row["name"]]
	for i in bodies.size():
		var body := bodies[i]
		var position: Vector2 = body["position"]
		text += "\n[node name=\"%s\" parent=\"Objects\" index=\"%d\" instance=ExtResource(\"%s\")]\n" % [
				_pascal(body["name"]), i, "3" if body["kind"] == "station" else "2"]
		text += "position = Vector2(%d, %d)\ndata = ExtResource(\"loc_%d\")\n" % [roundi(position.x), roundi(position.y), i]
	return text


func _location_text(body: Dictionary, row: Dictionary) -> String:
	var is_station: bool = body["kind"] == "station"
	var barren: bool = body.get("barren", false)
	var script_path := "res://scripts/resources/inhabited_data.gd" if is_station else "res://scripts/resources/planet_data.gd"
	var script_class := "InhabitedData" if is_station else "PlanetData"
	var text := "[gd_resource type=\"Resource\" script_class=\"%s\" format=3]\n\n" % script_class
	text += "[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]\n" % script_path
	if not is_station:
		text += "[ext_resource type=\"Resource\" path=\"res://resources/planet_types/%s.tres\" id=\"2\"]\n" % body["planet_type"]
	var faction_id: String = row["faction"]
	if not barren and faction_id != UNCLAIMED:
		text += "[ext_resource type=\"Resource\" path=\"%s\" id=\"faction_1\"]\n" % _factions[faction_id]
	if not barren:
		text += "[ext_resource type=\"Script\" path=\"res://scripts/resources/commodity.gd\" id=\"cs\"]\n"
		for good in body["exports"] + body["imports"]:
			text += "[ext_resource type=\"Resource\" path=\"res://resources/commodities/%s.tres\" id=\"c_%s\"]\n" % [good, good]
		text += "[ext_resource type=\"Resource\" path=\"%s%s_market.tres\" id=\"market\"]\n" % [MARKET_DIR, body["id"]]
		if body["shipyard"]:
			text += "[ext_resource type=\"Script\" path=\"res://scripts/resources/ship_stats.gd\" id=\"sss\"]\n"
			text += "[ext_resource type=\"Resource\" path=\"res://resources/ships/shuttle_stats.tres\" id=\"sy_shuttle\"]\n"
			text += "[ext_resource type=\"Resource\" path=\"res://resources/ships/interceptor_stats.tres\" id=\"sy_interceptor\"]\n"
		if body["outfitter"]:
			text += "[ext_resource type=\"Script\" path=\"res://scripts/resources/upgrade_definition.gd\" id=\"uds\"]\n"
			text += "[ext_resource type=\"Resource\" path=\"res://resources/upgrades/cargo_bay.tres\" id=\"up_cargo_bay\"]\n"
			text += "[ext_resource type=\"Resource\" path=\"res://resources/upgrades/engine_1.tres\" id=\"up_engine_1\"]\n"
	text += "\n[resource]\nscript = ExtResource(\"1\")\n"
	text += "id = &\"%s\"\ndisplay_name = \"%s\"\n" % [body["id"], body["name"]]
	if not is_station:
		text += "planet_type = ExtResource(\"2\")\n"
	if barren:
		text += "population = 0\ndockable = false\nsize = %d.0\n" % roundi(body["size"])
		return text
	if faction_id != UNCLAIMED:
		text += "faction = ExtResource(\"faction_1\")\n"
	text += "population = %d\n" % body["population"]
	text += "exported_goods = Array[ExtResource(\"cs\")]([%s])\n" % ", ".join(_ext_list(body["exports"], "c_"))
	text += "imported_goods = Array[ExtResource(\"cs\")]([%s])\n" % ", ".join(_ext_list(body["imports"], "c_"))
	text += "size = %d.0\n" % roundi(body["size"])
	text += "market = ExtResource(\"market\")\n"
	if body["shipyard"]:
		text += "shipyard_ships = Array[ExtResource(\"sss\")]([ExtResource(\"sy_shuttle\"), ExtResource(\"sy_interceptor\")])\n"
	if body["outfitter"]:
		text += "outfitter_upgrades = Array[ExtResource(\"uds\")]([ExtResource(\"up_cargo_bay\"), ExtResource(\"up_engine_1\")])\n"
	return text


func _ext_list(goods: Array, prefix: String) -> Array[String]:
	var result: Array[String] = []
	for good in goods:
		result.append("ExtResource(\"%s%s\")" % [prefix, good])
	return result


func _market_text(body: Dictionary) -> String:
	var goods: Array = body["exports"] + body["imports"]
	var text := "[gd_resource type=\"Resource\" script_class=\"MarketData\" format=3]\n\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/resources/market_data.gd\" id=\"1\"]\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/resources/market_listing.gd\" id=\"2\"]\n"
	for good in goods:
		text += "[ext_resource type=\"Resource\" path=\"res://resources/commodities/%s.tres\" id=\"c_%s\"]\n" % [good, good]
	for i in goods.size():
		text += "\n[sub_resource type=\"Resource\" id=\"listing_%d\"]\nscript = ExtResource(\"2\")\ncommodity = ExtResource(\"c_%s\")\nbase_stock = %d\n" % [
				i, goods[i], body["stock"] if body["exports"].has(goods[i]) else maxi(20, body["stock"] / 2)]
	var subs: Array[String] = []
	for i in goods.size():
		subs.append("SubResource(\"listing_%d\")" % i)
	text += "\n[resource]\nscript = ExtResource(\"1\")\nlistings = Array[ExtResource(\"2\")]([%s])\n" % ", ".join(subs)
	return text


func _galaxy_text() -> String:
	var rows: Array = _map["systems"]
	var origin: Dictionary
	for row in rows:
		if row["id"] == _map["origin_system"]:
			origin = row
	var scale: float = _map["scale"]
	var text := "[gd_resource type=\"Resource\" script_class=\"Galaxy\" format=3]\n\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/galaxy/galaxy.gd\" id=\"g\"]\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/galaxy/galaxy_system.gd\" id=\"gs\"]\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/galaxy/system_link.gd\" id=\"sl\"]\n"
	for faction_id in _factions:
		text += "[ext_resource type=\"Resource\" path=\"%s\" id=\"f_%s\"]\n" % [_factions[faction_id], faction_id]
	for row in rows:
		var path := "%s%s.tscn" % [SCENE_DIR, row["scene"]] if row.get("hand_built", false) else "%s%s_system.tscn" % [GENERATED_SCENE_DIR, row["id"]]
		text += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"sc_%s\"]\n" % [path, row["id"]]
	var subs: Array[String] = []
	for row in rows:
		var position := Vector2(row["x"] - origin["x"], row["y"] - origin["y"]) * scale
		text += "\n[sub_resource type=\"Resource\" id=\"sys_%s\"]\nscript = ExtResource(\"gs\")\nscene = ExtResource(\"sc_%s\")\n" % [row["id"], row["id"]]
		text += "map_position = Vector2(%d, %d)\n" % [roundi(position.x), roundi(position.y)]
		text += "start_discovered = %s\n" % ("true" if _map["start_discovered"].has(row["id"]) else "false")
		if row["faction"] != UNCLAIMED:
			text += "claim = ExtResource(\"f_%s\")\n" % row["faction"]
		subs.append("SubResource(\"sys_%s\")" % row["id"])
	var link_subs: Array[String] = []
	for row in rows:
		for other in row["links"]:
			if str(row["id"]) < str(other):
				var name := "link_%s_%s" % [row["id"], other]
				text += "\n[sub_resource type=\"Resource\" id=\"%s\"]\nscript = ExtResource(\"sl\")\na = &\"%s\"\nb = &\"%s\"\n" % [name, row["id"], other]
				link_subs.append("SubResource(\"%s\")" % name)
	text += "\n[resource]\nscript = ExtResource(\"g\")\n"
	text += "systems = Array[ExtResource(\"gs\")]([%s])\n" % ", ".join(subs)
	text += "links = Array[ExtResource(\"sl\")]([%s])\n" % ", ".join(link_subs)
	text += "fuel_per_unit = 0.1\n"
	return text
