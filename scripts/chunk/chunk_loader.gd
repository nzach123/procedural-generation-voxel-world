## ChunkLoader
## Static utility class for chunk I/O operations.
## All functions are thread-safe for use in WorkerThreadPool tasks.
## 
## IMPORTANT (Elena Vasquez review): This class contains ONLY static helpers.
## The actual task wrappers (_load_chunk_task, _spawn_chunk_threaded_or_load)
## MUST remain in ChunkManager for call_deferred callback ownership.
class_name ChunkLoader
extends RefCounted

# Explicit preload for static method access
const VoxelDataGeneratorClass := preload("res://scripts/chunk/voxel_data_generator.gd")


# -------------------------------------------------------------------
# Static API
# -------------------------------------------------------------------

## Loads voxel data from disk (thread-safe).
## @param key: Chunk coordinate to load.
## @return PackedByteArray: Voxel data, or empty if not found.
static func load_voxels_from_disk(key: Vector2i) -> PackedByteArray:
	return ChunkSerializer.load_chunk(key)


## Saves voxel data to disk (thread-safe).
## @param key: Chunk coordinate to save.
## @param voxels: Raw voxel data to persist.
static func save_voxels_to_disk(key: Vector2i, voxels: PackedByteArray) -> void:
	ChunkSerializer.save_voxels(key, voxels)


## Checks if a saved chunk exists for the given key.
## @param key: Chunk coordinate to check.
## @return bool: True if saved data exists on disk.
static func has_saved_chunk(key: Vector2i) -> bool:
	return ChunkSerializer.chunk_exists(key)


## Generates fallback voxel data when no save exists (thread-safe).
## Uses the provided noise generator for terrain generation.
## @param noise: FastNoiseLite generator (should be thread-local).
## @param offset: World position offset for the chunk origin.
## @param max_height: Maximum terrain height for generation.
## @return PackedByteArray: Generated voxel data.
static func generate_fallback_voxels(
	noise: FastNoiseLite,
	offset: Vector3,
	max_height: int
) -> PackedByteArray:
	return VoxelDataGeneratorClass.generate_voxel_data(noise, offset, max_height)


## Generates mesh arrays from voxel data (thread-safe).
## Wrapper for ChunkManager's static mesh generation.
## @param voxels: Raw voxel data.
## @param offset: World position offset for the chunk.
## @param color: Chunk tint color for debugging.
## @return Dictionary: Mesh data with vertices, uvs, normals, indices, triangle_count.
static func generate_mesh_from_voxels(
	voxels: PackedByteArray,
	offset: Vector3,
	color: Color
) -> Dictionary:
	return VoxelDataGeneratorClass.generate_mesh_arrays(voxels, offset, color)


## Creates a complete chunk loading result for the main thread apply queue.
## Consolidates voxel loading, fallback generation, and mesh building.
## @param key: Chunk coordinate.
## @param offset: World position offset.
## @param color: Chunk tint color.
## @param noise: Thread-local noise generator (for fallback).
## @param max_height: Maximum terrain height.
## @return Dictionary: Complete result ready for _queue_chunk_apply.
static func load_or_generate_chunk_data(
	key: Vector2i,
	offset: Vector3,
	color: Color,
	noise: FastNoiseLite,
	max_height: int
) -> Dictionary:
	var voxels: PackedByteArray
	var mesh_data: Dictionary
	
	# Try loading from disk first
	if has_saved_chunk(key):
		voxels = load_voxels_from_disk(key)
	
	# Validate loaded data, fallback to generation if invalid
	const CHUNK_VOLUME: int = 32 * 32 * 32  # 32768
	if voxels.size() != CHUNK_VOLUME:
		voxels = generate_fallback_voxels(noise, offset, max_height)
	
	# Generate mesh from voxels
	mesh_data = generate_mesh_from_voxels(voxels, offset, color)
	
	return {
		"key": key,
		"voxels": voxels,
		"mesh_data": mesh_data
	}
