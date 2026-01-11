## VisibilityManager
## Manages chunk visibility and collision state based on player proximity.
## IMPORTANT: Methods affecting PhysicsServer must be called from main thread only.
class_name VisibilityManager
extends RefCounted


# -------------------------------------------------------------------
# Dependencies
# -------------------------------------------------------------------

var _chunk_manager: Node  # Reference to ChunkManager


# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _init(manager: Node) -> void:
	_chunk_manager = manager


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Updates which chunks have collision enabled based on proximity to position.
## MUST be called from main thread (PhysicsServer is not thread-safe).
## @param center_pos: World position of the player/center point.
## @param chunks: Dictionary of Vector2i -> ChunkServer.
## @param collision_radius: Maximum chunk distance for collision.
## @param space_rid: Physics space RID for collision operations.
func update_collision_radius(
	center_pos: Vector3,
	chunks: Dictionary,
	collision_radius: int,
	space_rid: RID
) -> void:
	# REVIEWER REQUIREMENT (Marcus Chen): Thread safety assertion
	assert(
		OS.get_thread_caller_id() == OS.get_main_thread_id(),
		"update_collision_radius must be called from main thread (PhysicsServer is not thread-safe)"
	)
	
	# Inline coordinate conversion (avoids class_name resolution issues)
	const CHUNK_WIDTH: int = 32
	const CHUNK_DEPTH: int = 32
	var center_chunk := Vector2i(
		int(floor(center_pos.x / CHUNK_WIDTH)),
		int(floor(center_pos.z / CHUNK_DEPTH))
	)
	
	for key in chunks:  # Direct iteration (no .keys() allocation)
		var chunk: RefCounted = chunks[key]
		var dist: int = maxi(absi(key.x - center_chunk.x), absi(key.y - center_chunk.y))
		var should_have_collision: bool = dist <= collision_radius
		
		if chunk.is_collision_enabled() != should_have_collision:
			chunk.set_collision_enabled(should_have_collision, space_rid)


## Pre-computes spiral offsets sorted by distance (closest first).
## Used for prioritized chunk loading.
## @param view_distance: Maximum chunk distance to include.
## @return Array[Vector2i]: Offsets sorted by distance from center.
static func compute_spiral_offsets(view_distance: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var vd_sq: int = view_distance * view_distance
	
	for x in range(-view_distance, view_distance + 1):
		for z in range(-view_distance, view_distance + 1):
			var offset := Vector2i(x, z)
			if offset.length_squared() <= vd_sq:
				offsets.append(offset)
	
	# Sort by distance (closest first = highest priority)
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared()
	)
	
	return offsets


## Determines which chunks should be unloaded based on distance.
## @param center: Current center chunk coordinate.
## @param chunks: Dictionary of loaded chunks.
## @param unload_distance_sq: Squared distance threshold for unloading.
## @return Array[Vector2i]: Chunk coordinates that should be unloaded.
static func get_chunks_to_unload(
	center: Vector2i,
	chunks: Dictionary,
	unload_distance_sq: int
) -> Array[Vector2i]:
	var to_unload: Array[Vector2i] = []
	
	for coord in chunks:
		var dist: float = Vector2(coord.x - center.x, coord.y - center.y).length_squared()
		if dist > unload_distance_sq:
			to_unload.append(coord)
	
	return to_unload


## Finds the farthest chunk from center (for memory cap enforcement).
## @param center: Current center chunk coordinate.
## @param chunks: Dictionary of loaded chunks.
## @return Vector2i: Coordinate of farthest chunk, or Vector2i.ZERO if empty.
static func find_farthest_chunk(center: Vector2i, chunks: Dictionary) -> Vector2i:
	if chunks.is_empty():
		return Vector2i.ZERO
	
	var farthest_key: Vector2i = Vector2i.ZERO
	var farthest_dist: float = -1.0
	
	for coord in chunks:
		var dist: float = Vector2(coord.x - center.x, coord.y - center.y).length_squared()
		if dist > farthest_dist:
			farthest_dist = dist
			farthest_key = coord
	
	return farthest_key
