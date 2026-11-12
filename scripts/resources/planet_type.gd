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
## Settlement-screen background for inhabited planets of this type. Used when a
## planet's own data has no `picture` set.
@export var settlement_picture: Texture2D

## The economy of an inhabited planet of this type, unless the planet names its
## own profile. Null for types nobody lives on (gas giants).
@export var economy_profile: EconomyProfile

## True for moons. A system may only contain a moon if it also has a planet.
@export var is_moon: bool = false
