## ChunkSerializer
## Handles saving and loading chunk data to/from disk.
## Uses RLE (Run-Length Encoding) compression for efficient storage.
class_name ChunkSerializer
extends RefCounted


# -------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------

const MAGIC: String = "VXL"
const VERSION: int = 1
const SAVE_DIR: String = "user://save/"


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Saves a chunk's voxel data to disk.
## File format: [MAGIC 3B][VERSION 1B][X 4B][Z 4B][RLE DATA...]
static func save_chunk(chunk: Chunk) -> void:
	_ensure_save_dir()
	
	var key: Vector2i = chunk.key
	var path: String = _get_chunk_path(key)
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ChunkSerializer: Cannot write to %s" % path)
		return
	
	# Write header
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_8(VERSION)
	file.store_32(key.x)
	file.store_32(key.y)
	
	# Get voxel data and compress with RLE
	var voxels := _get_voxels_from_chunk(chunk)
	var rle_data := encode_rle(voxels)
	
	# Write RLE data
	file.store_32(rle_data.size())
	file.store_buffer(rle_data)
	
	file.close()
	print("ChunkSerializer: Saved chunk (%d, %d) - %d bytes" % [key.x, key.y, rle_data.size()])


## Loads a chunk's voxel data from disk.
## Returns null if chunk file doesn't exist.
static func load_chunk(coord: Vector2i) -> PackedByteArray:
	var path: String = _get_chunk_path(coord)
	
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ChunkSerializer: Cannot read from %s" % path)
		return PackedByteArray()
	
	# Read and validate header
	var magic := file.get_buffer(3).get_string_from_ascii()
	if magic != MAGIC:
		push_error("ChunkSerializer: Invalid magic in %s" % path)
		file.close()
		return PackedByteArray()
	
	var version := file.get_8()
	if version != VERSION:
		push_warning("ChunkSerializer: Version mismatch in %s (got %d, expected %d)" % [path, version, VERSION])
	
	var x := file.get_32()
	var z := file.get_32()
	
	if x != coord.x or z != coord.y:
		push_warning("ChunkSerializer: Coordinate mismatch in %s" % path)
	
	# Read RLE data
	var rle_size := file.get_32()
	var rle_data := file.get_buffer(rle_size)
	
	file.close()
	
	# Decode RLE
	var voxels := decode_rle(rle_data)
	print("ChunkSerializer: Loaded chunk (%d, %d) - %d voxels" % [coord.x, coord.y, voxels.size()])
	
	return voxels


## Checks if a saved chunk exists for the given coordinate.
static func chunk_exists(coord: Vector2i) -> bool:
	return FileAccess.file_exists(_get_chunk_path(coord))


## Deletes a saved chunk file.
static func delete_chunk(coord: Vector2i) -> void:
	var path: String = _get_chunk_path(coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# -------------------------------------------------------------------
# RLE Compression
# -------------------------------------------------------------------

## Encodes voxel data using Run-Length Encoding.
## Format: [COUNT 1B][VALUE 1B]...
## If count > 255, uses multiple runs.
static func encode_rle(data: PackedByteArray) -> PackedByteArray:
	if data.size() == 0:
		return PackedByteArray()
	
	var result := PackedByteArray()
	var current_value: int = data[0]
	var count: int = 1
	
	for i in range(1, data.size()):
		var value: int = data[i]
		
		if value == current_value and count < 255:
			count += 1
		else:
			result.append(count)
			result.append(current_value)
			current_value = value
			count = 1
	
	# Write final run
	result.append(count)
	result.append(current_value)
	
	return result


## Decodes RLE-encoded data back to voxel array.
static func decode_rle(rle_data: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	
	var i: int = 0
	while i < rle_data.size() - 1:
		var count: int = rle_data[i]
		var value: int = rle_data[i + 1]
		
		for _j in range(count):
			result.append(value)
		
		i += 2
	
	return result


# -------------------------------------------------------------------
# Private Helpers
# -------------------------------------------------------------------

## Returns the file path for a chunk coordinate.
static func _get_chunk_path(coord: Vector2i) -> String:
	return SAVE_DIR + "chunk_%d_%d.chk" % [coord.x, coord.y]


## Ensures the save directory exists.
static func _ensure_save_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("save"):
		dir.make_dir("save")


## Gets voxel data from chunk (handles private variable access).
static func _get_voxels_from_chunk(chunk: Chunk) -> PackedByteArray:
	var voxels := PackedByteArray()
	voxels.resize(Chunk.VOLUME)
	
	for y in range(Chunk.HEIGHT):
		for z in range(Chunk.DEPTH):
			for x in range(Chunk.WIDTH):
				var idx: int = x + z * Chunk.WIDTH + y * Chunk.WIDTH * Chunk.DEPTH
				voxels[idx] = chunk.get_voxel(x, y, z)
	
	return voxels
