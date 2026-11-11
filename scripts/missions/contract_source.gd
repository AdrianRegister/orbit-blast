class_name ContractSource
extends RefCounted
## Decides which contracts a location offers. The ContractManager asks the
## source for new contracts when a location is first used and again each time
## the player docks there, and keeps the result. The game uses the
## ProceduralContractSource; tests may use their own. Whatever the source, the
## manager, interface and save format are the same.


## Returns up to `wanted` new AVAILABLE contracts for the location. `existing`
## are the contracts it already has on offer or active, which new ones should not
## duplicate. Ids are assigned later by the manager.
func generate(_location: InhabitedData, _context: ContractContext, _wanted: int, _existing: Array[Contract]) -> Array[Contract]:
	return []


## How many offers a location should have on its mission computer.
func get_target_offers() -> int:
	return 1
