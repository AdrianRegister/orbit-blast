class_name FlavourPool
extends Resource
## A set of interchangeable pieces of flavour text for one kind of event
## (a delivery completed, arriving at a settlement, a spaceport bar visit, ...).
## One .tres per kind of event in resources/flavour/. Whatever handles the
## event holds a reference to its pool and calls pick(); adding a line of
## flavour is editing the .tres, adding a new kind of event is a new .tres.
##
## An entry may contain {placeholders} such as {destination}; pick() fills in
## the ones it is given and leaves unknown ones as they are.

@export_multiline var entries: Array[String] = []


## A random entry with placeholders replaced from `values`
## (for example {"destination": "Mars"}). Empty string if the pool is empty.
func pick(values: Dictionary = {}) -> String:
	if entries.is_empty():
		return ""
	var text: String = entries.pick_random()
	for key in values:
		text = text.replace("{%s}" % key, str(values[key]))
	return text


func validate() -> Array[String]:
	var problems: Array[String] = []
	if entries.is_empty():
		problems.append("flavour pool has no entries")
	for entry in entries:
		if entry.strip_edges().is_empty():
			problems.append("flavour pool has an empty entry")
	return problems
