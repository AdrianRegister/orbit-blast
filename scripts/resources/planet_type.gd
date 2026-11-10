class_name PlanetType
extends Resource
## A kind of planet (Terrestrial, Rocky, ...). One .tres per kind in
## resources/planet_types/. It links the kind to its sprite, so choosing a
## planet's type also chooses how it looks. Later, the trading system can add
## fields here (typical goods, price modifiers) so every planet of a type
## shares them.

@export var display_name: String = ""
## The sprite used for planets of this type.
@export var texture: Texture2D
