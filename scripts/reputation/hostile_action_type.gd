class_name HostileActionType
extends Resource
## A kind of hostile act against a faction's assets and what it costs the
## player in reputation (resources/reputation/hostile_actions/*.tres). Combat will
## report these through ReputationManager.report_hostile_action(); the penalty is
## configured here, per kind of act.

@export var id: StringName = &""
@export var display_name: String = ""
## Reputation lost with the faction that was hurt (a positive number).
@export var penalty: int = 5
