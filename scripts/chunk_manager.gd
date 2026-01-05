## ChunkManager
## Orchestrates infinite voxel terrain by managing chunk lifecycle.
## Uses Dictionary storage for sparse, infinite-coordinate support.
## Threading: Data and mesh generation run on WorkerThreadPool.
class_name ChunkManager
extends Node


# -------------------------------------------------------------------
# Signals
# -------------------------------------------------------------------

signal chunk_loaded(chunk: Chunk)
signal chunk_unloaded(key: Vector2i)


# -------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------

## Chunk dimensions (must match Chunk.gd).
const CHUNK_WIDTH: int = 32
const CHUNK_HEIGHT: int = 32
const CHUNK_DEPTH: int = 32
const CHUNK_VOLUME: int = CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_DEPTH


# -------------------------------------------------------------------
# Exports
# -------------------------------------------------------------------

## Size of the world in chunks (per axis, for initial generation).
@export var world_size: int = 4

## Maximum terrain height for noise generation.
@export var max_height: int = 16

## Noise scale multiplier.
@export var noise_scale: float = 0.05

## Reference to chunk scene (optional, can also create dynamically).
@export var chunk_scene: PackedScene

## Enable threaded generation (disable for debugging).
@export var use_threading: bool = true

## Collision radius in chunks. Only chunks within this distance from the player get collision.
@export var collision_radius: int = 2


# -------------------------------------------------------------------
# Public Variables
# -------------------------------------------------------------------

## Total triangle count across all chunks.
var triangles_total: int = 0

## Legacy compatibility: chunk_size property.
var chunk_size: int:
	get:
		return CHUNK_WIDTH


# -------------------------------------------------------------------
# Private Variables
# -------------------------------------------------------------------

## Active chunks dictionary: Vector2i -> Chunk
var _chunks: Dictionary = {}

## Triangle counts per chunk: Vector2i -> int
var _chunk_triangles: Dictionary = {}

## Pending chunk generation tasks: Vector2i -> task_id
var _pending_chunks: Dictionary = {}

## Pending chunk rebuild tasks (for deduplication): Vector2i -> true
var _pending_rebuilds: Dictionary = {}

## Noise generator (thread-safe for read operations).
var _noise: FastNoiseLite

## Mutex for thread-safe chunk dictionary access.
var _chunks_mutex: Mutex


# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _ready() -> void:
	_chunks_mutex = Mutex.new()
	
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.seed = 20140114
	_noise.frequency = noise_scale
	
	# Generate initial world
	_generate_initial_world()


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Returns the chunk at the given chunk coordinate, or null if not loaded.
func get_chunk(coord: Vector2i) -> Chunk:
	return _chunks.get(coord, null)


## Sets a voxel at a global world position.
func set_voxel(global_pos: Vector3, block_id: int) -> void:
	var chunk_coord := world_to_chunk_coord(global_pos)
	var local := world_to_local_voxel(global_pos)
	
	var chunk := get_chunk(chunk_coord)
	if chunk:
		chunk.set_voxel(local.x, local.y, local.z, block_id)
		chunk.mark_dirty()


## Converts world position to chunk coordinate.
func world_to_chunk_coord(global_pos: Vector3) -> Vector2i:
	var cx: int = int(floor(global_pos.x / CHUNK_WIDTH))
	var cz: int = int(floor(global_pos.z / CHUNK_DEPTH))
	return Vector2i(cx, cz)


## Converts world position to local voxel coordinate within a chunk.
func world_to_local_voxel(global_pos: Vector3) -> Vector3i:
	var local_x: int = posmod(int(floor(global_pos.x)), CHUNK_WIDTH)
	var local_y: int = clampi(int(floor(global_pos.y)), 0, CHUNK_HEIGHT - 1)
	var local_z: int = posmod(int(floor(global_pos.z)), CHUNK_DEPTH)
	return Vector3i(local_x, local_y, local_z)


## Legacy compatibility: checks if world position is air.
func is_air_world(wx: int, wy: int, wz: int) -> bool:
	var global_pos := Vector3(wx, wy, wz)
	var chunk_coord := world_to_chunk_coord(global_pos)
	
	var chunk := get_chunk(chunk_coord)
	if chunk == null:
		return true  # Unloaded chunks treated as air
	
	var local := world_to_local_voxel(global_pos)
	return chunk.get_voxel(local.x, local.y, local.z) == Chunk.AIR_ID


## Legacy compatibility: add block at world coordinates.
func add_block_world(world_coords: Vector3i) -> void:
	var global_pos := Vector3(world_coords.x, world_coords.y, world_coords.z)
	set_voxel(global_pos, BlockDefinitions.BlockType.DIRT)
	_update_neighbors_at(world_coords)


## Legacy compatibility: delete block at world coordinates.
func delete_block_world(world_coords: Vector3i) -> void:
	var global_pos := Vector3(world_coords.x, world_coords.y, world_coords.z)
	set_voxel(global_pos, Chunk.AIR_ID)
	_update_neighbors_at(world_coords)


# -------------------------------------------------------------------
# Threading API
# -------------------------------------------------------------------

## Generates voxel data on a worker thread (THREAD-SAFE).
## Returns a PackedByteArray with voxel IDs.
static func generate_voxel_data_threaded(
	noise: FastNoiseLite,
	chunk_offset: Vector3,
	max_h: int
) -> PackedByteArray:
	var voxels := PackedByteArray()
	voxels.resize(CHUNK_VOLUME)
	voxels.fill(0)  # AIR
	
	for x in range(CHUNK_WIDTH):
		for z in range(CHUNK_DEPTH):
			var world_x: float = x + chunk_offset.x
			var world_z: float = z + chunk_offset.z
			
			var height: int = int((noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5 * max_h)
			height = clampi(height, 0, CHUNK_HEIGHT - 1)
			
			for y in range(CHUNK_HEIGHT):
				var block_id: int = 0  # AIR
				if y < height:
					block_id = BlockDefinitions.BlockType.DIRT
				elif y == height:
					if y > 15:
						block_id = BlockDefinitions.BlockType.STONE
					else:
						block_id = BlockDefinitions.BlockType.GRASS
				
				# Flat index: x + z*WIDTH + y*WIDTH*DEPTH
				var idx: int = x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_DEPTH
				voxels[idx] = block_id
	
	return voxels


## Generates mesh arrays on a worker thread (THREAD-SAFE).
## Returns a Dictionary with keys: vertices, uvs, colors, normals, indices, triangle_count
static func generate_mesh_arrays_threaded(
	voxels: PackedByteArray,
	chunk_offset: Vector3,
	chunk_color: Color,
	tiles_per_row: int = 2
) -> Dictionary:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	
	var triangle_count: int = 0
	var vertex_index: int = 0
	var tile_size: float = 1.0 / tiles_per_row
	
	for y in range(CHUNK_HEIGHT):
		for z in range(CHUNK_DEPTH):
			for x in range(CHUNK_WIDTH):
				var idx: int = x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_DEPTH
				var block_id: int = voxels[idx]
				if block_id == 0:  # AIR
					continue
				
				var pos := Vector3(x, y, z) + chunk_offset
				
				# Check each face for visibility (no cross-chunk checks in thread)
				# +X face
				if _is_air_local(voxels, x + 1, y, z):
					_add_face_static(
						verts, uvs, colors, normals, indices, vertex_index,
						pos + Vector3(0.5, -0.5, 0.5),
						pos + Vector3(0.5, 0.5, 0.5),
						pos + Vector3(0.5, 0.5, -0.5),
						pos + Vector3(0.5, -0.5, -0.5),
						Vector3.RIGHT, chunk_color, block_id, 
						BlockDefinitions.Face.POS_X, tile_size, tiles_per_row
					)
					vertex_index += 4
					triangle_count += 2
				
				# -X face
				if _is_air_local(voxels, x - 1, y, z):
					_add_face_static(
						verts, uvs, colors, normals, indices, vertex_index,
						pos + Vector3(-0.5, -0.5, -0.5),
						pos + Vector3(-0.5, 0.5, -0.5),
						pos + Vector3(-0.5, 0.5, 0.5),
						pos + Vector3(-0.5, -0.5, 0.5),
						Vector3.LEFT, chunk_color, block_id,
						BlockDefinitions.Face.NEG_X, tile_size, tiles_per_row
					)
					vertex_index += 4
					triangle_count += 2
				
				# +Y face
				if _is_air_local(voxels, x, y + 1, z):
					_add_face_static(
						verts, uvs, colors, normals, indices, vertex_index,
						pos + Vector3(-0.5, 0.5, 0.5),
						pos + Vector3(-0.5, 0.5, -0.5),
						pos + Vector3(0.5, 0.5, -0.5),
						pos + Vector3(0.5, 0.5, 0.5),
						Vector3.UP, chunk_color, block_id,
						BlockDefinitions.Face.POS_Y, tile_size, tiles_per_row
					)
					vertex_index += 4
					triangle_count += 2
				
				# -Y face
				if _is_air_local(voxels, x, y - 1, z):
					_add_face_static(
						verts, uvs, colors, normals, indices, vertex_index,
						pos + Vector3(-0.5, -0.5, -0.5),
						pos + Vector3(-0.5, -0.5, 0.5),
						pos + Vector3(0.5, -0.5, 0.5),
						pos + Vector3(0.5, -0.5, -0.5),
						Vector3.DOWN, chunk_color, block_id,
						BlockDefinitions.Face.NEG_Y, tile_size, tiles_per_row
					)
					vertex_index += 4
					triangle_count += 2
				
				# +Z face
				if _is_air_local(voxels, x, y, z + 1):
					_add_face_static(
						verts, uvs, colors, normals, indices, vertex_index,
						pos + Vector3(-0.5, -0.5, 0.5),
						pos + Vector3(-0.5, 0.5, 0.5),
						pos + Vector3(0.5, 0.5, 0.5),
						pos + Vector3(0.5, -0.5, 0.5),
						Vector3.BACK, chunk_color, block_id,
						BlockDefinitions.Face.POS_Z, tile_size, tiles_per_row
					)
					vertex_index += 4
					triangle_count += 2
				
				# -Z face
				if _is_air_local(voxels, x, y, z - 1):
					_add_face_static(
						verts, uvs, colors, normals, indices, vertex_index,
						pos + Vector3(0.5, -0.5, -0.5),
						pos + Vector3(0.5, 0.5, -0.5),
						pos + Vector3(-0.5, 0.5, -0.5),
						pos + Vector3(-0.5, -0.5, -0.5),
						Vector3.FORWARD, chunk_color, block_id,
						BlockDefinitions.Face.NEG_Z, tile_size, tiles_per_row
					)
					vertex_index += 4
					triangle_count += 2
	
	return {
		"vertices": verts,
		"uvs": uvs,
		"colors": colors,
		"normals": normals,
		"indices": indices,
		"triangle_count": triangle_count
	}


## Helper: Check if local position is air (thread-safe, no cross-chunk).
static func _is_air_local(voxels: PackedByteArray, x: int, y: int, z: int) -> bool:
	if x < 0 or x >= CHUNK_WIDTH or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_DEPTH:
		return true  # Treat boundary as air for initial mesh
	var idx: int = x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_DEPTH
	return voxels[idx] == 0


## Helper: Add face to arrays (static, thread-safe).
static func _add_face_static(
	verts: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	base_index: int,
	v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
	normal: Vector3,
	chunk_color: Color,
	block_id: int,
	face: int,
	tile_size: float,
	tiles_per_row: int
) -> void:
	# Add vertices
	verts.append(v0)
	verts.append(v1)
	verts.append(v2)
	verts.append(v3)
	
	# Add normals
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	
	# Add colors
	colors.append(chunk_color)
	colors.append(chunk_color)
	colors.append(chunk_color)
	colors.append(chunk_color)
	
	# Calculate UVs from atlas
	var tile_index: int = 0
	if BlockDefinitions.BLOCK_TILES.has(block_id):
		var face_map: Dictionary = BlockDefinitions.BLOCK_TILES[block_id]
		if face_map.has(face):
			tile_index = face_map[face]
	
	var col: int = tile_index % tiles_per_row
	var row: int = tile_index / tiles_per_row
	var base_uv := Vector2(col * tile_size, row * tile_size)
	
	uvs.append(base_uv + Vector2(0, tile_size))
	uvs.append(base_uv + Vector2(0, 0))
	uvs.append(base_uv + Vector2(tile_size, 0))
	uvs.append(base_uv + Vector2(tile_size, tile_size))
	
	# Add indices (two triangles)
	indices.append(base_index + 0)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index + 0)
	indices.append(base_index + 2)
	indices.append(base_index + 3)


# -------------------------------------------------------------------
# Private Methods
# -------------------------------------------------------------------

## Generates the initial world grid.
func _generate_initial_world() -> void:
	for x in range(world_size):
		for z in range(world_size):
			var key := Vector2i(x, z)
			if use_threading:
				_spawn_chunk_threaded(key)
			else:
				_spawn_chunk_sync(key)
	
	# If not using threading, rebuild meshes after all chunks exist
	if not use_threading:
		await get_tree().process_frame
		for key in _chunks.keys():
			_chunks[key].build_mesh()


## Spawns a chunk synchronously (legacy/debug mode).
func _spawn_chunk_sync(key: Vector2i) -> Chunk:
	var chunk: Chunk
	
	if chunk_scene:
		chunk = chunk_scene.instantiate() as Chunk
	else:
		chunk = Chunk.new()
	
	add_child(chunk)
	
	chunk.key = key
	chunk.chunk_offset = Vector3(key.x * CHUNK_WIDTH, 0, key.y * CHUNK_DEPTH)
	chunk.chunk_manager = self
	
	chunk.mesh_updated.connect(_on_chunk_mesh_updated)
	chunk.border_update_requested.connect(_on_border_update_requested)
	
	chunk.init_data(_noise, max_height)
	
	_chunks[key] = chunk
	chunk_loaded.emit(chunk)
	
	return chunk


## Spawns a chunk using threaded generation.
func _spawn_chunk_threaded(key: Vector2i) -> void:
	if _pending_chunks.has(key) or _chunks.has(key):
		return
	
	_pending_chunks[key] = true
	
	# Create chunk node immediately (on main thread)
	var chunk: Chunk
	if chunk_scene:
		chunk = chunk_scene.instantiate() as Chunk
	else:
		chunk = Chunk.new()
	
	add_child(chunk)
	
	chunk.key = key
	chunk.chunk_offset = Vector3(key.x * CHUNK_WIDTH, 0, key.y * CHUNK_DEPTH)
	chunk.chunk_manager = self
	
	chunk.mesh_updated.connect(_on_chunk_mesh_updated)
	chunk.border_update_requested.connect(_on_border_update_requested)
	
	_chunks[key] = chunk
	
	# Dispatch threaded generation
	var task_data := {
		"key": key,
		"offset": chunk.chunk_offset,
		"color": chunk.chunk_color
	}
	
	WorkerThreadPool.add_task(
		Callable(self, "_generate_chunk_task").bind(task_data)
	)


## Worker thread task: generates data and mesh arrays.
func _generate_chunk_task(task_data: Dictionary) -> void:
	var key: Vector2i = task_data["key"]
	var offset: Vector3 = task_data["offset"]
	var color: Color = task_data["color"]
	
	# Stage 1: Generate voxel data
	var voxels := ChunkManager.generate_voxel_data_threaded(_noise, offset, max_height)
	
	# Stage 2: Generate mesh arrays
	var mesh_data := ChunkManager.generate_mesh_arrays_threaded(voxels, offset, color)
	
	# Stage 3: Apply on main thread
	var result := {
		"key": key,
		"voxels": voxels,
		"mesh_data": mesh_data
	}
	
	call_deferred("_apply_chunk_data", result)


## Main thread: applies generated data to chunk.
func _apply_chunk_data(result: Dictionary) -> void:
	var key: Vector2i = result["key"]
	var voxels: PackedByteArray = result["voxels"]
	var mesh_data: Dictionary = result["mesh_data"]
	
	_pending_chunks.erase(key)
	
	var chunk := get_chunk(key)
	if chunk == null:
		return
	
	# Apply voxel data
	chunk.set_voxels_raw(voxels)
	
	# Apply mesh
	chunk.apply_mesh_arrays(mesh_data)
	
	chunk_loaded.emit(chunk)


## Unloads a chunk at the given coordinate.
func _unload_chunk(key: Vector2i) -> void:
	if not _chunks.has(key):
		return
	
	var chunk: Chunk = _chunks[key]
	
	if _chunk_triangles.has(key):
		triangles_total -= _chunk_triangles[key]
		_chunk_triangles.erase(key)
	
	_chunks.erase(key)
	chunk.queue_free()
	
	chunk_unloaded.emit(key)


## Updates neighbor chunks when a border block changes.
func _update_neighbors_at(world_coords: Vector3i) -> void:
	var global_pos := Vector3(world_coords.x, world_coords.y, world_coords.z)
	var chunk_coord := world_to_chunk_coord(global_pos)
	var local := world_to_local_voxel(global_pos)
	
	if local.x == 0:
		_rebuild_chunk_at(chunk_coord + Vector2i(-1, 0))
	elif local.x == CHUNK_WIDTH - 1:
		_rebuild_chunk_at(chunk_coord + Vector2i(1, 0))
	
	if local.z == 0:
		_rebuild_chunk_at(chunk_coord + Vector2i(0, -1))
	elif local.z == CHUNK_DEPTH - 1:
		_rebuild_chunk_at(chunk_coord + Vector2i(0, 1))


## Rebuilds the mesh for a chunk if it exists.
## Uses threaded path when use_threading is enabled, with deduplication.
func _rebuild_chunk_at(key: Vector2i) -> void:
	var chunk := get_chunk(key)
	if not chunk:
		return
	
	if use_threading:
		# Deduplicate pending rebuilds
		if _pending_rebuilds.has(key):
			return
		_pending_rebuilds[key] = true
		
		var task_data := {
			"key": key,
			"voxels": chunk._voxels.duplicate(),  # Copy for thread safety
			"offset": chunk.chunk_offset,
			"color": chunk.chunk_color
		}
		
		WorkerThreadPool.add_task(
			Callable(self, "_rebuild_chunk_task").bind(task_data)
		)
	else:
		chunk.build_mesh()


## Worker thread task: rebuilds mesh arrays for existing chunk.
func _rebuild_chunk_task(task_data: Dictionary) -> void:
	var key: Vector2i = task_data["key"]
	var voxels: PackedByteArray = task_data["voxels"]
	var offset: Vector3 = task_data["offset"]
	var color: Color = task_data["color"]
	
	# Generate mesh arrays on thread
	var mesh_data := ChunkManager.generate_mesh_arrays_threaded(voxels, offset, color)
	
	var result := {
		"key": key,
		"mesh_data": mesh_data
	}
	
	call_deferred("_apply_rebuild_data", result)


## Main thread: applies rebuilt mesh to chunk.
func _apply_rebuild_data(result: Dictionary) -> void:
	var key: Vector2i = result["key"]
	var mesh_data: Dictionary = result["mesh_data"]
	
	_pending_rebuilds.erase(key)
	
	var chunk := get_chunk(key)
	if chunk == null:
		return
	
	chunk.apply_mesh_arrays(mesh_data)


## Callback when a chunk mesh is updated.
func _on_chunk_mesh_updated(chunk: Chunk, triangle_count: int) -> void:
	var key: Vector2i = chunk.key
	var old_count: int = 0
	
	if _chunk_triangles.has(key):
		old_count = _chunk_triangles[key]
	
	_chunk_triangles[key] = triangle_count
	triangles_total += triangle_count - old_count


## Callback when a chunk requests a border update.
func _on_border_update_requested(neighbor_key: Vector2i) -> void:
	_rebuild_chunk_at(neighbor_key)


## Updates which chunks have collision enabled based on proximity to position.
## Call this from _physics_process or when player moves significantly.
func update_collision_radius(center_pos: Vector3) -> void:
	var center_chunk := world_to_chunk_coord(center_pos)
	
	for key in _chunks.keys():
		var chunk: Chunk = _chunks[key]
		var dist: int = maxi(absi(key.x - center_chunk.x), absi(key.y - center_chunk.y))
		var should_have_collision: bool = dist <= collision_radius
		
		if chunk.is_collision_enabled() != should_have_collision:
			chunk.set_collision_enabled(should_have_collision)
