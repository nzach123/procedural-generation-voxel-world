## BlockData
## Resource defining static properties of a single block type.
class_name BlockData
extends Resource

## Human-readable name (e.g., "Dirt").
@export var block_name: String = ""

## Coordinates on the main texture atlas (x, y tile indices).
@export var texture_atlas_coords: Vector2i = Vector2i.ZERO

## Determines if the block generates collision/mesh faces.
@export var is_solid: bool = true

## If true, this block does not occlude neighbors (for glass, water, etc).
@export var is_transparent: bool = false
