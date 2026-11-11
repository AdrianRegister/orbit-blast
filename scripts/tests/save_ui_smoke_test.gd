extends SceneTree
## Headless smoke test of the menus through the real buttons: main menu (New
## Game, Continue), autosave, pause menu (Save, Load, Resume, Quit to menu),
## and damaged saves. Uses a throwaway file in user://. Run with:
##   Godot --headless --path . --script res://scripts/tests/save_ui_smoke_test.gd

const PATH := "user://save_ui_test.json"

var _failures: int = 0


func _init() -> void:
	_clean()
	var menu := await _open_menu()
	var new_button: Button = menu.get_node("%NewButton")
	var continue_button: Button = menu.get_node("%ContinueButton")
	_check(not new_button.disabled, "New Game is available")
	_check(continue_button.disabled, "Continue is disabled with no save")

	# --- New game.
	var confirm: Control = menu.get_node("%ConfirmNew")
	new_button.pressed.emit()
	var warned := confirm.visible
	await process_frame
	var main := _find_main()
	_check(main != null and not warned, "New Game with no save starts at once, without a warning")
	_check(not is_instance_valid(menu) or menu.is_queued_for_deletion(), "the menu goes away")
	var prompt: NamePrompt = main.get_node("NamePrompt")
	_check(prompt.visible and paused, "a new game asks for the ship's name and waits")
	_check(not main.get_save_manager().autosave_enabled, "nothing is autosaved before the ship is named")
	prompt.get_node("%NameInput").text = "Test Pilot's Pride"
	prompt.get_node("%OkButton").pressed.emit()
	await process_frame
	_check(main.get_player_data().fleet.get_active().ship_name == "Test Pilot's Pride", "the ship has the chosen name")
	_check(main.get_save_manager().autosave_enabled, "autosave is on during a game")
	_check(main.get_player_data().credits == 500000, "a new game starts with the starting credits")
	_check(not paused, "the game is not paused")

	# --- Autosave after an action.
	var earth: InhabitedData = load("res://resources/locations/earth.tres")
	var economy: EconomyManager = main.get_node("Economy")
	var contracts: ContractManager = main.get_node("Contracts")
	economy.set_cargo_capacity(500)  # the starting shuttle is too small for the test contract
	contracts.accept(contracts.get_available(earth)[0], earth)
	await process_frame
	await process_frame
	_check(FileAccess.file_exists(PATH), "accepting a contract autosaves")

	# --- Esc opens the pause menu; its Save button saves.
	var pause: PauseMenu = main.get_node("PauseMenu")
	await _press_escape()
	_check(pause.visible and paused, "Esc opens the pause menu and pauses the game")
	var status: Label = pause.get_node("%StatusLabel")
	pause.get_node("%SaveButton").pressed.emit()
	_check(status.text == "GAME SAVED", "Save Game reports success: '%s'" % status.text)
	_check(not pause.get_node("%LoadButton").disabled, "Load Game is available once there is a save")

	# --- Load restores an earlier state.
	var saved_credits := main.get_player_data().credits
	main.get_player_data().credits = 12
	pause.get_node("%LoadButton").pressed.emit()
	await process_frame
	_check(main.get_player_data().credits == saved_credits, "Load Game restores the saved credits")
	_check(not pause.visible and not paused, "...and closes the menu and resumes")

	# --- Esc again, then Esc / Resume close it.
	await _press_escape()
	_check(pause.visible, "Esc opens the pause menu again")
	await _press_escape()
	_check(not pause.visible and not paused, "Esc closes it")
	await _press_escape()
	pause.get_node("%ResumeButton").pressed.emit()
	_check(not pause.visible and not paused, "Resume closes it")

	# --- Esc closes the trading screen first, without opening the pause menu.
	var ship := main.get_player_ship()
	var earth_node: Targetable
	for node in get_nodes_in_group(Targetable.GROUP):
		if node.target_name == "Earth":
			earth_node = node
	ship.global_position = earth_node.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	main.get_node("Targeting").select(earth_node)
	main.get_node("Docking").try_dock()
	await process_frame
	main.get_node("SettlementScreen").get_node("%TradingButton").pressed.emit()
	await process_frame
	var trading: TradingScreen = main.get_node("TradingScreen")
	_check(trading.visible, "trading screen open")
	await _press_escape()
	_check(not trading.visible and not pause.visible, "Esc closes the trading screen, not the pause menu")
	await _press_escape()
	_check(pause.visible, "a second Esc (while docked) opens the pause menu")
	pause.get_node("%SaveButton").pressed.emit()
	await _press_escape()  # close

	# --- Quit to menu, then Continue returns to the docked game.
	await _press_escape()
	pause.get_node("%QuitButton").pressed.emit()
	await process_frame
	await process_frame
	_check(_find_main() == null, "Quit to Menu removes the game")
	_check(not paused, "...and does not leave the tree paused")
	menu = _find_menu()
	_check(menu != null, "the main menu is back")
	menu.save_path = PATH
	menu._refresh_continue()
	continue_button = menu.get_node("%ContinueButton")
	_check(not continue_button.disabled, "Continue is enabled with a save")
	_check("Last saved" in menu.get_node("%MessageLabel").text, "Continue says when the save was made: '%s'" % menu.get_node("%MessageLabel").text)
	continue_button.pressed.emit()
	await process_frame
	main = _find_main()
	_check(main != null and main.get_docked_target() != null, "Continue resumes docked, as saved (%s)" % menu.get_node("%MessageLabel").text if is_instance_valid(menu) else "gone")
	_check(main.get_node("SettlementScreen").visible, "the settlement screen is shown")
	_check(main.get_node("Contracts").get_active().size() == 1, "the accepted contract is still active")
	_check(main.get_player_data().cargo.get_used() == 40, "its cargo is still in the hold")
	main.free()

	# --- Damaged saves.
	var good_text := FileAccess.get_file_as_string(PATH)
	for case in [
		["unreadable file", '{"version": 1, "econ'],
		["invalid contents", null],
	]:
		if case[1] == null:
			var good: Dictionary = JSON.parse_string(good_text)
			good["economy"]["credits"] = -1
			_write(PATH, JSON.stringify(good))
			_write(PATH + ".bak", "junk")
		else:
			_write(PATH, case[1])
			_write(PATH + ".bak", "junk")
		menu = await _open_menu()
		continue_button = menu.get_node("%ContinueButton")
		if case[1] != null:
			_check(continue_button.disabled and not menu.get_node("%MessageLabel").text.is_empty(),
					"%s: Continue disabled with a message ('%s')" % [case[0], menu.get_node("%MessageLabel").text])
		else:
			_check(not continue_button.disabled, "%s: looks fine until it is loaded" % case[0])
			continue_button.pressed.emit()
			await process_frame
			_check(_find_main() == null, "%s: no game is started" % case[0])
			_check(continue_button.disabled and not menu.get_node("%MessageLabel").text.is_empty(),
					"%s: Continue disabled with a message ('%s')" % [case[0], menu.get_node("%MessageLabel").text])
		confirm = menu.get_node("%ConfirmNew")
		menu.get_node("%NewButton").pressed.emit()
		await process_frame
		_check(confirm.visible and _find_main() == null, "%s: New Game asks before replacing the file" % case[0])
		menu.get_node("%CancelButton").pressed.emit()
		await process_frame
		_check(not confirm.visible and _find_main() == null and FileAccess.file_exists(PATH),
				"%s: Cancel keeps the menu and the file" % case[0])
		menu.get_node("%NewButton").pressed.emit()
		menu.get_node("%ConfirmButton").pressed.emit()
		await process_frame
		_check(_find_main() != null, "%s: confirming starts a new game" % case[0])
		_find_main().free()
		paused = false
		_clean_menus()

	_clean()
	print("")
	if _failures == 0:
		print("SAVE UI SMOKE TEST: all passed")
	else:
		print("SAVE UI SMOKE TEST: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _open_menu() -> MainMenu:
	var menu: MainMenu = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.save_path = PATH
	root.add_child(menu)
	await process_frame
	return menu


func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _find_main() -> Main:
	for child in root.get_children():
		if child is Main and not child.is_queued_for_deletion():
			return child
	return null


func _find_menu() -> MainMenu:
	for child in root.get_children():
		if child is MainMenu and not child.is_queued_for_deletion():
			return child
	return null


func _clean_menus() -> void:
	for child in root.get_children():
		if child is MainMenu:
			child.free()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		print("FAIL  ", description)
		_failures += 1
