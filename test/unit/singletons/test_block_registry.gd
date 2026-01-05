## Test: BlockRegistry
## GUT unit tests for block_registry.gd singleton.
extends GutTest


# -------------------------------------------------------------------
# Constants Tests
# -------------------------------------------------------------------

func test_air_id_is_zero() -> void:
	assert_eq(BlockRegistry.AIR_ID, 0)


func test_chunk_size_is_32x32x32() -> void:
	assert_eq(BlockRegistry.CHUNK_SIZE, Vector3i(32, 32, 32))
	assert_eq(BlockRegistry.CHUNK_WIDTH, 32)
	assert_eq(BlockRegistry.CHUNK_HEIGHT, 32)
	assert_eq(BlockRegistry.CHUNK_DEPTH, 32)


func test_blocks_path_points_to_data() -> void:
	assert_eq(BlockRegistry.BLOCKS_PATH, "res://data/blocks/")


# -------------------------------------------------------------------
# Instance Tests (Requires Autoload)
# -------------------------------------------------------------------

# Note: These tests require BlockRegistry to be available as autoload
# If running standalone, these will be skipped

func test_registry_exists_as_autoload() -> void:
	if not Engine.has_singleton("BlockRegistry"):
		pending("BlockRegistry autoload not available")
		return
	pass_test("BlockRegistry autoload exists")


# -------------------------------------------------------------------
# BlockData Resource Tests
# -------------------------------------------------------------------

func test_block_data_resource_creation() -> void:
	var data := BlockData.new()
	data.block_name = "Test"
	data.texture_atlas_coords = Vector2i(1, 2)
	data.is_solid = true
	data.is_transparent = false
	
	assert_eq(data.block_name, "Test")
	assert_eq(data.texture_atlas_coords, Vector2i(1, 2))
	assert_true(data.is_solid)
	assert_false(data.is_transparent)


func test_block_data_defaults() -> void:
	var data := BlockData.new()
	assert_eq(data.block_name, "")
	assert_eq(data.texture_atlas_coords, Vector2i.ZERO)
	assert_true(data.is_solid)
	assert_false(data.is_transparent)
