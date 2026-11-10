class_name StatBar
extends HBoxContainer
## One labelled status bar row: "CAPTION [=====----] value/max".
## Purely presentational; the HUD tells it what to show.

@export var caption: String = ""
@export var fill_color: Color = Color(0.6, 0.65, 0.71)

@onready var _caption_label: Label = %Caption
@onready var _bar: ProgressBar = %Bar
@onready var _value_label: Label = %Value


func _ready() -> void:
	_caption_label.text = caption
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	_bar.add_theme_stylebox_override("fill", fill)


func set_values(value: float, max_value: float) -> void:
	_bar.max_value = max_value
	_bar.value = value
	_value_label.text = "%d/%d" % [roundi(value), roundi(max_value)]
