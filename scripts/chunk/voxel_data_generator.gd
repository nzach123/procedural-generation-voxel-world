## VoxelDataGenerator
## Static utility class for threaded voxel and mesh generation.
## All functions are THREAD-SAFE for use in WorkerThreadPool tasks.
class_name VoxelDataGenerator
extends RefCounted


# -------------------------------------------------------------------
# Constants (mirrored from ChunkManager for static access)
# -------------------------------------------------------------------

const CHUNK_WIDTH: int = 32
const CHUNK_HEIGHT: int = 32
const CHUNK_DEPTH: int = 32
const CHUNK_VOLUME: int = CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_DEPTH


# -------------------------------------------------------------------
# Preloads
# -------------------------------------------------------------------

const MeshBuilderClass := preload("res://scripts/chunk/mesh_builder.gd")


# -------------------------------------------------------------------
# Static API
# -------------------------------------------------------------------

## Generates voxel data on a worker thread (THREAD-SAFE).
## Returns a PackedByteArray with voxel IDs.
## @param noise: Thread-local FastNoiseLite generator.
## @param chunk_offset: World position offset for the chunk origin.
## @param max_h: Maximum terrain height for generation.
## @return PackedByteArray: Generated voxel data (32768 bytes).
static func generate_voxel_data(
	noise: FastNoiseLite,
	chunk_offset: Vector3,
	max_h: int
) -> PackedByteArray:
	var voxels := PackedByteArray()
	voxels.resize(CHUNK_VOLUME)
	voxels.fill(0)  # AIR
	
	for x in range(CHUNK_WIDTH):
		for z in range(CHUNK_DEPTH):
			var world_x: float = x + chunk_offset.x
			var world_z: float = z + chunk_offset.z
			
			var height: int = int((noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5 * max_h)
			height = clampi(height, 0, CHUNK_HEIGHT - 1)
			
			for y in range(CHUNK_HEIGHT):
				var block_id: int = 0  # AIR
				if y < height:
					block_id = BlockDefinitions.BlockType.DIRT
				elif y == height:
					if y > 15:
						block_id = BlockDefinitions.BlockType.STONE
					else:
						block_id = BlockDefinitions.BlockType.GRASS
				
				# Flat index: x + z*WIDTH + y*WIDTH*DEPTH
				var idx: int = x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_DEPTH
				voxels[idx] = block_id
	
	return voxels


## Generates mesh arrays on a worker thread (THREAD-SAFE).
## Returns a Dictionary with keys: vertices, uvs, colors, normals, indices, triangle_count
## @param voxels: Raw voxel data (PackedByteArray).
## @param chunk_offset: World position offset for mesh positioning.
## @param chunk_color: Tint color for vertex coloring.
## @param tiles_per_row: Texture atlas tiles per row (default 2).
## @return Dictionary: Mesh data ready for apply_mesh().
static func generate_mesh_arrays(
	voxels: PackedByteArray,
	chunk_offset: Vector3,
	chunk_color: Color,
	tiles_per_row: int = 2
) -> Dictionary:
	var arrays := MeshBuilderClass.create_arrays()
	var triangle_count: int = 0
	var vertex_index: int = 0
	
	# Face neighbor offsets for visibility checks
	var face_offsets := {
		BlockDefinitions.Face.POS_X: Vector3i(1, 0, 0),
		BlockDefinitions.Face.NEG_X: Vector3i(-1, 0, 0),
		BlockDefinitions.Face.POS_Y: Vector3i(0, 1, 0),
		BlockDefinitions.Face.NEG_Y: Vector3i(0, -1, 0),
		BlockDefinitions.Face.POS_Z: Vector3i(0, 0, 1),
		BlockDefinitions.Face.NEG_Z: Vector3i(0, 0, -1),
	}
	
	for y in range(CHUNK_HEIGHT):
		for z in range(CHUNK_DEPTH):
			for x in range(CHUNK_WIDTH):
				var idx: int = x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_DEPTH
				var block_id: int = voxels[idx]
				if block_id == 0:  # AIR
					continue
				
				var pos := Vector3(x, y, z) + chunk_offset
				
				# Check each face for visibility
				for face in face_offsets:
					var offset: Vector3i = face_offsets[face]
					if is_air_local(voxels, x + offset.x, y + offset.y, z + offset.z):
						vertex_index += MeshBuilderClass.add_face(arrays, vertex_index, pos, face, block_id, chunk_color, tiles_per_row)
						triangle_count += 2
	
	return MeshBuilderClass.to_mesh_data(arrays, triangle_count)


## Checks if local position is air (thread-safe, no cross-chunk lookups).
## Treats out-of-bounds coordinates as air (for mesh generation edge handling).
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
