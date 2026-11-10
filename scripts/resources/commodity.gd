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
## Optional icon. Not required by any current system.
@export var icon: Texture2D
