## Test: ChunkManager Lifecycle
## GUT unit tests for chunk dictionary state and missing chunk handling.
## NOTE: ChunkManager is a Node with heavy _ready() initialization.
## Tests here use detached instances and avoid scene tree to prevent lock errors.
extends GutTest


# -------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------

var _manager: ChunkManager


func before_each() -> void:
	_manager = ChunkManager.new()
	# DO NOT add to tree - ChunkManager._ready() creates Timers and coroutines
	# that cause "Object is locked" errors during GUT teardown


func after_each() -> void:
	if is_instance_valid(_manager):
		_manager.free()
	_manager = null


# -------------------------------------------------------------------
# Initial State Tests (before _ready)
# -------------------------------------------------------------------

func test_chunks_dictionary_starts_empty() -> void:
	assert_eq(_manager._chunks.size(), 0, "Chunks should start empty")


func test_triangles_total_starts_at_zero() -> void:
	assert_eq(_manager.triangles_total, 0, "No triangles initially")


func test_chunk_size_property_is_32() -> void:
	assert_eq(_manager.chunk_size, 32, "Legacy property returns CHUNK_WIDTH")


# -------------------------------------------------------------------
# Get Chunk Tests (Missing Chunk Handling)
# -------------------------------------------------------------------

func test_get_chunk_returns_null_for_missing() -> void:
	var result := _manager.get_chunk(Vector2i(0, 0))
	assert_null(result, "Missing chunk returns null")


func test_get_chunk_returns_null_for_negative_coords() -> void:
	var result := _manager.get_chunk(Vector2i(-100, -100))
	assert_null(result, "Negative coords return null")


func test_get_chunk_at_world_pos_returns_null_for_unloaded() -> void:
	var result := _manager.get_chunk_at_world_pos(Vector3(1000, 0, 1000))
	assert_null(result, "Unloaded world position returns null")


# -------------------------------------------------------------------
# Set Voxel on Missing Chunk Tests
# -------------------------------------------------------------------

func test_set_voxel_on_missing_chunk_is_noop() -> void:
	# Should not crash, just no-op
	_manager.set_voxel(Vector3(0, 0, 0), 1)
	pass_test("set_voxel on missing chunk doesn't crash")


func test_set_voxel_on_missing_negative_chunk_is_noop() -> void:
	# Negative world position, no chunk loaded
	_manager.set_voxel(Vector3(-100, 0, -100), 2)
	pass_test("set_voxel on missing negative chunk doesn't crash")


# -------------------------------------------------------------------
# is_air_world Tests (Documented Behavior)
# -------------------------------------------------------------------

func test_is_air_world_returns_true_for_unloaded_chunk() -> void:
	# Per HANDOFF.md: "Unloaded chunks treated as air"
	var result := _manager.is_air_world(0, 0, 0)
	assert_true(result, "Unloaded returns true (air)")


func test_is_air_world_returns_true_for_far_negative() -> void:
	var result := _manager.is_air_world(-1000, 0, -1000)
	assert_true(result, "Far negative unloaded is air")


func test_is_air_world_returns_true_for_high_y() -> void:
	var result := _manager.is_air_world(0, 1000, 0)
	assert_true(result, "High Y unloaded is air")


# -------------------------------------------------------------------
# Constants Consistency Tests (Class-level, no instance needed)
# -------------------------------------------------------------------

func test_chunk_width_constant() -> void:
	assert_eq(ChunkManager.CHUNK_WIDTH, 32)


func test_chunk_height_constant() -> void:
	assert_eq(ChunkManager.CHUNK_HEIGHT, 32)


func test_chunk_depth_constant() -> void:
	assert_eq(ChunkManager.CHUNK_DEPTH, 32)


func test_chunk_volume_constant() -> void:
	assert_eq(ChunkManager.CHUNK_VOLUME, 32768)


# -------------------------------------------------------------------
# Manager Instantiation Test
# -------------------------------------------------------------------

func test_manager_can_be_instantiated() -> void:
	# ChunkManager.new() should work even without scene tree
	assert_not_null(_manager)
	pass_test("ChunkManager instantiation works")
