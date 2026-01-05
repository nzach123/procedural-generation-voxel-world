## Test: Chunk
## GUT unit tests for chunk.gd voxel storage and meshing.
extends GutTest


# -------------------------------------------------------------------
# Test Fixtures
# -------------------------------------------------------------------

var _chunk: Chunk


func before_each() -> void:
	_chunk = Chunk.new()
	add_child_autofree(_chunk)
	# Wait for _ready to complete
	await get_tree().process_frame


func after_each() -> void:
	_chunk = null


# -------------------------------------------------------------------
# Constants Tests
# -------------------------------------------------------------------

func test_chunk_dimensions_are_32x32x32() -> void:
	assert_eq(Chunk.WIDTH, 32, "Width should be 32")
	assert_eq(Chunk.HEIGHT, 32, "Height should be 32")
	assert_eq(Chunk.DEPTH, 32, "Depth should be 32")
	assert_eq(Chunk.VOLUME, 32768, "Volume should be 32^3")


func test_air_id_is_zero() -> void:
	assert_eq(Chunk.AIR_ID, 0, "AIR_ID should be 0")


# -------------------------------------------------------------------
# Voxel Storage Tests (get_voxel / set_voxel)
# -------------------------------------------------------------------

func test_get_voxel_returns_air_for_unset_position() -> void:
	var result: int = _chunk.get_voxel(5, 5, 5)
	assert_eq(result, Chunk.AIR_ID, "Unset voxel should return AIR_ID")


func test_set_voxel_and_get_voxel_roundtrip() -> void:
	_chunk.set_voxel(10, 15, 20, 2)
	var result: int = _chunk.get_voxel(10, 15, 20)
	assert_eq(result, 2, "Should retrieve the value that was set")


func test_set_voxel_at_origin() -> void:
	_chunk.set_voxel(0, 0, 0, 1)
	assert_eq(_chunk.get_voxel(0, 0, 0), 1, "Origin voxel should be settable")


func test_set_voxel_at_max_bounds() -> void:
	_chunk.set_voxel(31, 31, 31, 3)
	assert_eq(_chunk.get_voxel(31, 31, 31), 3, "Max corner should be settable")


func test_get_voxel_out_of_bounds_negative_returns_air() -> void:
	assert_eq(_chunk.get_voxel(-1, 0, 0), Chunk.AIR_ID, "Negative X should return AIR")
	assert_eq(_chunk.get_voxel(0, -1, 0), Chunk.AIR_ID, "Negative Y should return AIR")
	assert_eq(_chunk.get_voxel(0, 0, -1), Chunk.AIR_ID, "Negative Z should return AIR")


func test_get_voxel_out_of_bounds_over_max_returns_air() -> void:
	assert_eq(_chunk.get_voxel(32, 0, 0), Chunk.AIR_ID, "X=32 should return AIR")
	assert_eq(_chunk.get_voxel(0, 32, 0), Chunk.AIR_ID, "Y=32 should return AIR")
	assert_eq(_chunk.get_voxel(0, 0, 32), Chunk.AIR_ID, "Z=32 should return AIR")


func test_set_voxel_out_of_bounds_does_not_crash() -> void:
	# These should silently fail, not crash
	_chunk.set_voxel(-1, 0, 0, 1)
	_chunk.set_voxel(0, -1, 0, 1)
	_chunk.set_voxel(0, 0, -1, 1)
	_chunk.set_voxel(32, 0, 0, 1)
	_chunk.set_voxel(0, 32, 0, 1)
	_chunk.set_voxel(0, 0, 32, 1)
	pass_test("Out of bounds set_voxel should not crash")


func test_multiple_voxels_do_not_interfere() -> void:
	_chunk.set_voxel(0, 0, 0, 1)
	_chunk.set_voxel(1, 0, 0, 2)
	_chunk.set_voxel(0, 1, 0, 3)
	_chunk.set_voxel(0, 0, 1, 4)
	
	assert_eq(_chunk.get_voxel(0, 0, 0), 1)
	assert_eq(_chunk.get_voxel(1, 0, 0), 2)
	assert_eq(_chunk.get_voxel(0, 1, 0), 3)
	assert_eq(_chunk.get_voxel(0, 0, 1), 4)


# -------------------------------------------------------------------
# set_voxels_raw Tests
# -------------------------------------------------------------------

func test_set_voxels_raw_with_correct_size() -> void:
	var raw := PackedByteArray()
	raw.resize(Chunk.VOLUME)
	raw.fill(0)
	raw[0] = 5
	raw[100] = 7
	
	_chunk.set_voxels_raw(raw)
	
	assert_eq(_chunk.get_voxel(0, 0, 0), 5, "First voxel should be 5")


func test_set_voxels_raw_with_wrong_size_is_ignored() -> void:
	_chunk.set_voxel(5, 5, 5, 9)
	
	var wrong_size := PackedByteArray()
	wrong_size.resize(100)  # Wrong size
	wrong_size.fill(1)
	
	_chunk.set_voxels_raw(wrong_size)
	
	assert_eq(_chunk.get_voxel(5, 5, 5), 9, "Original value should remain")


# -------------------------------------------------------------------
# is_air Tests
# -------------------------------------------------------------------

func test_is_air_returns_true_for_empty_voxel() -> void:
	assert_true(_chunk.is_air(5, 5, 5), "Empty voxel should be air")


func test_is_air_returns_false_for_solid_voxel() -> void:
	_chunk.set_voxel(5, 5, 5, 1)
	assert_false(_chunk.is_air(5, 5, 5), "Solid voxel should not be air")


func test_is_air_boundary_returns_true_without_manager() -> void:
	# Without chunk_manager, out of bounds should return true
	assert_true(_chunk.is_air(-1, 5, 5), "Out of bounds should return true")
	assert_true(_chunk.is_air(32, 5, 5), "Out of bounds should return true")


# -------------------------------------------------------------------
# check_block_selected Tests
# -------------------------------------------------------------------

func test_check_block_selected_returns_false_for_air() -> void:
	_chunk.chunk_offset = Vector3.ZERO
	assert_false(_chunk.check_block_selected(Vector3i(5, 5, 5)))


func test_check_block_selected_returns_true_for_solid() -> void:
	_chunk.chunk_offset = Vector3.ZERO
	_chunk.set_voxel(5, 5, 5, 1)
	assert_true(_chunk.check_block_selected(Vector3i(5, 5, 5)))


# -------------------------------------------------------------------
# get_triangle_count Tests
# -------------------------------------------------------------------

func test_get_triangle_count_initially_zero() -> void:
	assert_eq(_chunk.get_triangle_count(), 0)


# -------------------------------------------------------------------
# Indexing Formula Tests
# -------------------------------------------------------------------

func test_flat_index_formula_consistency() -> void:
	# Test that x + z*WIDTH + y*WIDTH*DEPTH gives unique indices
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
