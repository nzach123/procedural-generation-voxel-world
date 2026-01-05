## BlockRegistry
## Singleton providing global access to block definitions.
## Maps integer IDs (byte) to BlockData resources.
class_name BlockRegistry
extends Node

const BLOCKS_PATH: String = "res://data/blocks/"
const AIR_ID: int = 0

## Chunk dimensions - single source of truth.
const CHUNK_SIZE: Vector3i = Vector3i(32, 32, 32)
const CHUNK_WIDTH: int = 32
const CHUNK_HEIGHT: int = 32
const CHUNK_DEPTH: int = 32

## Dictionary mapping block ID (int) -> BlockData resource.
var _blocks: Dictionary = {}


func _ready() -> void:
	_load_all_blocks()


## Registers a new block type. Called during initialization or for dynamic blocks.
func register_block(id: int, data: BlockData) -> void:
	if id < 0 or id > 255:
		push_error("BlockRegistry: Invalid block ID %d (must be 0-255)" % id)
		return
	if _blocks.has(id):
		push_warning("BlockRegistry: Overwriting block ID %d" % id)
	_blocks[id] = data
	print("BlockRegistry: Registered block %d (%s)" % [id, data.block_name])


## Retrieves the BlockData resource for a given ID.
## Returns null if ID is not registered.
func get_block_data(id: int) -> BlockData:
	return _blocks.get(id, null)


## Returns true if the block ID is registered and solid.
func is_solid(id: int) -> bool:
	var data: BlockData = get_block_data(id)
	if data == null:
		return false
	return data.is_solid


## Returns true if the block ID is registered and transparent.
func is_transparent(id: int) -> bool:
	var data: BlockData = get_block_data(id)
	if data == null:
		return true  # Unregistered blocks treated as transparent (air-like)
	return data.is_transparent


## Returns the texture atlas coordinates for a block ID.
func get_texture_coords(id: int) -> Vector2i:
	var data: BlockData = get_block_data(id)
	if data == null:
		return Vector2i.ZERO
	return data.texture_atlas_coords


## Loads all .tres files from BLOCKS_PATH and registers them.
## File naming convention: <id>_<name>.tres (e.g., "01_dirt.tres")
func _load_all_blocks() -> void:
	var dir := DirAccess.open(BLOCKS_PATH)
	if dir == null:
		push_warning("BlockRegistry: Cannot open blocks directory: %s" % BLOCKS_PATH)
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path: String = BLOCKS_PATH + file_name
			var resource: Resource = load(full_path)
			
			if resource is BlockData:
				# Extract ID from filename: "01_dirt.tres" -> 1
				var id_str: String = file_name.split("_")[0]
				var id: int = id_str.to_int()
				register_block(id, resource as BlockData)
			else:
				push_warning("BlockRegistry: %s is not a BlockData resource" % full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	print("BlockRegistry: Loaded %d blocks" % _blocks.size())
