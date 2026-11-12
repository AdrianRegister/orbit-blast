class_name Commodity
extends Resource
## A tradeable good (Food, Ore, ...). One .tres per commodity in
## resources/commodities/. Definitions are shared by every market, cargo hold
## and location; nothing about a specific market belongs here.

## Unique identifier, e.g. &"food". Used as the key in cargo manifests and
## market stock, so it must never change once saved data exists.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Price in credits before any market adjustment.
@export var base_price: int = 100
## What the people of any settlement use of this good, in units per day for each
## million inhabitants (food, water, fuel, ...). 0 = people do not need it; only
## industry does. See EconomyModel.
@export var civilian_demand: float = 0.0
## True for goods of war (munitions, armour, ...). They are traded like any other
## good, and the market simulation treats them like any other, but civilian
## contracts never carry them, and a future smuggling or blockade system can key
## on this.
@export var military: bool = false
## Optional icon. Not required by any current system.
@export var icon: Texture2D
