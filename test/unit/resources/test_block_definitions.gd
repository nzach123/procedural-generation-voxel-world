## Test: BlockDefinitions
## GUT unit tests for block_definitions.gd enums and tile mappings.
extends GutTest


# -------------------------------------------------------------------
# Enum Value Tests
# -------------------------------------------------------------------

func test_block_type_air_is_zero() -> void:
	assert_eq(BlockDefinitions.BlockType.AIR, 0, "AIR should be 0")


func test_block_type_grass_is_one() -> void:
	assert_eq(BlockDefinitions.BlockType.GRASS, 1, "GRASS should be 1")


func test_block_type_dirt_is_two() -> void:
	assert_eq(BlockDefinitions.BlockType.DIRT, 2, "DIRT should be 2")


func test_block_type_stone_is_three() -> void:
	assert_eq(BlockDefinitions.BlockType.STONE, 3, "STONE should be 3")


# -------------------------------------------------------------------
# Face Enum Tests
# -------------------------------------------------------------------

func test_face_enum_has_six_values() -> void:
	# All required faces for a cube
	assert_eq(BlockDefinitions.Face.POS_X, 0)
	assert_eq(BlockDefinitions.Face.NEG_X, 1)
	assert_eq(BlockDefinitions.Face.POS_Y, 2)
	assert_eq(BlockDefinitions.Face.NEG_Y, 3)
	assert_eq(BlockDefinitions.Face.POS_Z, 4)
	assert_eq(BlockDefinitions.Face.NEG_Z, 5)


# -------------------------------------------------------------------
# Block Tiles Dictionary Tests
# -------------------------------------------------------------------

func test_block_tiles_has_all_block_types() -> void:
	assert_true(BlockDefinitions.BLOCK_TILES.has(BlockDefinitions.BlockType.AIR))
	assert_true(BlockDefinitions.BLOCK_TILES.has(BlockDefinitions.BlockType.GRASS))
	assert_true(BlockDefinitions.BLOCK_TILES.has(BlockDefinitions.BlockType.DIRT))
	assert_true(BlockDefinitions.BLOCK_TILES.has(BlockDefinitions.BlockType.STONE))


func test_air_block_has_no_faces() -> void:
	var air_faces: Dictionary = BlockDefinitions.BLOCK_TILES[BlockDefinitions.BlockType.AIR]
	assert_eq(air_faces.size(), 0, "AIR should have no face mappings")


func test_grass_block_has_all_faces() -> void:
	var grass_faces: Dictionary = BlockDefinitions.BLOCK_TILES[BlockDefinitions.BlockType.GRASS]
	assert_eq(grass_faces.size(), 6, "GRASS should have all 6 faces")
	assert_true(grass_faces.has(BlockDefinitions.Face.POS_X))
	assert_true(grass_faces.has(BlockDefinitions.Face.NEG_X))
	assert_true(grass_faces.has(BlockDefinitions.Face.POS_Y))
	assert_true(grass_faces.has(BlockDefinitions.Face.NEG_Y))
	assert_true(grass_faces.has(BlockDefinitions.Face.POS_Z))
	assert_true(grass_faces.has(BlockDefinitions.Face.NEG_Z))


func test_grass_top_face_differs_from_sides() -> void:
	var grass_faces: Dictionary = BlockDefinitions.BLOCK_TILES[BlockDefinitions.BlockType.GRASS]
	var top: int = grass_faces[BlockDefinitions.Face.POS_Y]
	var side: int = grass_faces[BlockDefinitions.Face.POS_X]
	assert_ne(top, side, "Grass top should differ from sides")


func test_dirt_block_has_uniform_faces() -> void:
	var dirt_faces: Dictionary = BlockDefinitions.BLOCK_TILES[BlockDefinitions.BlockType.DIRT]
	var first_tile: int = dirt_faces[BlockDefinitions.Face.POS_X]
	for face in dirt_faces.keys():
		assert_eq(dirt_faces[face], first_tile, "Dirt should have same tile on all faces")


func test_stone_block_has_uniform_faces() -> void:
	var stone_faces: Dictionary = BlockDefinitions.BLOCK_TILES[BlockDefinitions.BlockType.STONE]
	var first_tile: int = stone_faces[BlockDefinitions.Face.POS_X]
	for face in stone_faces.keys():
		assert_eq(stone_faces[face], first_tile, "Stone should have same tile on all faces")


# -------------------------------------------------------------------
# Tile Index Validity Tests
# -------------------------------------------------------------------

func test_all_tile_indices_are_non_negative() -> void:
	for block_type in BlockDefinitions.BLOCK_TILES.keys():
		var faces: Dictionary = BlockDefinitions.BLOCK_TILES[block_type]
		for face in faces.keys():
			var tile_idx: int = faces[face]
			assert_gte(tile_idx, 0, "Tile index should be >= 0")


func test_all_tile_indices_are_within_atlas() -> void:
	var max_tile: int = 3  # 2x2 atlas = 4 tiles (0-3)
	for block_type in BlockDefinitions.BLOCK_TILES.keys():
		var faces: Dictionary = BlockDefinitions.BLOCK_TILES[block_type]
		for face in faces.keys():
			var tile_idx: int = faces[face]
			assert_lte(tile_idx, max_tile, "Tile index should be <= %d" % max_tile)
