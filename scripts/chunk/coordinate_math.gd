## CoordinateMath
## Static utility class for coordinate conversions in the voxel engine.
## All functions are pure and thread-safe.
class_name CoordinateMath
extends RefCounted


# -------------------------------------------------------------------
# Constants (mirror ChunkManager for static access)
# -------------------------------------------------------------------

const CHUNK_WIDTH: int = 32
const CHUNK_HEIGHT: int = 32
const CHUNK_DEPTH: int = 32
const CHUNK_VOLUME: int = CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_DEPTH


# -------------------------------------------------------------------
# Static API
# -------------------------------------------------------------------

## Converts world position to chunk coordinate (2D grid key).
## @param global_pos: World position to convert.
## @return Vector2i: Chunk coordinate for chunk dictionary lookup.
static func world_to_chunk_coord(global_pos: Vector3) -> Vector2i:
	var cx: int = int(floor(global_pos.x / CHUNK_WIDTH))
	var cz: int = int(floor(global_pos.z / CHUNK_DEPTH))
	return Vector2i(cx, cz)


## Converts world position to local voxel coordinate within a chunk.
## @param global_pos: World position to convert.
## @return Vector3i: Local voxel coordinate (0 to CHUNK_SIZE-1 per axis).
static func world_to_local_voxel(global_pos: Vector3) -> Vector3i:
	var local_x: int = posmod(int(floor(global_pos.x)), CHUNK_WIDTH)
	var local_y: int = clampi(int(floor(global_pos.y)), 0, CHUNK_HEIGHT - 1)
	var local_z: int = posmod(int(floor(global_pos.z)), CHUNK_DEPTH)
	return Vector3i(local_x, local_y, local_z)


## Converts local voxel coordinate to flat array index.
## Uses x + z*WIDTH + y*WIDTH*DEPTH indexing (same as ChunkManager).
## @param local: Local voxel coordinate within chunk.
## @return int: Flat index for PackedByteArray access.
static func local_to_flat_index(local: Vector3i) -> int:
	return local.x + local.z * CHUNK_WIDTH + local.y * CHUNK_WIDTH * CHUNK_DEPTH


## Converts flat array index to local voxel coordinate.
## Inverse of local_to_flat_index.
## @param idx: Flat index from PackedByteArray.
## @return Vector3i: Local voxel coordinate.
static func flat_index_to_local(idx: int) -> Vector3i:
	var y: int = idx / (CHUNK_WIDTH * CHUNK_DEPTH)
	var remainder: int = idx % (CHUNK_WIDTH * CHUNK_DEPTH)
	var z: int = remainder / CHUNK_WIDTH
	var x: int = remainder % CHUNK_WIDTH
	return Vector3i(x, y, z)


## Checks if local position is air (thread-safe, no cross-chunk lookups).
## Treats out-of-bounds coordinates as air (for mesh generation).
## @param voxels: Packed voxel data for the chunk.
## @param x: Local X coordinate.
## @param y: Local Y coordinate.
## @param z: Local Z coordinate.
## @return bool: True if position is air or out of bounds.
static func is_air_local(voxels: PackedByteArray, x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_WIDTH or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_DEPTH:
		return true  # Treat boundary as air for initial mesh
	var idx: int = x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_DEPTH
	return voxels[idx] == 0


## Checks if a local coordinate is on a chunk boundary.
## Used for determining if block modifications affect neighbor chunks.
## @param local: Local voxel coordinate.
## @return bool: True if on any X or Z boundary.
static func is_on_chunk_boundary(local: Vector3i) -> bool:
	return local.x == 0 or local.x == CHUNK_WIDTH - 1 \
		or local.z == 0 or local.z == CHUNK_DEPTH - 1


## Gets the chunk coordinate offset for a boundary face.
## @param local: Local voxel coordinate.
## @return Array[Vector2i]: Neighbor offsets that need updating.
static func get_affected_neighbor_offsets(local: Vector3i) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	
	if local.x == 0:
		offsets.append(Vector2i(-1, 0))
	elif local.x == CHUNK_WIDTH - 1:
		offsets.append(Vector2i(1, 0))
	
	if local.z == 0:
		offsets.append(Vector2i(0, -1))
	elif local.z == CHUNK_DEPTH - 1:
		offsets.append(Vector2i(0, 1))
	
	return offsets
