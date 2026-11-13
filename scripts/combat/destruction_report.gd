class_name DestructionReport
extends RefCounted
## Everything other systems need to know about a ship that was destroyed. Built
## by the CombatManager and passed with its signals. Plain data on purpose: the
## war system will read reports like this to turn fights into strategic losses.

var victim_id: StringName = &""
var victim_model: StringName = &""
var victim_faction: StringName = &""
var victim_is_player: bool = false
## The formation the victim belonged to when it was destroyed (a squadron, battle
## group or convoy): its kind (&"squadron", &"battle_group", &"convoy"), its id, and
## the id of the fleet it was part of. All empty for a ship in no formation, so wars
## can count a unit's losses.
var victim_formation_kind: StringName = &""
var victim_formation_id: StringName = &""
var victim_fleet_id: StringName = &""

var attacker_id: StringName = &""
var attacker_faction: StringName = &""
var attacker_is_player: bool = false

var system_id: StringName = &""
var position: Vector2 = Vector2.ZERO
## Game-clock day it happened on.
var day: int = 0
