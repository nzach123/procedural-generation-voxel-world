## Test: ChunkSerializer
## GUT unit tests for chunk_serializer.gd RLE compression and file I/O.
extends GutTest


# -------------------------------------------------------------------
# RLE Encoding Tests
# -------------------------------------------------------------------

func test_encode_rle_empty_array() -> void:
	var empty := PackedByteArray()
	var result := ChunkSerializer.encode_rle(empty)
	assert_eq(result.size(), 0, "Empty input should produce empty output")


func test_encode_rle_single_value() -> void:
	var data := PackedByteArray([5])
	var result := ChunkSerializer.encode_rle(data)
	assert_eq(result.size(), 2, "Single value should produce 2 bytes (count, value)")
	assert_eq(result[0], 1, "Count should be 1")
	assert_eq(result[1], 5, "Value should be 5")


func test_encode_rle_repeated_values() -> void:
	var data := PackedByteArray([7, 7, 7, 7, 7])
	var result := ChunkSerializer.encode_rle(data)
	assert_eq(result.size(), 2, "5 same values should produce 2 bytes")
	assert_eq(result[0], 5, "Count should be 5")
	assert_eq(result[1], 7, "Value should be 7")


func test_encode_rle_alternating_values() -> void:
	var data := PackedByteArray([1, 2, 1, 2])
	var result := ChunkSerializer.encode_rle(data)
	# Each value has count 1: [1,1], [1,2], [1,1], [1,2] = 8 bytes
	assert_eq(result.size(), 8, "Alternating values have no compression")


func test_encode_rle_max_run_length() -> void:
	var data := PackedByteArray()
	data.resize(300)
	data.fill(9)
	
	var result := ChunkSerializer.encode_rle(data)
	# Should split into 255 + 45 = two runs
	assert_eq(result.size(), 4, "300 values should split into 2 runs")
	assert_eq(result[0], 255, "First run count should be 255")
	assert_eq(result[1], 9, "First run value should be 9")
	assert_eq(result[2], 45, "Second run count should be 45")
	assert_eq(result[3], 9, "Second run value should be 9")


# -------------------------------------------------------------------
# RLE Decoding Tests
# -------------------------------------------------------------------

func test_decode_rle_empty_array() -> void:
	var empty := PackedByteArray()
	var result := ChunkSerializer.decode_rle(empty)
	assert_eq(result.size(), 0, "Empty input should produce empty output")


func test_decode_rle_single_run() -> void:
	var rle := PackedByteArray([3, 5])  # 3 fives
	var result := ChunkSerializer.decode_rle(rle)
	assert_eq(result.size(), 3)
	assert_eq(result[0], 5)
	assert_eq(result[1], 5)
	assert_eq(result[2], 5)


func test_decode_rle_multiple_runs() -> void:
	var rle := PackedByteArray([2, 1, 3, 2])  # 2 ones, 3 twos
	var result := ChunkSerializer.decode_rle(rle)
	assert_eq(result.size(), 5)
	assert_eq(result[0], 1)
	assert_eq(result[1], 1)
	assert_eq(result[2], 2)
	assert_eq(result[3], 2)
	assert_eq(result[4], 2)


# -------------------------------------------------------------------
# RLE Roundtrip Tests
# -------------------------------------------------------------------

func test_rle_roundtrip_random_data() -> void:
	var original := PackedByteArray()
	original.resize(1000)
	for i in range(1000):
		original[i] = randi() % 256
	
	var encoded := ChunkSerializer.encode_rle(original)
	var decoded := ChunkSerializer.decode_rle(encoded)
	
	assert_eq(decoded.size(), original.size(), "Sizes should match")
	for i in range(original.size()):
		if decoded[i] != original[i]:
			fail_test("Mismatch at index %d" % i)
			return
	pass_test("Roundtrip successful")


func test_rle_roundtrip_terrain_like_data() -> void:
	# Simulate terrain: mostly air (0) with some solid (1-3) at bottom
	var original := PackedByteArray()
	original.resize(32768)  # Chunk volume
	original.fill(0)
	
	# Fill bottom 1/4 with dirt
	for i in range(8192):
		original[i] = 2
	
	var encoded := ChunkSerializer.encode_rle(original)
	var decoded := ChunkSerializer.decode_rle(encoded)
	
	assert_eq(decoded.size(), original.size())
	# Verify compression ratio is good for terrain-like data
	gut.p("Compression: %d -> %d bytes (%.1f%%)" % [
		original.size(), encoded.size(), 
		100.0 * encoded.size() / original.size()
	])
	assert_lt(encoded.size(), original.size() / 10, "Should compress well")


# -------------------------------------------------------------------
# File Path Tests
# -------------------------------------------------------------------

func test_chunk_exists_returns_false_for_missing() -> void:
	var result := ChunkSerializer.chunk_exists(Vector2i(99999, 99999))
	assert_false(result, "Non-existent chunk should return false")


# -------------------------------------------------------------------
# Edge Cases
# -------------------------------------------------------------------

func test_encode_decode_all_zeros() -> void:
	var zeros := PackedByteArray()
	zeros.resize(1000)
	zeros.fill(0)
	
	var encoded := ChunkSerializer.encode_rle(zeros)
	assert_lte(encoded.size(), 8, "1000 zeros should compress to <=8 bytes")
	
	var decoded := ChunkSerializer.decode_rle(encoded)
	assert_eq(decoded.size(), 1000)


func test_encode_decode_all_same_value() -> void:
	var data := PackedByteArray()
	data.resize(32768)
	data.fill(42)
	
	var encoded := ChunkSerializer.encode_rle(data)
	# 32768 / 255 = 128.5 -> 129 runs of 2 bytes each
	assert_lte(encoded.size(), 260, "All same value should compress very well")
	
	var decoded := ChunkSerializer.decode_rle(encoded)
	assert_eq(decoded.size(), 32768)
	assert_eq(decoded[0], 42)
	assert_eq(decoded[32767], 42)
