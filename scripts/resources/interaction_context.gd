## InteractionContext
## Resource containing player interaction state for voxel manipulation.
## Used to decouple player input from voxel modification logic.
## Implements object pooling via static rent()/release() to reduce GC pressure.
class_name InteractionContext
extends Resource


# -------------------------------------------------------------------
# Pool Management (Static)
# -------------------------------------------------------------------

## Object pool for recycling InteractionContext instances.
static var _pool: Array[InteractionContext] = []

## Maximum pool size to prevent unbounded growth.
const MAX_POOL_SIZE: int = 32


## Rent an InteractionContext from the pool (or create new if empty).
## @return InteractionContext: A reset instance ready for use.
static func rent() -> InteractionContext:
	var ctx: InteractionContext
	if _pool.size() > 0:
		ctx = _pool.pop_back()
	else:
		ctx = InteractionContext.new()
	ctx._reset()
	return ctx


## Release an InteractionContext back to the pool for reuse.
## @param ctx: The context to return to the pool.
static func release(ctx: InteractionContext) -> void:
	if ctx == null:
		return
	ctx._reset()
	if _pool.size() < MAX_POOL_SIZE:
		_pool.push_back(ctx)
	# If pool is full, let GC handle it


## Returns current pool size (for debugging/testing).
static func get_pool_size() -> int:
	return _pool.size()


## Clears the pool (useful for testing or scene transitions).
static func clear_pool() -> void:
	_pool.clear()


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


# -------------------------------------------------------------------
# Internal
# -------------------------------------------------------------------

## Resets all state to defaults (called by rent/release).
func _reset() -> void:
	selected_block_id = 2  # DIRT
	brush_radius = 1
	reach_distance = 5.0
	can_modify = true
