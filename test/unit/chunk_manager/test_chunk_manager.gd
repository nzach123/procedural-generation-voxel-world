## Test: ChunkManager
## GUT unit tests for chunk_manager.gd coordinate conversion and world management.
extends GutTest


# -------------------------------------------------------------------
# Coordinate Conversion Tests (Pure Functions - No Scene Tree)
# -------------------------------------------------------------------

func test_world_to_chunk_coord_positive_origin() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(0, 0, 0))
	assert_eq(result, Vector2i(0, 0), "Origin should map to chunk (0,0)")
	manager.free()


func test_world_to_chunk_coord_within_first_chunk() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(15, 5, 20))
	assert_eq(result, Vector2i(0, 0), "Position 15,5,20 should be in chunk (0,0)")
	manager.free()


func test_world_to_chunk_coord_at_chunk_boundary() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(32, 0, 0))
	assert_eq(result, Vector2i(1, 0), "Position 32,0,0 should be in chunk (1,0)")
	manager.free()


func test_world_to_chunk_coord_negative_position() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-1, 0, 0))
	assert_eq(result, Vector2i(-1, 0), "Position -1,0,0 should be in chunk (-1,0)")
	manager.free()


func test_world_to_chunk_coord_negative_chunk_boundary() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-32, 0, -32))
	assert_eq(result, Vector2i(-1, -1), "Position -32,-32 should be in chunk (-1,-1)")
	manager.free()


func test_world_to_chunk_coord_far_negative() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-65, 0, -100))
	assert_eq(result, Vector2i(-3, -4), "Far negative position")
	manager.free()


# -------------------------------------------------------------------
# World to Local Voxel Tests
# -------------------------------------------------------------------

func test_world_to_local_voxel_positive_origin() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(0, 0, 0))
	assert_eq(result, Vector3i(0, 0, 0), "Origin should map to local (0,0,0)")
	manager.free()


func test_world_to_local_voxel_within_chunk() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(15, 10, 20))
	assert_eq(result, Vector3i(15, 10, 20), "Local coords within first chunk")
	manager.free()


func test_world_to_local_voxel_second_chunk() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(35, 5, 40))
	assert_eq(result, Vector3i(3, 5, 8), "Position 35,40 should map to local 3,8")
	manager.free()


func test_world_to_local_voxel_negative_uses_posmod() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(-1, 5, -1))
	assert_eq(result, Vector3i(31, 5, 31), "Negative -1 should wrap to 31 via posmod")
	manager.free()


func test_world_to_local_voxel_negative_exact_boundary() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(-32, 5, -32))
	assert_eq(result, Vector3i(0, 5, 0), "-32 should wrap to 0")
	manager.free()


func test_world_to_local_voxel_y_clamped() -> void:
	var manager := ChunkManager.new()
	var result_low := manager.world_to_local_voxel(Vector3(0, -10, 0))
	var result_high := manager.world_to_local_voxel(Vector3(0, 100, 0))
	assert_eq(result_low.y, 0, "Y should be clamped to min 0")
	assert_eq(result_high.y, 31, "Y should be clamped to max 31")
	manager.free()


# -------------------------------------------------------------------
# Static Thread-Safe Functions
# -------------------------------------------------------------------

func test_generate_voxel_data_threaded_returns_correct_size() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = 12345
	
	var voxels := ChunkManager.generate_voxel_data_threaded(
		noise, Vector3.ZERO, 16
	)
	
	assert_eq(voxels.size(), 32768, "Should return 32^3 voxels")


func test_generate_voxel_data_threaded_has_solid_blocks() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = 12345
	
	var voxels := ChunkManager.generate_voxel_data_threaded(
		noise, Vector3.ZERO, 16
	)
	
	var has_solid := false
	for i in range(voxels.size()):
		if voxels[i] != 0:
			has_solid = true
			break
	
	assert_true(has_solid, "Generated terrain should have solid blocks")


func test_is_air_local_within_bounds() -> void:
	var voxels := PackedByteArray()
	voxels.resize(32768)
	voxels.fill(0)
	voxels[0] = 1  # Set origin to solid
	
	assert_false(ChunkManager._is_air_local(voxels, 0, 0, 0), "Origin should be solid")
	assert_true(ChunkManager._is_air_local(voxels, 1, 0, 0), "Adjacent should be air")


func test_is_air_local_out_of_bounds_returns_true() -> void:
	var voxels := PackedByteArray()
	voxels.resize(32768)
	voxels.fill(1)  # All solid
	
	assert_true(ChunkManager._is_air_local(voxels, -1, 0, 0), "Negative X should be air")
	assert_true(ChunkManager._is_air_local(voxels, 32, 0, 0), "X=32 should be air")
	assert_true(ChunkManager._is_air_local(voxels, 0, -1, 0), "Negative Y should be air")
	assert_true(ChunkManager._is_air_local(voxels, 0, 32, 0), "Y=32 should be air")


# -------------------------------------------------------------------
# Mesh Array Generation Tests
# -------------------------------------------------------------------

func test_generate_mesh_arrays_threaded_empty_for_air() -> void:
	var voxels := PackedByteArray()
	voxels.resize(32768)
	voxels.fill(0)  # All air
	
	var result := ChunkManager.generate_mesh_arrays_threaded(
		voxels, Vector3.ZERO, Color.WHITE
	)
	
	assert_eq(result["triangle_count"], 0, "All-air chunk should have no triangles")
	assert_eq(result["vertices"].size(), 0, "Should have no vertices")


func test_generate_mesh_arrays_threaded_single_block() -> void:
	var voxels := PackedByteArray()
	voxels.resize(32768)
	voxels.fill(0)
	# Place a single block in the middle (surrounded by air)
	var idx: int = 16 + 16 * 32 + 16 * 32 * 32
	voxels[idx] = 1
	
	var result := ChunkManager.generate_mesh_arrays_threaded(
		voxels, Vector3.ZERO, Color.WHITE
	)
	
	# A single exposed block should have 6 faces * 2 triangles = 12 triangles
	assert_eq(result["triangle_count"], 12, "Single block should have 12 triangles (6 faces)")
	# 6 faces * 4 vertices = 24 vertices
	assert_eq(result["vertices"].size(), 24, "Should have 24 vertices")


func test_generate_mesh_arrays_threaded_face_culling() -> void:
	var voxels := PackedByteArray()
	voxels.resize(32768)
	voxels.fill(0)
	# Place two adjacent blocks
	var idx1: int = 16 + 16 * 32 + 16 * 32 * 32
	var idx2: int = 17 + 16 * 32 + 16 * 32 * 32  # X+1
	voxels[idx1] = 1
	voxels[idx2] = 1
	
	var result := ChunkManager.generate_mesh_arrays_threaded(
		voxels, Vector3.ZERO, Color.WHITE
	)
	
	# Two blocks share one face, so 2*6 - 2 = 10 visible faces = 20 triangles
	assert_eq(result["triangle_count"], 20, "Adjacent blocks should cull shared faces")


# -------------------------------------------------------------------
# Constants Tests
# -------------------------------------------------------------------

func test_chunk_constants_match_chunk_class() -> void:
	assert_eq(ChunkManager.CHUNK_WIDTH, Chunk.WIDTH)
	assert_eq(ChunkManager.CHUNK_HEIGHT, Chunk.HEIGHT)
	assert_eq(ChunkManager.CHUNK_DEPTH, Chunk.DEPTH)
