extends SceneTree
## The Factions screen through the real game scene: the top bar button and the F
## key open it, it shows the Federation's identity, colours, the player's
## reputation and standing, and its territory, it lists further factions, and
## Esc or F closes it. Run with:
##   Godot --headless --path . --script res://scripts/tests/faction_screen_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var registry := ContentRegistry.new()
	var federation := registry.faction(&"faction_1")
	var top_bar: TopBar = main.get_node("TopBar")
	var screen: FactionScreen = main.get_node("FactionScreen")
	var reputation: ReputationManager = main.get_node("Reputation")
	var territory: TerritoryManager = main.get_node("Territory")
	var travel: TravelManager = main.get_node("Travel")
	var button: Button = top_bar.get_node("%FactionsButton")

	_check(top_bar.visible and button.visible and not screen.visible, "the top bar shows a Factions button in flight, and the screen starts closed")
	var bar_rect: Rect2 = top_bar.get_node("Buttons").get_global_rect()
	var view_width := float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	_check(bar_rect.position.y < 60.0 and bar_rect.end.x <= view_width * 0.8 + 1.0, "the bar sits across the top of the space view, clear of the HUD panel")
	_check(top_bar.get_node("Buttons").mouse_filter == Control.MOUSE_FILTER_IGNORE, "...and only its buttons take clicks")

	# --- The button opens it.
	button.pressed.emit()
	await process_frame
	_check(screen.visible and paused, "the button opens the Factions screen and pauses the game")
	_check(screen.get_selected() == federation, "the Federation is selected")
	var list: ItemList = screen.get_node("%FactionList")
	_check(list.item_count == 1 and list.get_item_text(0) == "Federation", "it is the one faction listed")
	_check(screen.get_node("%NameLabel").text == "FEDERATION", "its name is shown")
	var text := _text(screen)
	_check(federation.description in text, "its description is shown")
	_check(federation.political_identity in text and federation.background in text, "...with its political identity and background")
	_check("STRENGTH" in text and "1,000" in text, "...and its military strength")
	var swatches := _swatches(screen)
	_check(swatches.size() == 2 and swatches[0] == federation.primary_colour and swatches[1] == federation.secondary_colour, "its primary and secondary colours are shown")
	_check("STANDING" in text and "NEUTRAL" in text and "(+0)" in text, "a new player is shown as Neutral at +0: %s" % text.substr(text.find("STANDING"), 30).replace("\n", " "))
	var bar := _bar(screen)
	_check(bar != null and bar.value == 0 and bar.fill_colour == federation.primary_colour, "the reputation bar is centred, in the faction colour")
	_check("92 controlled" in text and "1 known to you" in text and "Sol" in text, "its territory is summarised: %s" % text.substr(text.find("SYSTEMS"), 40).replace("\n", " "))
	_check("SETTLEMENTS" in text and "None known" in text, "...with its settlements, and no relations")

	# --- It follows changes while open.
	reputation.change(federation, 45)
	await process_frame
	text = _text(screen)
	_check("FRIENDLY" in text and "(+45)" in text and _bar(screen).value == 45, "reputation changes show at once: Friendly, +45")
	travel.discover(&"kerella")
	await process_frame
	_check("2 known to you" in _text(screen) and "Kerella" in _text(screen), "discovering a system adds it to the known territory")
	var rival := Faction.new()
	rival.id = &"faction_2"
	rival.display_name = "Rival"
	rival.primary_colour = Color(0.8, 0.2, 0.2)
	territory.transfer_settlement(registry.location(&"mars"), rival)
	await process_frame
	_check("CONTESTED" in _text(screen) and "Sol" in _text(screen), "a system with settlements of two factions is shown as contested")
	territory.reset_state()

	# --- Esc and F close it.
	_press("ui_cancel")
	await process_frame
	_check(not screen.visible and not paused, "Esc closes it and the game resumes")
	_press("factions")
	await process_frame
	_check(screen.visible and paused, "F opens it")
	_press("factions")
	await process_frame
	_check(not screen.visible and not paused, "F closes it")
	button.pressed.emit()
	await process_frame
	screen.get_node("%BackButton").pressed.emit()
	await process_frame
	_check(not screen.visible and not paused, "BACK closes it")

	# --- It does not open over another screen, or while warping.
	var map: GalaxyMapScreen = main.get_node("GalaxyMapScreen")
	map.open()
	main.get_tree().paused = true
	_press("factions")
	await process_frame
	_check(not screen.visible, "F does nothing while the galaxy map is open")
	map.close()
	main.get_tree().paused = false

	# --- Further factions appear in the list.
	var extra: FactionScreen = load("res://scenes/ui/faction_screen.tscn").instantiate()
	root.add_child(extra)
	var factions: Array[Faction] = [federation, rival]
	extra.setup(factions, main.galaxy, travel, territory, reputation, registry)
	extra.open()
	await process_frame
	var extra_list: ItemList = extra.get_node("%FactionList")
	_check(extra_list.item_count == 2 and extra_list.get_item_text(1) == "Rival", "a second faction is listed")
	extra_list.select(1)
	extra_list.item_selected.emit(1)
	await process_frame
	var rival_text := _text(extra)
	_check(extra.get_selected() == rival and extra.get_node("%NameLabel").text == "RIVAL" and "NEUTRAL" in rival_text and "0 controlled" in rival_text, "selecting it shows its own details: neutral reputation, no territory")
	reputation.change(rival, -65)
	await process_frame
	_check("HOSTILE" in _text(extra) and "(-65)" in _text(extra) and _bar(extra).value == -65, "its reputation is tracked separately: Hostile, -65")
	_check(reputation.get_reputation(federation) == 45, "...and the Federation's is unchanged")
	extra.close()

	# --- The bar is hidden while docked (the HUD is too).
	var ship := main.get_player_ship()
	var earth: Targetable = null
	for node in get_nodes_in_group(Targetable.GROUP):
		if node.target_name == "Earth":
			earth = node
	ship.global_position = earth.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	main.get_node("Targeting").select(earth)
	main.get_node("Docking").try_dock()
	await process_frame
	_check(not top_bar.visible, "the top bar is hidden while docked, like the HUD")

	print("")
	print("FACTION SCREEN TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## All the text the screen shows for the selected faction.
func _text(screen: FactionScreen) -> String:
	var text := ""
	var rows: VBoxContainer = screen.get_node("%DetailRows")
	for row in rows.get_children():
		text += _label_text(row) + "\n"
	return text


func _label_text(node: Node) -> String:
	if node is Label:
		return (node as Label).text + " "
	var text := ""
	for child in node.get_children():
		text += _label_text(child)
	return text


func _swatches(screen: FactionScreen) -> Array[Color]:
	var colours: Array[Color] = []
	var row := screen.get_node("%DetailRows").get_node_or_null("Colours")
	if row != null:
		for child in row.get_children():
			if child is ColorRect:
				colours.append((child as ColorRect).color)
	return colours


func _bar(screen: FactionScreen) -> ReputationBar:
	return screen.get_node("%DetailRows").get_node_or_null("ReputationBar") as ReputationBar


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	print("PASS  " if condition else "FAIL  ", label)
	if not condition:
		_failures += 1
