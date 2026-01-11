## Chunk
## Represents a single unit of voxel terrain.
## Stores raw voxel data in a flat PackedByteArray and handles mesh rendering.
class_name Chunk
extends Node3D

# Explicit preload for static method access
const MeshBuilder := preload("res://scripts/chunk/mesh_builder.gd")

# -- Signals --

signal mesh_updated(chunk: Chunk, triangle_count: int)
signal border_update_requested(neighbor_key: Vector2i)


# -- Constants --

const WIDTH: int = 32
const HEIGHT: int = 32
const DEPTH: int = 32
const VOLUME: int = WIDTH * HEIGHT * DEPTH  # 32,768 voxels

const AIR_ID: int = 0


# -- Exports --

## Reference to the ChunkManager that owns this chunk.
@export var chunk_manager: Node

## Grid key for this chunk (x, z coordinates in chunk space).
@export var key: Vector2i = Vector2i.ZERO


# -- Public Variables --

## World-space offset of this chunk's origin (0,0,0 corner).
var chunk_offset: Vector3 = Vector3.ZERO

## Chunk color tint for debugging.
var chunk_color: Color = Color.WHITE

# -- Private Variables --

## Flat voxel storage: ID at position = voxels[x + z*WIDTH + y*WIDTH*DEPTH]
var _voxels: PackedByteArray

var _mesh_instance: MeshInstance3D  ## Mesh arrays for ArrayMesh generation
var _collision_body: StaticBody3D
var _triangle_count: int = 0        ## Triangle count for stats

## Atlas configuration.
var _tiles_per_row: int = 2
var _tile_size: float = 1.0 / 2.0

## Lazy collision: only generates collision when enabled (for chunks near player).
var _collision_enabled: bool = false

## Debounce flag: batches multiple voxel changes into single mesh rebuild.
var _mesh_dirty: bool = false


# -- Lifecycle --

func _ready() -> void:
	_voxels.resize(VOLUME)
	_voxels.fill(AIR_ID)
	
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	
	# Apply material from scene or create default
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	
	var texture := load("res://assets/test.png") as Texture2D
	if texture:
		material.albedo_texture = texture
	
	_mesh_instance.material_override = material


# -- Public API --

## Returns the block ID at local coordinates.
func get_voxel(x: int, y: int, z: int) -> int:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT or z < 0 or z >= DEPTH:
		return AIR_ID
	return _voxels[_index(x, y, z)]


## Sets the block ID at local coordinates.
func set_voxel(x: int, y: int, z: int, block_id: int) -> void:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT or z < 0 or z >= DEPTH:
		return
	_voxels[_index(x, y, z)] = block_id


## Sets raw voxel data from threaded generation.
func set_voxels_raw(voxels: PackedByteArray) -> void:
	if voxels.size() == VOLUME:
		_voxels = voxels


## Returns raw voxel data for serialization (thread-safe copy).
func get_voxels_raw() -> PackedByteArray:
	return _voxels.duplicate()


## Applies pre-generated mesh arrays from threaded generation.
func apply_mesh_arrays(mesh_data: Dictionary) -> void:
	var verts: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var uvs: PackedVector2Array = mesh_data.get("uvs", PackedVector2Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	_triangle_count = mesh_data.get("triangle_count", 0)
	
	if verts.size() > 0:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh_instance.mesh = array_mesh
		
		_build_collision()
	else:
		_mesh_instance.mesh = null
		_clear_collision()
	
	mesh_updated.emit(self, _triangle_count)


## Builds the mesh from current voxel data using MeshBuilder.
func build_mesh() -> void:
	var result := MeshBuilder.build_from_voxels(
		_voxels,
		chunk_offset,
		chunk_color,
		_is_transparent,
		WIDTH, HEIGHT, DEPTH,
		_tiles_per_row
	)
	
	var arrays: Dictionary = result["arrays"]
	_triangle_count = result["triangle_count"]
	
	# Commit mesh
	if arrays.verts.size() > 0:
		var mesh_arrays: Array = []
		mesh_arrays.resize(Mesh.ARRAY_MAX)
		mesh_arrays[Mesh.ARRAY_VERTEX] = arrays.verts
		mesh_arrays[Mesh.ARRAY_TEX_UV] = arrays.uvs
		mesh_arrays[Mesh.ARRAY_COLOR] = arrays.colors
		mesh_arrays[Mesh.ARRAY_NORMAL] = arrays.normals
		mesh_arrays[Mesh.ARRAY_INDEX] = arrays.indices
		
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
		_mesh_instance.mesh = array_mesh
		
		_build_collision()
	else:
		_mesh_instance.mesh = null
		_clear_collision()
	
	mesh_updated.emit(self, _triangle_count)


## Checks if a block exists at the given world coordinates.
func check_block_selected(world_coords: Vector3i) -> bool:
	var local := _world_to_local(world_coords)
	return get_voxel(local.x, local.y, local.z) != AIR_ID


## Deletes a block at world coordinates.
func delete_block(world_coords: Vector3i) -> void:
	var local := _world_to_local(world_coords)
	
	if not _is_local_valid(local):
		if chunk_manager and chunk_manager.has_method("delete_block_world"):
			chunk_manager.delete_block_world(world_coords)
		return
	
	set_voxel(local.x, local.y, local.z, AIR_ID)
	mark_dirty()
	_check_border(local)


## Adds a block at world coordinates.
func add_block(world_coords: Vector3i, block_id: int = BlockDefinitions.BlockType.DIRT) -> void:
	var local := _world_to_local(world_coords)
	
	if not _is_local_valid(local):
		if chunk_manager and chunk_manager.has_method("add_block_world"):
			chunk_manager.add_block_world(world_coords)
		return
	
	set_voxel(local.x, local.y, local.z, block_id)
	mark_dirty()
	_check_border(local)


## Marks the chunk mesh as needing rebuild. Uses debounce to batch updates.
func mark_dirty() -> void:
	if _mesh_dirty:
		return
	_mesh_dirty = true
	call_deferred("_flush_rebuild")


## Flushes pending mesh rebuild (called deferred).
## Delegates to ChunkManager for threaded execution when available.
func _flush_rebuild() -> void:
	if not _mesh_dirty:
		return
	_mesh_dirty = false
	
	# Use ChunkManager's threaded rebuild if available
	if chunk_manager and chunk_manager.has_method("_rebuild_chunk_at"):
		DebugLogger.debug("Chunk %s: Using THREADED rebuild" % key, "Chunk")
		chunk_manager._rebuild_chunk_at(key)
	else:
		DebugLogger.debug("Chunk %s: Using SYNC rebuild (slow!)" % key, "Chunk")
		build_mesh()


## Enables or disables collision for this chunk (lazy collision).
## Uses call_deferred to prevent multiple collision builds stacking on same frame.
func set_collision_enabled(enabled: bool) -> void:
	if enabled == _collision_enabled:
		return
	_collision_enabled = enabled
	if enabled and _mesh_instance.mesh:
		# DEFERRED: Prevents hitches when multiple chunks enable collision simultaneously
		call_deferred("_build_collision")
	elif not enabled:
		_clear_collision()


## Returns whether collision is enabled for this chunk.
func is_collision_enabled() -> bool:
	return _collision_enabled


## Legacy compatibility: checks if local position is air.
func is_air(ix: int, iy: int, iz: int) -> bool:
	if ix >= 0 and ix < WIDTH and iy >= 0 and iy < HEIGHT and iz >= 0 and iz < DEPTH:
		return get_voxel(ix, iy, iz) == AIR_ID
	
	# Outside chunk bounds - ask chunk manager
	var wx: int = int(ix + chunk_offset.x)
	var wy: int = int(iy + chunk_offset.y)
	var wz: int = int(iz + chunk_offset.z)
	
	if chunk_manager and chunk_manager.has_method("is_air_world"):
		return chunk_manager.is_air_world(wx, wy, wz)
	
	return true


## Returns triangle count for stats.
func get_triangle_count() -> int:
	return _triangle_count


# -- Private Helpers --

## Converts 3D coordinates to flat array index.
func _index(x: int, y: int, z: int) -> int:
	return x + z * WIDTH + y * WIDTH * DEPTH


## Checks if a neighbor position is transparent (should render face).
func _is_transparent(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT or z < 0 or z >= DEPTH:
		# Check with chunk manager for cross-chunk boundaries
		var wx: int = int(x + chunk_offset.x)
		var wy: int = int(y + chunk_offset.y)
		var wz: int = int(z + chunk_offset.z)
		
		if chunk_manager and chunk_manager.has_method("is_air_world"):
			return chunk_manager.is_air_world(wx, wy, wz)
		return true
	
	return get_voxel(x, y, z) == AIR_ID


## Converts world coordinates to local chunk coordinates.
func _world_to_local(world_coords: Vector3i) -> Vector3i:
	return Vector3i(
		world_coords.x - int(chunk_offset.x),
		world_coords.y - int(chunk_offset.y),
		world_coords.z - int(chunk_offset.z)
	)


## Checks if local coordinates are within chunk bounds.
func _is_local_valid(local: Vector3i) -> bool:
	return local.x >= 0 and local.x < WIDTH \
		and local.y >= 0 and local.y < HEIGHT \
		and local.z >= 0 and local.z < DEPTH


## Emits border update signals for neighbor chunks.
func _check_border(local: Vector3i) -> void:
	if local.x == 0:
		border_update_requested.emit(key + Vector2i(-1, 0))
	elif local.x == WIDTH - 1:
		border_update_requested.emit(key + Vector2i(1, 0))
	
	if local.z == 0:
		border_update_requested.emit(key + Vector2i(0, -1))
	elif local.z == DEPTH - 1:
		border_update_requested.emit(key + Vector2i(0, 1))


## Builds collision shape from mesh (only if collision is enabled).
func _build_collision() -> void:
	_clear_collision()
	
	if not _collision_enabled:
		DebugLogger.debug("Chunk %s: Collision SKIPPED (disabled)" % key, "Chunk")
		return
	
	if _mesh_instance.mesh == null:
		return
	
	var start := Time.get_ticks_msec()
	
	_collision_body = StaticBody3D.new()
	var shape := _mesh_instance.mesh.create_trimesh_shape()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	
	_collision_body.add_child(collision_shape)
	add_child(_collision_body)
	
	var elapsed := Time.get_ticks_msec() - start
	DebugLogger.debug("Chunk %s: Collision BUILT in %dms (triangles: %d)" % [key, elapsed, _triangle_count], "Chunk")


## Removes collision shape.
func _clear_collision() -> void:
	if _collision_body:
		_collision_body.queue_free()
		_collision_body = null
