## InteractionContext
## Resource containing player interaction state for voxel manipulation.
## Used to decouple player input from voxel modification logic.
class_name InteractionContext
extends Resource


# -------------------------------------------------------------------
# Exports
# -------------------------------------------------------------------

## ID of the block to place when interacting.
@export var selected_block_id: int = 2  # Default: DIRT

## Radius of the modification brush (1 = single block).
@export_range(1, 5) var brush_radius: int = 1

## Maximum reach distance for block interaction.
@export var reach_distance: float = 5.0

## Whether the player can modify blocks.
@export var can_modify: bool = true


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Returns the block ID to use for placing.
func get_place_block() -> int:
	return selected_block_id


## Sets the selected block ID.
func set_selected_block(block_id: int) -> void:
	selected_block_id = block_id


## Cycles to the next block type.
func cycle_block() -> void:
	selected_block_id = (selected_block_id % 3) + 1  # Cycles 1 -> 2 -> 3 -> 1
