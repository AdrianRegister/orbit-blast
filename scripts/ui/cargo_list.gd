class_name CargoList
extends VBoxContainer
## Shows how full the cargo hold is and what is in it: "CARGO  used / capacity"
## followed by one "Name ... quantity" line per commodity carried. Purely
## presentational; it is told what to show, so the flight HUD and the trading
## screen can both use it.

@onready var _usage_row: InfoRow = %UsageRow
@onready var _lines: VBoxContainer = %Lines


## `lines` is an Array of [display_name: String, quantity: int] pairs.
func set_cargo(used: int, capacity: int, lines: Array) -> void:
	_usage_row.set_value("%d / %d" % [used, capacity])
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	if lines.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"CaptionLabel"
		empty.text = "EMPTY"
		_lines.add_child(empty)
		return
	for line in lines:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = str(line[0])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var quantity_label := Label.new()
		quantity_label.text = NumberFormat.with_commas(line[1])
		quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_label)
		row.add_child(quantity_label)
		_lines.add_child(row)
