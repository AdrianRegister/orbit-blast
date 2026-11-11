class_name PlayerSection
extends RefCounted
## The "player" section of the save: where the player is (system, position,
## heading, speed), whether they are flying or docked and where. Credits and cargo belong to the economy section, ships to the
## fleet section, contracts to theirs. It reads and restores through Main's small public interface rather
## than touching the scene tree itself.

var _main: Main


func _init(main: Main) -> void:
	_main = main


func save_state() -> Dictionary:
	var ship := _main.get_player_ship()
	var data := {
		"system": str(_main.get_system().system_id),
		"position": SaveData.from_vector(ship.global_position),
		"rotation": ship.rotation,
		"velocity": SaveData.from_vector(ship.velocity),
		"mode": "space",
	}
	var docked_at := _main.get_docked_target()
	if docked_at != null and docked_at.details is InhabitedData:
		data["mode"] = "docked"
		data["docked_at"] = str((docked_at.details as InhabitedData).id)
	return data


func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary:
		return ["player is not an object"]
	if not SaveData.is_id(data.get("system")) or not registry.has_system(StringName(data["system"])):
		problems.append("player is in an unknown star system")
	if not SaveData.is_vector(data.get("position")):
		problems.append("player position is not a pair of numbers")
	if not SaveData.is_number(data.get("rotation")):
		problems.append("player rotation is not a number")
	if not SaveData.is_vector(data.get("velocity")):
		problems.append("player velocity is not a pair of numbers")
	match data.get("mode"):
		"space":
			pass
		"docked":
			if not SaveData.is_id(data.get("docked_at")) or registry.location(StringName(data["docked_at"])) == null:
				problems.append("player is docked at an unknown location")
		_:
			problems.append("player mode must be 'space' or 'docked'")
	return problems


func load_state(data: Dictionary, registry: ContentRegistry) -> void:
	var docked_at: StringName = StringName(data["docked_at"]) if data["mode"] == "docked" else &""
	_main.restore_player(StringName(data["system"]),
			SaveData.to_vector(data["position"]), float(data["rotation"]),
			SaveData.to_vector(data["velocity"]), docked_at, registry)
