## ChunkManager
## Orchestrates infinite voxel terrain by managing chunk lifecycle.
## Uses Dictionary storage for sparse, infinite-coordinate support.
## Threading: Data and mesh generation run on WorkerThreadPool.
class_name ChunkManager
extends Node

# Explicit preloads for static method access
const MeshBuilderClass := preload("res://scripts/chunk/mesh_builder.gd")
const CoordinateMathClass := preload("res://scripts/chunk/coordinate_math.gd")
const VisibilityManagerClass := preload("res://scripts/chunk/visibility_manager.gd")
const ChunkLoaderClass := preload("res://scripts/chunk/chunk_loader.gd")
const VoxelDataGeneratorClass := preload("res://scripts/chunk/voxel_data_generator.gd")


# -------------------------------------------------------------------
# Signals
# -------------------------------------------------------------------

signal chunk_loaded(chunk: ChunkServer)
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

@export_group("Infinite Scrolling")
## Path to player node for position tracking.
@export var player_path: NodePath
## Resolved player reference (set in _ready).
var player: Node3D
## Radius of chunks to keep loaded around player.
@export var view_distance: int = 8
## Extra chunks beyond view_distance before unloading (hysteresis).
@export var unload_buffer: int = 2
## How often to check for chunk updates (seconds).
@export var tick_rate: float = 0.5
## Maximum concurrent chunk generation tasks (lower = less frame stutter).
@export var max_concurrent_loads: int = 8

@export_group("Memory Management")
## Maximum chunks to keep loaded (prevents memory exhaustion).
@export var max_loaded_chunks: int = 400

@export_group("Origin Shifting")
## Enable automatic origin shifting for long play sessions.
@export var enable_origin_shifting: bool = true
## Distance from origin before shifting world back.
@export var origin_shift_threshold: float = 5000.0


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

## Active chunks dictionary: Vector2i -> ChunkServer
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

# --- Player Tracking State ---
## Last chunk coordinate where player was (for change detection).
var _last_player_chunk: Vector2i = Vector2i(999999, 999999)
## Heartbeat timer for periodic chunk updates.
var _update_timer: Timer

# --- Spiral Loading (pre-computed for priority) ---
## Offsets sorted by distance for closest-first loading.
var _load_priority_offsets: Array[Vector2i] = []

# --- Edge Remesh Queue (neighbor-triggered) ---
## Chunks needing border remesh after neighbor loaded.
var _edge_remesh_queue: Array[Vector2i] = []

# --- Thread-Local Noise Parameters ---
## Cached noise seed for thread-local copies.
var _noise_seed: int
## Cached noise frequency for thread-local copies.
var _noise_frequency: float

# --- Origin Shifting ---
## Cumulative world origin offset for coordinate tracking.
var _world_origin_offset: Vector3 = Vector3.ZERO

# --- Time-Budgeted Mesh Apply ---
## Queue of pending chunk data to apply (prevents frame stutter).
var _pending_applies: Array[Dictionary] = []
## Maximum milliseconds to spend applying meshes per frame.
const APPLY_BUDGET_MS: float = 2.0

# --- ChunkServer RID Caches ---
## World3D scenario RID for RenderingServer.
var _scenario_rid: RID
## World3D physics space RID for PhysicsServer3D.
var _space_rid: RID
## Shared material RID for all chunk meshes.
var _chunk_material_rid: RID
## Keep material object alive (RID invalidates if object freed)
var _chunk_material: StandardMaterial3D

## Flag to defer RID initialization to first process frame
var _rids_initialized: bool = false


# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _ready() -> void:
	_chunks_mutex = Mutex.new()
	
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.seed = VoxelConstants.DEFAULT_NOISE_SEED
	_noise.frequency = noise_scale
	
	# Cache noise parameters for thread-local copies
	_noise_seed = _noise.seed
	_noise_frequency = _noise.frequency
	
	# Pre-compute spiral offsets (closest chunks first)
	_precompute_spiral_offsets()
	
	# Initialize ChunkServer RID caches (deferred to first process if viewport not ready)
	_init_chunk_server_rids()
	
	# Resolve player path to node reference
	if player_path:
		player = get_node_or_null(player_path) as Node3D
	
	# Initialize heartbeat timer for player tracking
	if player:
		_update_timer = Timer.new()
		_update_timer.wait_time = tick_rate
		_update_timer.autostart = true
		_update_timer.one_shot = false
		_update_timer.timeout.connect(_on_heartbeat)
		add_child(_update_timer)
		DebugLogger.debug("Player tracking enabled (view_distance=%d)" % view_distance, "ChunkManager")
	else:
		# Legacy mode: generate static world if no player assigned
		push_warning("ChunkManager: No player assigned, using legacy static generation")
		_generate_initial_world()


func _exit_tree() -> void:
	# Free material RID to prevent VRAM leak
	if _chunk_material_rid.is_valid():
		RenderingServer.free_rid(_chunk_material_rid)
		_chunk_material_rid = RID()


## Initializes RID caches for ChunkServer rendering/physics.
func _init_chunk_server_rids() -> void:
	# Cache World3D RIDs for ChunkServer (get from viewport since ChunkManager is Node, not Node3D)
	var viewport := get_viewport()
	if viewport:
		var world_3d := viewport.find_world_3d()
		if world_3d:
			_scenario_rid = world_3d.scenario
			_space_rid = world_3d.space
			_rids_initialized = true
		else:
			push_warning("ChunkManager: World3D not available, will retry")
			return
	else:
		push_warning("ChunkManager: Viewport not available, will retry")
		return
	
	# Create shared material for all chunk meshes
	_chunk_material = StandardMaterial3D.new()
	_chunk_material.vertex_color_use_as_albedo = true
	_chunk_material.vertex_color_is_srgb = true
	_chunk_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	
	var texture := load("res://assets/test.png") as Texture2D
	if texture:
		_chunk_material.albedo_texture = texture
	
	_chunk_material_rid = _chunk_material.get_rid()


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Returns the chunk at the given world position, or null if not loaded.
func get_chunk_at_world_pos(global_pos: Vector3) -> ChunkServer:
	var key := world_to_chunk_coord(global_pos)
	return get_chunk(key)


## Returns the chunk at the given chunk coordinate, or null if not loaded.
func get_chunk(coord: Vector2i) -> ChunkServer:
	return _chunks.get(coord, null)


## Sets a voxel at a global world position.
func set_voxel(global_pos: Vector3, block_id: int) -> void:
	var chunk_coord := world_to_chunk_coord(global_pos)
	var local := world_to_local_voxel(global_pos)
	
	var chunk := get_chunk(chunk_coord)
	if chunk:
		chunk.set_voxel(local.x, local.y, local.z, block_id)
		# Trigger mesh rebuild for ChunkServer
		_rebuild_chunk_at(chunk_coord)


## Converts world position to chunk coordinate.
func world_to_chunk_coord(global_pos: Vector3) -> Vector2i:
	return CoordinateMathClass.world_to_chunk_coord(global_pos)


## Converts world position to local voxel coordinate within a chunk.
func world_to_local_voxel(global_pos: Vector3) -> Vector3i:
	return CoordinateMathClass.world_to_local_voxel(global_pos)


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


# NOTE: Voxel and mesh generation moved to VoxelDataGenerator utility class.
# Use VoxelDataGenerator.generate_voxel_data() and VoxelDataGenerator.generate_mesh_arrays()
# for thread-safe generation operations.


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
			var chunk: ChunkServer = _chunks[key]
			var voxels := chunk.get_voxels_raw()
			var mesh_data := VoxelDataGeneratorClass.generate_mesh_arrays(voxels, chunk.chunk_offset, chunk.chunk_color)
			chunk.apply_mesh(mesh_data, _scenario_rid, _chunk_material_rid)


## Spawns a chunk synchronously (legacy/debug mode).
func _spawn_chunk_sync(key: Vector2i) -> ChunkServer:
	var chunk := ChunkServer.new()
	chunk.key = key
	chunk.chunk_offset = Vector3(key.x * CHUNK_WIDTH, 0, key.y * CHUNK_DEPTH)
	
	# Generate voxel data synchronously
	var voxels := VoxelDataGeneratorClass.generate_voxel_data(_noise, chunk.chunk_offset, max_height)
	chunk.set_voxels_raw(voxels)
	
	_chunks[key] = chunk
	chunk_loaded.emit(chunk)
	
	return chunk


## Spawns a chunk using threaded generation.
func _spawn_chunk_threaded(key: Vector2i) -> void:
	if _pending_chunks.has(key) or _chunks.has(key):
		return
	
	_pending_chunks[key] = true
	
	# Create ChunkServer immediately (on main thread)
	var chunk := ChunkServer.new()
	chunk.key = key
	chunk.chunk_offset = Vector3(key.x * CHUNK_WIDTH, 0, key.y * CHUNK_DEPTH)
	
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
	
	# Stage 1: Generate voxel data (using thread-local noise for safety)
	var thread_noise := _create_thread_local_noise()
	var voxels := VoxelDataGeneratorClass.generate_voxel_data(thread_noise, offset, max_height)
	
	# Stage 2: Generate mesh arrays
	var mesh_data := VoxelDataGeneratorClass.generate_mesh_arrays(voxels, offset, color)
	
	# Stage 3: Apply on main thread
	var result := {
		"key": key,
		"voxels": voxels,
		"mesh_data": mesh_data
	}
	
	call_deferred("_queue_chunk_apply", result)


## Queues chunk data for time-budgeted application (prevents frame stutter).
func _queue_chunk_apply(result: Dictionary) -> void:
	_pending_applies.append(result)


## Called every frame to process pending chunk applies within time budget.
func _process(_delta: float) -> void:
	_process_pending_applies()


## Processes pending chunk applies within time budget.
func _process_pending_applies() -> void:
	if _pending_applies.is_empty():
		return
	
	var start_us := Time.get_ticks_usec()
	var budget_us := APPLY_BUDGET_MS * 1000.0
	
	while not _pending_applies.is_empty():
		if Time.get_ticks_usec() - start_us > budget_us:
			break  # Budget exhausted, continue next frame
		
		var result: Dictionary = _pending_applies.pop_front()
		_do_apply_chunk_data(result)


## Actually applies chunk data (called from time-budgeted queue).
func _do_apply_chunk_data(result: Dictionary) -> void:
	# Guard: Defer if RIDs not yet initialized (prevents material null errors)
	if not _chunk_material_rid.is_valid():
		_pending_applies.push_back(result)
		return
	
	var key: Vector2i = result["key"]
	var voxels: PackedByteArray = result["voxels"]
	var mesh_data: Dictionary = result["mesh_data"]
	
	_pending_chunks.erase(key)
	
	var chunk := get_chunk(key)
	if chunk == null:
		return
	
	# Apply voxel data
	chunk.set_voxels_raw(voxels)
	
	# Apply mesh using ChunkServer RID-based approach
	chunk.apply_mesh(mesh_data, _scenario_rid, _chunk_material_rid)
	
	# Track triangle count
	var tri_count: int = mesh_data.get("triangle_count", 0)
	var old_count: int = _chunk_triangles.get(key, 0)
	_chunk_triangles[key] = tri_count
	triangles_total += tri_count - old_count
	
	# CRITICAL: Force-enable collision for chunks near player immediately after mesh apply
	# This fixes the race condition where player spawns before collision is enabled
	if player and _space_rid.is_valid():
		var player_chunk := world_to_chunk_coord(player.global_position)
		var dist := maxi(absi(key.x - player_chunk.x), absi(key.y - player_chunk.y))
		if dist <= collision_radius:
			chunk.set_collision_enabled(true, _space_rid)
	
	# Queue neighbor edge remeshes (fix void edge seams)
	_queue_neighbor_edge_remesh(key)
	
	chunk_loaded.emit(chunk)


## Unloads a chunk at the given coordinate.
func _unload_chunk(key: Vector2i) -> void:
	if not _chunks.has(key):
		return
	
	var chunk: ChunkServer = _chunks[key]
	
	if _chunk_triangles.has(key):
		triangles_total -= _chunk_triangles[key]
		_chunk_triangles.erase(key)
	
	_chunks.erase(key)
	
	# Explicitly destroy the ChunkServer to ensure main-thread RID cleanup
	# This avoids relying on NOTIFICATION_PREDELETE which can be flaky with RefCounted
	chunk.destroy()
	
	# ChunkServer is RefCounted - freed automatically when refcount hits 0
	# RIDs cleaned up in NOTIFICATION_PREDELETE
	
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
			"voxels": chunk.get_voxels_raw(),  # Thread-safe copy
			"offset": chunk.chunk_offset,
			"color": chunk.chunk_color
		}
		
		WorkerThreadPool.add_task(
			Callable(self, "_rebuild_chunk_task").bind(task_data)
		)
	else:
		# Sync rebuild - regenerate mesh on main thread
		var voxels := chunk.get_voxels_raw()
		var mesh_data := VoxelDataGeneratorClass.generate_mesh_arrays(voxels, chunk.chunk_offset, chunk.chunk_color)
		chunk.apply_mesh(mesh_data, _scenario_rid, _chunk_material_rid)


## Worker thread task: rebuilds mesh arrays for existing chunk.
func _rebuild_chunk_task(task_data: Dictionary) -> void:
	var key: Vector2i = task_data["key"]
	var voxels: PackedByteArray = task_data["voxels"]
	var offset: Vector3 = task_data["offset"]
	var color: Color = task_data["color"]
	
	# Generate mesh arrays on thread
	var mesh_data := VoxelDataGeneratorClass.generate_mesh_arrays(voxels, offset, color)
	
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
	
	chunk.apply_mesh(mesh_data, _scenario_rid, _chunk_material_rid)
	
	# Update triangle count
	var tri_count: int = mesh_data.get("triangle_count", 0)
	var old_count: int = _chunk_triangles.get(key, 0)
	_chunk_triangles[key] = tri_count
	triangles_total += tri_count - old_count


## Callback when a chunk mesh is updated (legacy - kept for compatibility).
func _on_chunk_mesh_updated(_chunk: ChunkServer, _triangle_count: int) -> void:
	# No longer used - triangle tracking handled in _do_apply_chunk_data
	pass


## Callback when a chunk requests a border update.
func _on_border_update_requested(neighbor_key: Vector2i) -> void:
	_rebuild_chunk_at(neighbor_key)


## Updates which chunks have collision enabled based on proximity to position.
## Call this from _physics_process or when player moves significantly.
func update_collision_radius(center_pos: Vector3) -> void:
	var center_chunk := world_to_chunk_coord(center_pos)
	
	for key in _chunks:  # Direct iteration (no .keys() allocation)
		var chunk: ChunkServer = _chunks[key]
		var dist: int = maxi(absi(key.x - center_chunk.x), absi(key.y - center_chunk.y))
		var should_have_collision: bool = dist <= collision_radius
		
		if chunk.is_collision_enabled() != should_have_collision:
			chunk.set_collision_enabled(should_have_collision, _space_rid)


# -------------------------------------------------------------------
# Player Tracking Loop
# -------------------------------------------------------------------

## Pre-computes spiral offsets sorted by distance (closest first).
func _precompute_spiral_offsets() -> void:
	_load_priority_offsets = VisibilityManagerClass.compute_spiral_offsets(view_distance)
	DebugLogger.debug("Pre-computed %d spiral offsets" % _load_priority_offsets.size(), "ChunkManager")


## Heartbeat callback: checks player position and updates chunks.
func _on_heartbeat() -> void:
	if not is_instance_valid(player):
		return
	
	var center_chunk := world_to_chunk_coord(player.global_position)
	
	# Only full update if player moved to new chunk
	if center_chunk != _last_player_chunk:
		_last_player_chunk = center_chunk
		_update_chunk_visibility(center_chunk)
		update_collision_radius(player.global_position)
	
	# Always process edge remesh queue
	_process_edge_remesh_queue()
	
	# Check origin shifting
	if enable_origin_shifting:
		_check_origin_shift()


## Main visibility update: loads nearby chunks, unloads distant ones.
func _update_chunk_visibility(center: Vector2i) -> void:
	var unload_sq: int = (view_distance + unload_buffer) * (view_distance + unload_buffer)
	
	# --- LOAD LOOP (spiral priority) ---
	for offset in _load_priority_offsets:
		var coord := center + offset
		
		if _chunks.has(coord) or _pending_chunks.has(coord):
			continue
		
		# Memory cap check
		if _chunks.size() >= max_loaded_chunks:
			_force_unload_farthest(center)
		
		# Concurrent load limit
		if _pending_chunks.size() >= max_concurrent_loads:
			break  # Try again next heartbeat
		
		_spawn_chunk_threaded_or_load(coord)
	
	# --- UNLOAD LOOP (direct iteration, no .keys() allocation) ---
	var to_unload: Array[Vector2i] = []
	for coord in _chunks:
		var dist: float = Vector2(coord.x - center.x, coord.y - center.y).length_squared()
		if dist > unload_sq:
			to_unload.append(coord)
	
	for coord in to_unload:
		_save_and_unload(coord)


## Spawns a chunk, checking serializer first for saved data.
func _spawn_chunk_threaded_or_load(key: Vector2i) -> void:
	if _pending_chunks.has(key) or _chunks.has(key):
		return
	
	_pending_chunks[key] = true
	
	# Create ChunkServer immediately (on main thread)
	var chunk := ChunkServer.new()
	chunk.key = key
	chunk.chunk_offset = Vector3(key.x * CHUNK_WIDTH, 0, key.y * CHUNK_DEPTH)
	
	_chunks[key] = chunk
	
	# Check if saved chunk exists
	if ChunkSerializer.chunk_exists(key):
		# Load from disk on worker thread
		WorkerThreadPool.add_task(
			Callable(self, "_load_chunk_task").bind(key)
		)
	else:
		# Generate new chunk
		var task_data := {
			"key": key,
			"offset": chunk.chunk_offset,
			"color": chunk.chunk_color
		}
		WorkerThreadPool.add_task(
			Callable(self, "_generate_chunk_task").bind(task_data)
		)


## Worker thread task: loads saved chunk data and generates mesh.
func _load_chunk_task(key: Vector2i) -> void:
	# Load voxels from disk
	var voxels := ChunkSerializer.load_chunk(key)
	
	DebugLogger.debug("Loading chunk %s from disk (size=%d)" % [key, voxels.size()], "ChunkManager")
	
	# Get chunk reference (needed for fallback and mesh gen)
	var chunk := get_chunk(key)
	if chunk == null:
		call_deferred("_pending_chunks_erase", key)
		return
	
	if voxels.is_empty() or voxels.size() != CHUNK_VOLUME:
		if not voxels.is_empty():
			DebugLogger.debug("Data correction - Invalid voxel size (%d) for chunk %s. Regenerating." % [voxels.size(), key], "ChunkManager")
		
		# Fallback to generation if load fails or data invalid
		var offset := chunk.chunk_offset
		var thread_noise := _create_thread_local_noise()
		voxels = VoxelDataGeneratorClass.generate_voxel_data(thread_noise, offset, max_height)
	
	# Generate mesh arrays
	var mesh_data := VoxelDataGeneratorClass.generate_mesh_arrays(voxels, chunk.chunk_offset, chunk.chunk_color)
	
	# Self-healing: If loaded chunk has 0 triangles (likely corrupted from previous bug), regenerate
	if mesh_data["triangle_count"] == 0:
		DebugLogger.debug("Data correction - Regenerating empty chunk %s" % key, "ChunkManager")
		var offset := chunk.chunk_offset
		var thread_noise := _create_thread_local_noise()
		voxels = VoxelDataGeneratorClass.generate_voxel_data(thread_noise, offset, max_height)
		mesh_data = VoxelDataGeneratorClass.generate_mesh_arrays(voxels, offset, chunk.chunk_color)
	
	var result := {
		"key": key,
		"voxels": voxels,
		"mesh_data": mesh_data
	}
	
	call_deferred("_queue_chunk_apply", result)


## Helper to erase from pending on main thread.
func _pending_chunks_erase(key: Vector2i) -> void:
	_pending_chunks.erase(key)


## Saves chunk to disk and unloads it.
func _save_and_unload(key: Vector2i) -> void:
	if not _chunks.has(key):
		return
	
	var chunk: ChunkServer = _chunks[key]
	var voxels := chunk.get_voxels_raw()
	
	# Save on worker thread to prevent stutter
	WorkerThreadPool.add_task(
		func() -> void:
			ChunkSerializer.save_voxels(key, voxels)
	)
	
	_unload_chunk(key)


## Queues neighboring chunks for edge remesh when a chunk loads.
func _queue_neighbor_edge_remesh(loaded_key: Vector2i) -> void:
	# When a chunk loads, its 4 cardinal neighbors may have void edges
	# that now have real data available. Queue them for remesh.
	var neighbors := [
		loaded_key + Vector2i(-1, 0),
		loaded_key + Vector2i(1, 0),
		loaded_key + Vector2i(0, -1),
		loaded_key + Vector2i(0, 1),
	]
	
	for neighbor_key in neighbors:
		if _chunks.has(neighbor_key) and neighbor_key not in _edge_remesh_queue:
			_edge_remesh_queue.append(neighbor_key)


## Processes pending edge remeshes (batched per heartbeat).
func _process_edge_remesh_queue() -> void:
	# Process up to 4 edge remeshes per heartbeat to avoid stutter
	const MAX_REMESH_PER_TICK: int = 4
	var processed: int = 0
	
	while not _edge_remesh_queue.is_empty() and processed < MAX_REMESH_PER_TICK:
		var key: Vector2i = _edge_remesh_queue.pop_front()
		if _chunks.has(key):
			_rebuild_chunk_at(key)
			processed += 1


## Forces unload of farthest chunk when memory cap hit.
func _force_unload_farthest(center: Vector2i) -> void:
	if _chunks.is_empty():
		return
	
	var farthest_key: Vector2i
	var farthest_dist: float = -1.0
	
	for coord in _chunks:
		var dist: float = Vector2(coord.x - center.x, coord.y - center.y).length_squared()
		if dist > farthest_dist:
			farthest_dist = dist
			farthest_key = coord
	
	if farthest_dist > 0:
		_save_and_unload(farthest_key)
		push_warning("ChunkManager: Force unloaded chunk %s (memory cap)" % farthest_key)


## Checks if origin shift is needed and performs it.
func _check_origin_shift() -> void:
	if not is_instance_valid(player):
		return
	
	var player_pos := player.global_position
	if player_pos.length() < origin_shift_threshold:
		return
	
	# Calculate shift to bring player back near origin
	var shift := -player_pos
	shift.y = 0  # Keep Y stable for physics
	
	# Shift all chunks
	for chunk in _chunks.values():
		chunk.global_position += shift
		chunk.chunk_offset += shift
	
	# Shift player
	player.global_position += shift
	
	# Track cumulative offset for world coordinates
	_world_origin_offset -= shift
	
	DebugLogger.debug("Origin shifted by %s (total offset: %s)" % [shift, _world_origin_offset], "ChunkManager")


## Creates a thread-local FastNoiseLite with same parameters.
func _create_thread_local_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = _noise_seed
	noise.frequency = _noise_frequency
	return noise
