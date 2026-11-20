class_name BattleReadout
extends CanvasLayer
## DEVELOPMENT ONLY. A small box at the top of the combat sandbox's screen that keeps the score of
## the battle that is running (BattleTracker): ships and strength left, losses, ships that got
## away, kills, the time, and the winner, with buttons to start or hold the battle and to clear it.
## It is separate from the battle panel (F3), so it stays on screen when that panel is replaced by the
## formations panel (F2). It shows only while there is a battle, the player is flying and the game
## is not paused.

const REFRESH_SECONDS := 0.2

var _sandbox: CombatSandbox
var _tracker: BattleTracker
var _factions: Array[StringName] = [&"", &""]
var _box: PanelContainer
var _text: Label
var _start_button: Button
var _clear_button: Button
var _since_refresh: float = 0.0
var _names := {}


func _init() -> void:
	# Keeps running while the game is paused, so it can hide itself behind menus.
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(sandbox: CombatSandbox, registry: ContentRegistry) -> void:
	_sandbox = sandbox
	_tracker = sandbox.get_tracker()
	for faction in registry.factions():
		_names[faction.id] = faction.display_name
	layer = 5
	_box = PanelContainer.new()
	_box.theme = load("res://resources/ui/hud_theme.tres")
	add_child(_box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_box.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	_text = Label.new()
	_text.custom_minimum_size = Vector2(560, 0)
	row.add_child(_text)
	var buttons := VBoxContainer.new()
	row.add_child(buttons)
	_start_button = Button.new()
	_start_button.custom_minimum_size = Vector2(110, 28)
	_start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_button)
	_clear_button = Button.new()
	_clear_button.text = "CLEAR"
	_clear_button.custom_minimum_size = Vector2(110, 28)
	_clear_button.pressed.connect(func() -> void: _sandbox.clear_battle())
	buttons.add_child(_clear_button)
	DevPanel.disable_focus(self)
	visible = false


func _process(delta: float) -> void:
	var show_it := _sandbox != null and _tracker != null and _tracker.has_battle() and _sandbox.is_flying() and not get_tree().paused
	visible = show_it
	if not show_it:
		return
	# Centred at the top of the play area (left of the HUD panel).
	var width := get_viewport().get_visible_rect().size.x
	_box.position = Vector2(maxf((width * 0.8 - _box.size.x) * 0.5, 12.0), 12.0)
	_since_refresh += delta
	if _since_refresh >= REFRESH_SECONDS:
		_since_refresh = 0.0
		refresh()


## Redraws the text and the start button from the tracker.
func refresh() -> void:
	_factions = _sandbox.get_battle_factions()
	var lines: Array[String] = []
	for side in 2:
		var name: String = _names.get(_factions[side], "no faction")
		lines.append("%s (%s)" % [_tracker.describe_side(side), name])
	var winner := _tracker.winner()
	var status := "HELD" if _sandbox.is_battle_held() else "FIGHTING"
	if winner == &"draw":
		status = "DRAW"
	elif winner != &"":
		status = "WINNER: %s (%s)" % [str(winner).to_upper(), _names.get(_factions[0 if winner == &"a" else 1], "no faction")]
	lines.append("%s   time %s" % [status, _format_time(_tracker.elapsed)])
	_text.text = "\n".join(lines)
	_start_button.text = "START" if _sandbox.is_battle_held() else "HOLD"
	_start_button.disabled = winner != &""


func _on_start_pressed() -> void:
	if _sandbox.is_battle_held():
		_sandbox.start_battle()
	else:
		_sandbox.hold_battle(true)
	refresh()


static func _format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
