class_name InfoRow
extends HBoxContainer
## One "CAPTION  value" line. The value wraps onto several lines if it is long.

@export var caption: String = ""

@onready var _caption_label: Label = %Caption
@onready var _value_label: Label = %Value


func _ready() -> void:
	_caption_label.text = caption


func set_value(text: String) -> void:
	_value_label.text = text
