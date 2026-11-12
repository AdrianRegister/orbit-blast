class_name DestructionReport
extends RefCounted
## Everything other systems need to know about a ship that was destroyed. Built
## by the CombatManager and passed with its signals. Plain data on purpose: the
## war system will read reports like this to turn fights into strategic losses.

var victim_id: StringName = &""
var victim_model: StringName = &""
var victim_faction: StringName = &""
var victim_is_player: bool = false

var attacker_id: StringName = &""
var attacker_faction: StringName = &""
var attacker_is_player: bool = false

var system_id: StringName = &""
var position: Vector2 = Vector2.ZERO
## Game-clock day it happened on.
var day: int = 0
