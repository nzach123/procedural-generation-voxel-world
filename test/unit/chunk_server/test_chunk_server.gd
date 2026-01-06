## Test: ChunkServer
## GUT unit tests for chunk_server.gd RID-based chunk container.
extends GutTest


# -------------------------------------------------------------------
# Helper: Creates a fresh ChunkServer for each test
# RefCounted objects need local scope to ensure lifecycle
# -------------------------------------------------------------------

func _create_server() -> ChunkServer:
	return ChunkServer.new()


# -------------------------------------------------------------------
# Constants Tests (no instance needed)
# -------------------------------------------------------------------

func test_chunk_dimensions_are_32x32x32() -> void:
	assert_eq(ChunkServer.WIDTH, 32, "Width should be 32")
	assert_eq(ChunkServer.HEIGHT, 32, "Height should be 32")
	assert_eq(ChunkServer.DEPTH, 32, "Depth should be 32")
	assert_eq(ChunkServer.VOLUME, 32768, "Volume should be 32^3")


func test_air_id_is_zero() -> void:
	assert_eq(ChunkServer.AIR_ID, 0, "AIR_ID should be 0")


func test_aabb_margin_is_0_1() -> void:
	assert_almost_eq(ChunkServer.AABB_MARGIN, 0.1, 0.001, "AABB margin should be 0.1")


# -------------------------------------------------------------------
# Voxel Storage Tests
# -------------------------------------------------------------------

func test_get_voxel_returns_air_for_unset_position() -> void:
	var server := _create_server()
	var result: int = server.get_voxel(5, 5, 5)
	assert_eq(result, ChunkServer.AIR_ID, "Unset voxel should return AIR_ID")


func test_set_voxel_and_get_voxel_roundtrip() -> void:
	var server := _create_server()
	server.set_voxel(10, 15, 20, 2)
	var result: int = server.get_voxel(10, 15, 20)
	assert_eq(result, 2, "Should retrieve the value that was set")


func test_set_voxel_at_origin() -> void:
	var server := _create_server()
	server.set_voxel(0, 0, 0, 1)
	assert_eq(server.get_voxel(0, 0, 0), 1, "Origin voxel should be settable")


func test_set_voxel_at_max_bounds() -> void:
	var server := _create_server()
	server.set_voxel(31, 31, 31, 3)
	assert_eq(server.get_voxel(31, 31, 31), 3, "Max corner should be settable")


func test_get_voxel_out_of_bounds_negative_returns_air() -> void:
	var server := _create_server()
	assert_eq(server.get_voxel(-1, 0, 0), ChunkServer.AIR_ID, "Negative X should return AIR")
	assert_eq(server.get_voxel(0, -1, 0), ChunkServer.AIR_ID, "Negative Y should return AIR")
	assert_eq(server.get_voxel(0, 0, -1), ChunkServer.AIR_ID, "Negative Z should return AIR")


func test_get_voxel_out_of_bounds_over_max_returns_air() -> void:
	var server := _create_server()
	assert_eq(server.get_voxel(32, 0, 0), ChunkServer.AIR_ID, "X=32 should return AIR")
	assert_eq(server.get_voxel(0, 32, 0), ChunkServer.AIR_ID, "Y=32 should return AIR")
	assert_eq(server.get_voxel(0, 0, 32), ChunkServer.AIR_ID, "Z=32 should return AIR")


func test_set_voxel_out_of_bounds_does_not_crash() -> void:
	var server := _create_server()
	server.set_voxel(-1, 0, 0, 1)
	server.set_voxel(0, -1, 0, 1)
	server.set_voxel(0, 0, -1, 1)
	server.set_voxel(32, 0, 0, 1)
	server.set_voxel(0, 32, 0, 1)
	server.set_voxel(0, 0, 32, 1)
	pass_test("Out of bounds set_voxel should not crash")


func test_multiple_voxels_do_not_interfere() -> void:
	var server := _create_server()
	server.set_voxel(0, 0, 0, 1)
	server.set_voxel(1, 0, 0, 2)
	server.set_voxel(0, 1, 0, 3)
	server.set_voxel(0, 0, 1, 4)
	
	assert_eq(server.get_voxel(0, 0, 0), 1)
	assert_eq(server.get_voxel(1, 0, 0), 2)
	assert_eq(server.get_voxel(0, 1, 0), 3)
	assert_eq(server.get_voxel(0, 0, 1), 4)


# -------------------------------------------------------------------
# set_voxels_raw / get_voxels_raw Tests
# -------------------------------------------------------------------

func test_set_voxels_raw_with_correct_size() -> void:
	var server := _create_server()
	var raw := PackedByteArray()
	raw.resize(ChunkServer.VOLUME)
	raw.fill(0)
	raw[0] = 5
	
	server.set_voxels_raw(raw)
	
	assert_eq(server.get_voxel(0, 0, 0), 5, "First voxel should be 5")


func test_set_voxels_raw_with_wrong_size_is_ignored() -> void:
	var server := _create_server()
	server.set_voxel(5, 5, 5, 9)
	
	var wrong_size := PackedByteArray()
	wrong_size.resize(100)  # Wrong size
	wrong_size.fill(1)
	
	server.set_voxels_raw(wrong_size)
	
	assert_eq(server.get_voxel(5, 5, 5), 9, "Original value should remain")


func test_get_voxels_raw_returns_copy() -> void:
	var server := _create_server()
	server.set_voxel(0, 0, 0, 7)
	var raw := server.get_voxels_raw()
	
	# Modify the copy
	raw[0] = 99
	
	# Original should be unchanged
	assert_eq(server.get_voxel(0, 0, 0), 7, "Original should not be modified")


# -------------------------------------------------------------------
# Collision State Tests
# -------------------------------------------------------------------

func test_collision_disabled_by_default() -> void:
	var server := _create_server()
	assert_false(server.is_collision_enabled(), "Collision should be disabled initially")


func test_collision_layer_and_mask_defaults() -> void:
	var server := _create_server()
	assert_eq(server.collision_layer, 1, "Default collision layer should be 1")
	assert_eq(server.collision_mask, 1, "Default collision mask should be 1")


# -------------------------------------------------------------------
# AABB Calculation Tests
# -------------------------------------------------------------------

func test_aabb_includes_margin_at_origin() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3.ZERO
	var aabb: AABB = server._calculate_aabb()
	
	# Position should be negative due to margin
	assert_lt(aabb.position.x, 0.0, "AABB X should be negative")
	assert_lt(aabb.position.y, 0.0, "AABB Y should be negative")
	assert_lt(aabb.position.z, 0.0, "AABB Z should be negative")
	
	# Size should exceed chunk dimensions
	assert_gt(aabb.size.x, 32.0, "AABB width should exceed 32")
	assert_gt(aabb.size.y, 32.0, "AABB height should exceed 32")
	assert_gt(aabb.size.z, 32.0, "AABB depth should exceed 32")


func test_aabb_at_offset_position() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3(64, 0, 128)
	var aabb: AABB = server._calculate_aabb()
	
	# Position should be offset minus margin
	assert_almost_eq(aabb.position.x, 64.0 - 0.1, 0.001)
	assert_almost_eq(aabb.position.z, 128.0 - 0.1, 0.001)


# -------------------------------------------------------------------
# Triangle Count Tests
# -------------------------------------------------------------------

func test_get_triangle_count_initially_zero() -> void:
	var server := _create_server()
	assert_eq(server.get_triangle_count(), 0)


# -------------------------------------------------------------------
# Indexing Formula Tests
# -------------------------------------------------------------------

func test_flat_index_formula_consistency() -> void:
	var indices := {}
	var collision := false
	
	for y in range(4):  # Small subset for speed
		for z in range(4):
			for x in range(4):
				var idx: int = x + z * 32 + y * 32 * 32
				if indices.has(idx):
					collision = true
					break
				indices[idx] = true
	
	assert_false(collision, "Flat indexing should produce unique indices")
