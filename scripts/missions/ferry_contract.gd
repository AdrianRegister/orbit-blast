class_name FerryContract
extends CargoDeliveryContract
## Take a few passengers from the issuer to a destination. Passengers are carried
## as a small contract lot of the non-market "Passengers" commodity, so they take
## up cargo space (never more than MAX_PASSENGERS), appear in the cargo list and
## are loaded, delivered and saved exactly like other contract cargo. Quick, early
## game work for small ships.

const MAX_PASSENGERS := 3


func get_type_label() -> String:
	return "FERRY"


func get_requirement_text() -> String:
	return "%d %s" % [quantity, "passenger" if quantity == 1 else "passengers"]


func get_progress_text() -> String:
	match status:
		Status.AVAILABLE:
			return "Board at %s" % origin.display_name
		Status.ACCEPTED:
			return "Aboard: %d / %d. Take them to %s" % [quantity_in_hold, quantity, destination.display_name]
		Status.COMPLETED:
			return "Passengers delivered to %s" % destination.display_name
	return ""


func get_type_id() -> StringName:
	return &"ferry"


func validate_dict(data: Dictionary, registry: ContentRegistry) -> Array[String]:
	var problems := super(data, registry)
	if SaveData.is_int(data.get("quantity")) and data["quantity"] > MAX_PASSENGERS:
		problems.append("ferry contract carries more than %d passengers" % MAX_PASSENGERS)
	return problems
