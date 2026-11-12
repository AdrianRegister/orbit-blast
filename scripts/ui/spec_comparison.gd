class_name SpecComparison
extends GridContainer
## A small table comparing two sets of ship specs: STAT, CURRENT, NEW, CHANGE.
## Used by the shipyard (your ship against a model) and the outfitters (your
## ship against itself with an upgrade). It only displays what it is given.

const BETTER_COLOR := Color(0.45, 0.9, 0.5)
const WORSE_COLOR := Color(1.0, 0.45, 0.4)
const CAPTION_COLOR := Color(0.6, 0.66, 0.75)


func _init() -> void:
	columns = 4
	add_theme_constant_override("h_separation", 18)
	add_theme_constant_override("v_separation", 4)


## `current` and `after` are ShipSpecs. With after = null only the current
## column is filled in.
func show_specs(current: ShipSpecs, after: ShipSpecs) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for title in ["", "CURRENT", "NEW", "CHANGE"]:
		_add_label(title, CAPTION_COLOR, HORIZONTAL_ALIGNMENT_RIGHT if title != "" else HORIZONTAL_ALIGNMENT_LEFT)
	_add_row("TOP SPEED", current.max_speed, after.max_speed if after != null else NAN, "%d")
	_add_row("ACCELERATION", current.thrust, after.thrust if after != null else NAN, "%d")
	_add_row("TURN RATE", current.turn_rate, after.turn_rate if after != null else NAN, "%.1f")
	_add_row("CARGO", float(current.cargo_capacity), float(after.cargo_capacity) if after != null else NAN, "%d")
	_add_row("SHIELDS", current.shield_capacity, after.shield_capacity if after != null else NAN, "%d")
	_add_row("ARMOUR", current.armour, after.armour if after != null else NAN, "%d")
	_add_row("HULL", current.hull, after.hull if after != null else NAN, "%d")
	_add_row("ENERGY", current.energy_capacity, after.energy_capacity if after != null else NAN, "%d")
	_add_row("WEAPON MOUNTS", float(current.weapon_mounts), float(after.weapon_mounts) if after != null else NAN, "%d")


func _add_row(title: String, current: float, after: float, format: String) -> void:
	_add_label(title, CAPTION_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	_add_label(format % current, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	if is_nan(after):
		_add_label("", Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		_add_label("", Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		return
	_add_label(format % after, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	var difference := after - current
	var shown := format % absf(difference)
	if shown == format % 0.0:
		_add_label("-", CAPTION_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	elif difference > 0.0:
		_add_label("+" + shown, BETTER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_add_label("-" + shown, WORSE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)


func _add_label(text: String, color: Color, alignment: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
