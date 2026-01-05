## Test: Coordinate Math
## GUT unit tests specifically for coordinate conversion edge cases.
## Critical for ensuring negative coordinates work correctly.
extends GutTest


# -------------------------------------------------------------------
# Documented Risk Tests (from 07_open_questions_and_risks.md)
# -------------------------------------------------------------------

func test_negative_one_maps_to_chunk_negative_one() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-1, 0, -1))
	assert_eq(result, Vector2i(-1, -1), "Position -1,-1 should be in chunk (-1,-1)")
	manager.free()


func test_negative_sixteen_maps_to_chunk_negative_one() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-16, 0, 0))
	assert_eq(result, Vector2i(-1, 0), "Position -16 should be in chunk -1")
	manager.free()


func test_negative_seventeen_maps_to_chunk_negative_one() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-17, 0, 0))
	assert_eq(result, Vector2i(-1, 0), "Position -17 should be in chunk -1")
	manager.free()


func test_negative_thirty_two_maps_to_chunk_negative_one() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-32, 0, 0))
	assert_eq(result, Vector2i(-1, 0), "Position -32 should be in chunk -1")
	manager.free()


func test_negative_thirty_three_maps_to_chunk_negative_two() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_chunk_coord(Vector3(-33, 0, 0))
	assert_eq(result, Vector2i(-2, 0), "Position -33 should be in chunk -2")
	manager.free()


# -------------------------------------------------------------------
# Local Voxel with Negative Coordinates
# -------------------------------------------------------------------

func test_local_voxel_negative_one_is_31() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(-1, 0, 0))
	assert_eq(result.x, 31, "Local x of -1 should be 31")
	manager.free()


func test_local_voxel_negative_32_is_0() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(-32, 0, 0))
	assert_eq(result.x, 0, "Local x of -32 should be 0")
	manager.free()


func test_local_voxel_negative_33_is_31() -> void:
	var manager := ChunkManager.new()
	var result := manager.world_to_local_voxel(Vector3(-33, 0, 0))
	assert_eq(result.x, 31, "Local x of -33 should be 31 (in chunk -2)")
	manager.free()


# -------------------------------------------------------------------
# Boundary Crossing Tests
# -------------------------------------------------------------------

func test_chunk_boundary_32_to_33() -> void:
	var manager := ChunkManager.new()
	var before := manager.world_to_chunk_coord(Vector3(31, 0, 0))
	var after := manager.world_to_chunk_coord(Vector3(32, 0, 0))
	assert_eq(before, Vector2i(0, 0))
	assert_eq(after, Vector2i(1, 0))
	manager.free()


func test_chunk_boundary_zero_to_negative_one() -> void:
	var manager := ChunkManager.new()
	var before := manager.world_to_chunk_coord(Vector3(0, 0, 0))
	var after := manager.world_to_chunk_coord(Vector3(-1, 0, 0))
	assert_eq(before, Vector2i(0, 0))
	assert_eq(after, Vector2i(-1, 0))
	manager.free()


# -------------------------------------------------------------------
# Posmod Verification
# -------------------------------------------------------------------

func test_posmod_behavior_matches_expected() -> void:
	# Verify GDScript posmod behaves as expected
	assert_eq(posmod(-1, 32), 31)
	assert_eq(posmod(-32, 32), 0)
	assert_eq(posmod(-33, 32), 31)
	assert_eq(posmod(0, 32), 0)
	assert_eq(posmod(31, 32), 31)
	assert_eq(posmod(32, 32), 0)


# -------------------------------------------------------------------
# Documentation Example Validation
# -------------------------------------------------------------------

func test_doc_example_world_to_chunk_coord() -> void:
	# From 05_logic_and_workflows.md
	var manager := ChunkManager.new()
	
	# floor(-1 / 32) should be -1
	var result := manager.world_to_chunk_coord(Vector3(-1, 0, -1))
	assert_eq(result, Vector2i(-1, -1))
	
	manager.free()


func test_doc_example_world_to_local_voxel() -> void:
	# From 05_logic_and_workflows.md
	var manager := ChunkManager.new()
	
	# posmod(-1, 32) should be 31
	var result := manager.world_to_local_voxel(Vector3(-1, 5, -1))
	assert_eq(result, Vector3i(31, 5, 31))
	
	manager.free()
