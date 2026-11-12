class_name TopBar
extends CanvasLayer
## A slim bar of buttons across the top of the space view (the part of the screen
## not taken by the HUD panel). Each button opens an information screen; another
## is a new child of the Buttons node plus a signal. It decides nothing: Main
## opens the screens.

signal factions_requested

@onready var _factions_button: Button = %FactionsButton
@onready var _day_label: Label = %DayLabel


func _ready() -> void:
	_factions_button.pressed.connect(factions_requested.emit)


## Hides the Factions button (the combat sandbox has no factions screen).
func hide_factions_button() -> void:
	_factions_button.visible = false


## Shows the current calendar day at the far right of the bar.
func set_day(day: int) -> void:
	_day_label.text = "DAY %d" % day
