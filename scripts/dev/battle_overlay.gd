class_name BattleOverlay
extends Node2D
## DEVELOPMENT ONLY. A debug overlay for the combat sandbox, drawn over the star system: a line
## from every ship to the ship it is targeting, coloured by side (A blue, B red, anyone else grey),
## and a label over every unit's leader (and every fleet's flagship) with what its commander is
## doing: the formation state (FOLLOWING, ATTACKING ...) and, for a squadron inside a battle group,
## its role (SCREEN, STRIKE). Switched on and off from the sandbox toolbar (F4).

const COLOURS := [Color(0.35, 0.65, 1.0), Color(1.0, 0.4, 0.35)]
const OTHER := Color(0.7, 0.7, 0.75)
const FONT_SIZE := 15

var _sandbox: CombatSandbox
var _system: StarSystem
var _tracker: BattleTracker


func setup(sandbox: CombatSandbox, system: StarSystem) -> void:
	_sandbox = sandbox
	_system = system
	_tracker = sandbox.get_tracker()
	z_index = 200
	visible = false
	_system.add_child(self)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if _system == null or not is_instance_valid(_system):
		return
	var zoom := 1.0
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		zoom = camera.zoom.x
	var width := maxf(2.0 / zoom, 1.5)
	for ship in _system.get_ships_root().get_children():
		var npc := ship as NpcShip
		if npc == null or npc.is_queued_for_deletion() or not npc.visible:
			continue
		var target: Combatant = npc.get_combatant().get_target()
		if target == null or not is_instance_valid(target) or not target.is_alive():
			continue
		var colour := _colour_of(npc)
		colour.a = 0.7
		draw_line(to_local(npc.global_position), to_local(target.global_position), colour, width)
		draw_circle(to_local(target.global_position), 5.0 / zoom, colour)
	var size := int(FONT_SIZE / zoom)
	for unit in _system.get_formations_root().get_children():
		var label := ""
		var anchor: NpcShip
		var colour := OTHER
		if unit is Formation and is_instance_valid(unit) and unit.has_valid_lead():
			anchor = unit.lead
			label = "%s %s" % [Formation.kind_name(unit.kind).to_upper(), str(Formation.State.keys()[unit.state])]
			if unit.commander != null and unit.commander.role != UnitCommander.Role.NONE:
				label += " (%s)" % str(UnitCommander.Role.keys()[unit.commander.role])
			if unit.commander != null and unit.commander.directive != UnitCommander.Directive.FREE:
				label += " [%s]" % str(UnitCommander.Directive.keys()[unit.commander.directive])
		elif unit is WarFleet and is_instance_valid(unit) and unit.has_flagship() and unit.commander != null:
			anchor = unit.flagship
			label = "FLEET %s (%s)" % [str(FleetCommander.State.keys()[unit.commander.state]), str(FleetCommander.Objective.keys()[unit.commander.objective])]
		if anchor == null:
			continue
		colour = _colour_of(anchor)
		draw_string(ThemeDB.fallback_font, to_local(anchor.global_position) + Vector2(14.0, -14.0) / zoom, label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


func _colour_of(ship: NpcShip) -> Color:
	var side := _tracker.side_of(ship) if _tracker != null else -1
	return COLOURS[side] if side >= 0 else OTHER
