class_name ContractSource
extends RefCounted
## Decides which contracts a location offers. The ContractManager asks the
## source once per location (on first use) and keeps the result. The first
## source reads fixed offers from the location's data; a procedural generator
## would be another subclass (using the context's galaxy, discovery state and
## reward rules), with no change to the manager, the interface or the save format.


## Returns new AVAILABLE contracts for the location. Ids are assigned later.
func generate(_location: InhabitedData, _context: ContractContext) -> Array[Contract]:
	return []
