extends SceneTree
## Headless smoke test of the real game scene: dock at Earth through the
## DockingManager, open the trading floor, buy and sell through the UI buttons
## and check the HUD. Run with:
##   Godot --headless --path . --script res://scripts/tests/trading_ui_smoke_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var hud: Hud = main.get_node("Hud")
	var credits_label: Label = hud.get_node("%CreditsValue")
	_check(credits_label.text == "500,000", "HUD starts at 500,000 credits (was '%s')" % credits_label.text)

	var ship: PlayerShip = main.get_node("PlayerShip")
	var targeting: TargetingManager = main.get_node("Targeting")
	var docking: DockingManager = main.get_node("Docking")
	var settlement: SettlementScreen = main.get_node("SettlementScreen")
	var trading: TradingScreen = main.get_node("TradingScreen")
	var economy: EconomyManager = main.get_node("Economy")

	var earth: Targetable
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == "Earth":
			earth = t
	_check(earth != null, "found Earth's Targetable")

	ship.global_position = earth.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	targeting.select(earth)
	docking.try_dock()
	await process_frame
	_check(settlement.visible, "docking opens the settlement screen")
	_check(not trading.visible, "trading screen starts closed")

	var trading_button: Button = settlement.get_node("%TradingButton")
	_check(not trading_button.disabled, "Trading Floor enabled at Earth")
	trading_button.pressed.emit()
	await process_frame
	_check(trading.visible, "Trading Floor button opens the trading screen")

	# A headless window has an arbitrary size, so lay the screen out at the
	# game's design resolution (1920x1080) before measuring it.
	var panel: Control = trading.get_node("Panel")
	panel.size = Vector2(1920, 1080)
	await process_frame
	var table: Tree = trading.get_node("%Table")
	var cargo_panel: Control = trading.get_node("%CargoPanel")
	var total_width: float = table.size.x + cargo_panel.size.x
	_check(table.size.x > 0.0 and cargo_panel.size.x > 0.0, "table (%d px) and cargo panel (%d px) both visible" % [table.size.x, cargo_panel.size.x])
	_check(absf(table.size.x / total_width - 0.75) < 0.01, "commodity table is 75%% of the row (%.1f%%)" % [100.0 * table.size.x / total_width])
	_check(absf(cargo_panel.size.x / total_width - 0.25) < 0.01, "cargo hold is 25%% of the row (%.1f%%)" % [100.0 * cargo_panel.size.x / total_width])
	var screen: Vector2 = trading.get_node("Panel").size
	var trade_panel: Control = trading.get_node("%SelectedLabel").get_parent().get_parent().get_parent()
	_check(trade_panel.global_position.y + trade_panel.size.y <= screen.y - 90.0,
			"trade panel ends 90+ px above the screen bottom (%d of %d)" % [trade_panel.global_position.y + trade_panel.size.y, screen.y])
	_check(table.size.y > 150.0, "table has usable height (%d px)" % table.size.y)
	_check(table.get_root().get_child_count() == 4, "Earth lists 4 commodities")

	# Select Food (first row), buy 10 through the button.
	var quantity: SpinBox = trading.get_node("%QuantityBox")
	quantity.value = 10
	var buy_button: Button = trading.get_node("%BuyButton")
	var sell_button: Button = trading.get_node("%SellButton")
	_check(not buy_button.disabled, "Buy enabled for a valid purchase")
	_check(sell_button.disabled, "Sell disabled where the market rejects Food")
	buy_button.pressed.emit()
	await process_frame
	var expected: int = 500000 - 10 * 38  # Food 50 * 0.75 = 37.5 -> 38
	_check(economy.get_credits() == expected, "credits after buying: %d" % economy.get_credits())
	_check(credits_label.text == NumberFormat.with_commas(expected), "HUD credits updated to '%s'" % credits_label.text)
	_check(economy.get_cargo().get_used() == 10, "cargo holds 10")
	var hud_cargo: CargoList = hud.get_node("%CargoList")
	var hud_lines: VBoxContainer = hud_cargo.get_node("%Lines")
	_check(hud_lines.get_child_count() == 1 and hud_lines.get_child(0).get_child(0).text == "Food"
			and hud_lines.get_child(0).get_child(1).text == "10", "HUD cargo list shows Food 10")
	var trading_cargo: CargoList = trading.get_node("%CargoList")
	var trading_lines: VBoxContainer = trading_cargo.get_node("%Lines")
	_check(trading_lines.get_child_count() == 1 and trading_lines.get_child(0).get_child(1).text == "10",
			"trading screen cargo breakdown shows Food 10")

	# Too many: asks for far more than the stock.
	quantity.value = 99999
	_check(buy_button.disabled, "oversized purchase disabled")
	var buy_label: Label = trading.get_node("%BuyLabel")
	_check(buy_label.text == "INSUFFICIENT MARKET STOCK", "feedback text: '%s'" % buy_label.text)

	# Back, then depart.
	trading.get_node("%BackButton").pressed.emit()
	_check(not trading.visible and settlement.visible, "Back returns to the settlement screen")
	settlement.depart_requested.emit()
	await process_frame
	_check(not settlement.visible and not trading.visible, "departing closes both screens")
	_check(economy.get_cargo().get_used() == 10, "cargo persisted after departing")
	_check(hud.visible, "HUD visible again after departing")

	print("")
	print("UI SMOKE TEST: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	main.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	print("PASS  " if condition else "FAIL  ", description)
	if not condition:
		_failures += 1
