## ChunkServer
## RefCounted container for chunk data using direct RenderingServer and PhysicsServer3D.
## Replaces Node-based Chunk scenes to eliminate scene tree overhead.
##
## THREADING: All public methods must be called from main thread only.
## RID LIFECYCLE: All RIDs freed in NOTIFICATION_PREDELETE.
class_name ChunkServer
extends RefCounted


# -- Constants --

const WIDTH: int = 32
const HEIGHT: int = 32
const DEPTH: int = 32
const VOLUME: int = WIDTH * HEIGHT * DEPTH  # 32,768 voxels

const AIR_ID: int = 0

## AABB margin to prevent frustum culling edge artifacts.
const AABB_MARGIN: float = 0.1


# -- Public State --

## Grid key for this chunk (x, z coordinates in chunk space).
var key: Vector2i = Vector2i.ZERO

## World-space offset of this chunk's origin (0,0,0 corner).
var chunk_offset: Vector3 = Vector3.ZERO

## Chunk color tint for debugging.
var chunk_color: Color = Color.WHITE

## Collision layer for physics body.
var collision_layer: int = 1

## Collision mask for physics body.
var collision_mask: int = 1


# -- Private State --

## Flat voxel storage: ID at position = voxels[x + z*WIDTH + y*WIDTH*DEPTH]
var _voxels: PackedByteArray

## RenderingServer RIDs
var _mesh_rid: RID
var _mesh_instance_rid: RID

## PhysicsServer3D RIDs
var _body_rid: RID
var _shape_rid: RID
## Keep shape object alive (RID invalidates if object freed)
var _shape: ConcavePolygonShape3D

## Collision state
var _collision_enabled: bool = false

## Flag to prevent double-free when destroy() is called explicitly.
var _destroyed: bool = false

## Triangle count for stats
var _triangle_count: int = 0

## Stored mesh arrays for collision shape creation
## (RenderingServer doesn't provide mesh_get_surface in Godot 4.5)
var _cached_mesh_arrays: Array = []

## Cached RIDs for regeneration
var _scenario: RID
var _material: RID


# -- Lifecycle --

func _init() -> void:
	_voxels.resize(VOLUME)
	_voxels.fill(AIR_ID)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Skip if already cleaned up by explicit destroy()
		if _destroyed:
			return
		
		if OS.get_thread_caller_id() != OS.get_main_thread_id():
			push_error("ChunkServer: FATAL - freed from non-main thread! RIDs leaked.")
			return
		
		_free_rendering_rids()
		_free_physics_rids()


## Explicit destructor to ensure clean RID disposal on main thread.
## Recommended over relying on ref-count PREDELETE for heavy resources.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	_free_rendering_rids()
	_free_physics_rids()


# -- Public API: Voxel Access --

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


# -- Public API: Mesh --

## Applies pre-generated mesh arrays and creates RenderingServer instances.
## @param mesh_data: Dictionary with vertices, uvs, colors, normals, indices, triangle_count
## @param scenario: World3D scenario RID to link mesh instance to
## @param material: Material RID to apply to mesh surface
func apply_mesh(mesh_data: Dictionary, scenario: RID, material: RID) -> void:
	# Cache RIDs for regeneration
	_scenario = scenario
	_material = material
	
	# Free existing mesh RIDs if any
	_free_rendering_rids()
	
	var verts: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var uvs: PackedVector2Array = mesh_data.get("uvs", PackedVector2Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	_triangle_count = mesh_data.get("triangle_count", 0)
	
	if verts.is_empty():
		return
	
	# Create mesh
	_mesh_rid = RenderingServer.mesh_create()
	
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	# Cache for collision shape creation
	_cached_mesh_arrays = arrays
	
	RenderingServer.mesh_add_surface_from_arrays(_mesh_rid, RenderingServer.PRIMITIVE_TRIANGLES, arrays)
	
	if material.is_valid():
		RenderingServer.mesh_surface_set_material(_mesh_rid, 0, material)
	
	# Create mesh instance and link to scenario
	_mesh_instance_rid = RenderingServer.instance_create()
	RenderingServer.instance_set_base(_mesh_instance_rid, _mesh_rid)
	RenderingServer.instance_set_scenario(_mesh_instance_rid, scenario)
	RenderingServer.instance_set_custom_aabb(_mesh_instance_rid, _calculate_aabb())
	RenderingServer.instance_set_transform(_mesh_instance_rid, Transform3D.IDENTITY)
	RenderingServer.instance_set_visible(_mesh_instance_rid, true)


## Returns the triangle count for stats.
func get_triangle_count() -> int:
	return _triangle_count


# -- Public API: Collision --

## Enables or disables collision for this chunk (lazy collision).
## @param enabled: Whether collision should be active
## @param space: World3D physics space RID
func set_collision_enabled(enabled: bool, space: RID) -> void:
	if enabled == _collision_enabled:
		return
	
	if enabled:
		# If mesh data isn't ready, don't enable collision yet (keep flag false)
		# This ensures we retry later when apply_mesh calls logic again
		if _cached_mesh_arrays.is_empty():
			return
		
		_build_collision(space)
		_collision_enabled = true
	else:
		_free_physics_rids()
		_collision_enabled = false


## Returns whether collision is enabled for this chunk.
## Used by ability system for "Void Problem" safety checks.
func is_collision_enabled() -> bool:
	return _collision_enabled


# -- Public API: Gameplay --

## Checks if the block at global coordinates is selected (highlighted).
func check_block_selected(global_coords: Vector3i) -> bool:
	var lx := global_coords.x - int(chunk_offset.x)
	var ly := global_coords.y - int(chunk_offset.y)
	var lz := global_coords.z - int(chunk_offset.z)
	
	var id := get_voxel(lx, ly, lz)
	return id != AIR_ID


## Deletes a block (sets to AIR) and regenerates mesh.
func delete_block(global_coords: Vector3i) -> void:
	var lx := global_coords.x - int(chunk_offset.x)
	var ly := global_coords.y - int(chunk_offset.y)
	var lz := global_coords.z - int(chunk_offset.z)
	
	set_voxel(lx, ly, lz, AIR_ID)
	_update_mesh()


## Adds a block (sets to ID 1) and regenerates mesh.
func add_block(global_coords: Vector3i) -> void:
	var lx := global_coords.x - int(chunk_offset.x)
	var ly := global_coords.y - int(chunk_offset.y)
	var lz := global_coords.z - int(chunk_offset.z)
	
	set_voxel(lx, ly, lz, 1) # Default solid block
	_update_mesh()


## Regenerates mesh using cached RIDs.
func _update_mesh() -> void:
	if not _scenario.is_valid() or not _material.is_valid():
		return
		
	# Synchronous regeneration (fast for single block)
	var mesh_data := ChunkManager.generate_mesh_arrays_threaded(_voxels, chunk_offset, chunk_color)
	apply_mesh(mesh_data, _scenario, _material)
	
	# Collision update if enabled
	if _collision_enabled:
		_build_collision(PhysicsServer3D.body_get_space(_body_rid))


# -- Private: RID Management --

## Calculates custom AABB with margin for frustum culling.
func _calculate_aabb() -> AABB:
	return AABB(
		chunk_offset - Vector3(AABB_MARGIN, AABB_MARGIN, AABB_MARGIN),
		Vector3(WIDTH + AABB_MARGIN * 2, HEIGHT + AABB_MARGIN * 2, DEPTH + AABB_MARGIN * 2)
	)


## Frees all RenderingServer RIDs with validity checks.
func _free_rendering_rids() -> void:
	if _mesh_instance_rid.is_valid():
		RenderingServer.free_rid(_mesh_instance_rid)
		_mesh_instance_rid = RID()
	
	if _mesh_rid.is_valid():
		RenderingServer.free_rid(_mesh_rid)
		_mesh_rid = RID()


## Frees all PhysicsServer3D RIDs with validity checks.
func _free_physics_rids() -> void:
	if _body_rid.is_valid():
		PhysicsServer3D.free_rid(_body_rid)
		_body_rid = RID()
	
	# Shape RID is owned by the RefCounted _shape object
	# We must NOT manually free it, or we get a double-free crash when _shape dies
	_shape_rid = RID()
	_shape = null
	
	_collision_enabled = false


## Frees all RIDs (called from NOTIFICATION_PREDELETE).
func _free_all_rids() -> void:
	_free_rendering_rids()
	_free_physics_rids()


## Builds collision from current mesh.
## @param space: World3D physics space RID
func _build_collision(space: RID) -> void:
	_free_physics_rids()
	
	if _cached_mesh_arrays.is_empty():
		return
	
	# Create trimesh shape from cached mesh arrays
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _cached_mesh_arrays)
	_shape = mesh.create_trimesh_shape()
	
	if _shape == null:
		return
	
	_shape_rid = _shape.get_rid()
	
	# Create static body
	_body_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(_body_rid, space)
	PhysicsServer3D.body_add_shape(_body_rid, _shape_rid)
	PhysicsServer3D.body_set_state(
		_body_rid, 
		PhysicsServer3D.BODY_STATE_TRANSFORM,
		# Use IDENTITY because mesh vertices already have world offset baked in
		# (see generate_mesh_arrays_threaded: pos := Vector3(x,y,z) + offset)
		Transform3D.IDENTITY
	)
	
	# Configure collision layers
	PhysicsServer3D.body_set_collision_layer(_body_rid, collision_layer)
	PhysicsServer3D.body_set_collision_mask(_body_rid, collision_mask)
	
	# Force update to prevent "fall-through" on creation frame
	# PhysicsServer3D.flush_queries() # Removed: Not available in Godot 4 API
	
	_collision_enabled = true
	
	# Note: PhysicsServer3D doesn't have body_set_user_data in Godot 4.5
	# GrappleAbility will look up chunks via ChunkManager.get_chunk_at_world_pos() instead


# -- Private: Indexing --

## Converts 3D coordinates to flat array index.
func _index(x: int, y: int, z: int) -> int:
	return x + z * WIDTH + y * WIDTH * DEPTH
