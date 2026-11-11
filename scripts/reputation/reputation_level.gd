class_name ReputationLevel
extends Resource
## One standing on the reputation scale ("Wary", "Honoured", ...). A level covers
## every reputation from its lower bound up to the next level's lower bound.

@export var lower_bound: int = 0
@export var display_name: String = ""
