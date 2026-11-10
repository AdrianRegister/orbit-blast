class_name GameStateManager
extends Node
## Tracks which high-level state the game is in. It only stores the state and
## announces changes; other systems listen and decide what that means for them
## (Main wires the listeners up). Add new states to the enum as needed.

enum State { FLYING, DOCKED }

## Emitted after every change.
signal state_changed(new_state: State, previous_state: State)

var state: State = State.FLYING


func change_state(new_state: State) -> void:
	if new_state == state:
		return
	var previous: State = state
	state = new_state
	state_changed.emit(new_state, previous)
