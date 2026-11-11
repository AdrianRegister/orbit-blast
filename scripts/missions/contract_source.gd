class_name ContractSource
extends RefCounted
## Decides which contracts a location offers. The ContractManager asks the
## source once per location (on first use) and keeps the result. The first
## source reads fixed offers from the location's data; a procedural generator
## would be another subclass, with no change to the manager or the interface.


## Returns new AVAILABLE contracts for the location. Ids are assigned later.
func generate(_location: InhabitedData) -> Array[Contract]:
	return []
