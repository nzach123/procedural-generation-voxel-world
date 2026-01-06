## GrappleAbility
## Player ability for grappling hook traversal.
## Uses cached PhysicsRayQueryParameters3D to avoid per-frame allocations.
## Implements "Void Problem" safety by checking chunk physics readiness.
class_name GrappleAbility
extends PlayerAbility


# -------------------------------------------------------------------
# Signals
# -------------------------------------------------------------------

## Emitted when grapple attaches to a surface.
signal grapple_attached(point: Vector3)

## Emitted when grapple detaches (completed or cancelled).
signal grapple_detached


# -------------------------------------------------------------------
# Exports
# -------------------------------------------------------------------

## Maximum grapple range in meters.
@export var max_range: float = 50.0

## Pull speed when attached (m/s).
@export var pull_speed: float = 15.0

## Minimum distance from target to auto-release.
@export var release_distance: float = 2.0

## Input action to fire/release grapple.
@export var input_grapple: String = "grapple"

## Collision mask for grapple raycast.
@export_flags_3d_physics var collision_mask: int = 1


# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

## Cached ray query parameters (no per-frame allocation).
var _ray_params: PhysicsRayQueryParameters3D = null

## Whether currently attached to a surface.
var _attached: bool = false

## World position of grapple attachment point.
var _target_point: Vector3 = Vector3.ZERO

## Reference to the chunk we're attached to (for physics readiness checks).
var _attached_chunk: Object = null


# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _init() -> void:
	display_name = "Grapple Hook"
	cooldown = 0.5
	interruptible = true


func enter(owner: CharacterBody3D) -> void:
	super.enter(owner)
	
	# Initialize cached ray parameters (done once, reused)
	if _ray_params == null:
		_ray_params = PhysicsRayQueryParameters3D.new()
	
	# Reset ray params for this activation
	_ray_params.collision_mask = collision_mask
	_ray_params.exclude = []
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true


func exit() -> void:
	_detach()
	super.exit()


func physics_update(delta: float) -> void:
	super.physics_update(delta)
	
	if not is_active or not player:
		return
	
	if _attached:
		_process_pull(delta)


func input(event: InputEvent) -> bool:
	if not InputMap.has_action(input_grapple):
		return false
	
	if event.is_action_pressed(input_grapple):
		if _attached:
			_release_and_exit()
		else:
			if not _try_attach():
				# Failed to attach - exit ability
				_exit_ability()
		return true
	
	return false


# -------------------------------------------------------------------
# Grapple Logic
# -------------------------------------------------------------------

## Attempts to attach grapple via raycast.
## @return bool: True if attached successfully.
func _try_attach() -> bool:
	if not player:
		return false
	
	var camera: Camera3D = _get_camera()
	if not camera:
		return false
	
	# Setup ray from camera forward
	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_basis.z) * max_range
	
	# Update cached ray params (no new() allocation)
	_ray_params.from = from
	_ray_params.to = to
	_ray_params.exclude = [player.get_rid()]
	
	# Perform raycast
	var space_state := player.get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(_ray_params)
	
	if result.is_empty():
		return false
	
	# Void Problem Safety: Check if hit chunk has physics ready
	# Void Problem Safety: Check if hit chunk has physics ready
	# With ChunkServer, we can't get chunk via collider.get_parent() because it's an RID.
	# We must look up the chunk via ChunkManager using the hit position.
	var chunk_manager = player.get("chunk_manager")
	if chunk_manager:
		# Offset slightly into the surface to ensure we get the block's chunk, not the air neighbor
		var normal: Vector3 = result["normal"]
		var hit_pos: Vector3 = result["position"] - (normal * 0.05)
		
		# We need to access ChunkManager helpers exposed or replicate logic
		# ChunkManager should have get_chunk_at(pos). If not, we rely on ability to access it via property.
		if chunk_manager.has_method("get_chunk_at_world_pos"):
			var chunk = chunk_manager.get_chunk_at_world_pos(hit_pos)
			if chunk:
				if not chunk.is_collision_enabled():
					push_warning("GrappleAbility: Rejected grapple to chunk with no collision")
					return false
				_attached_chunk = chunk
		# Fallback: manually calculate if helper missing (assuming standard size 32)
		elif chunk_manager.has_method("world_to_chunk_coord") and chunk_manager.has_method("get_chunk"):
			var key: Vector2i = chunk_manager.world_to_chunk_coord(hit_pos)
			var chunk = chunk_manager.get_chunk(key)
			if chunk:
				if chunk.has_method("is_collision_enabled") and not chunk.is_collision_enabled():
					push_warning("GrappleAbility: Rejected grapple to chunk with no collision")
					return false
				_attached_chunk = chunk
	
	_target_point = result["position"]
	_attached = true
	
	grapple_attached.emit(_target_point)
	return true


## Processes pull movement while attached.
func _process_pull(delta: float) -> void:
	if not player or not _attached:
		return
	
	# Void Problem Safety: Continuously verify chunk physics
	if _attached_chunk and _attached_chunk.has_method("is_collision_enabled"):
		if not _attached_chunk.is_collision_enabled():
			push_warning("GrappleAbility: Chunk lost collision - detaching")
			_detach()
			return
	
	var direction: Vector3 = (_target_point - player.global_position).normalized()
	var distance: float = player.global_position.distance_to(_target_point)
	
	# Auto-release when close enough
	if distance < release_distance:
		_detach()
		return
	
	# Apply pull velocity
	var pull_velocity: Vector3 = direction * pull_speed
	player.velocity = pull_velocity
	player.move_and_slide()


## Detaches grapple and resets state (does NOT exit ability).
func _detach() -> void:
	if _attached:
		_attached = false
		_target_point = Vector3.ZERO
		_attached_chunk = null
		start_cooldown()
		grapple_detached.emit()


## Releases grapple and exits the ability (returns control to player).
func _release_and_exit() -> void:
	_detach()
	_exit_ability()


## Exits the ability and returns control to player.
func _exit_ability() -> void:
	is_active = false
	ability_finished.emit()


## Gets the camera from player hierarchy.
func _get_camera() -> Camera3D:
	if not player:
		return null
	
	# Try common camera paths
	var head: Node = player.get_node_or_null("Head")
	if head:
		var cam: Camera3D = head.get_node_or_null("Camera3D")
		if cam:
			return cam
	
	# Fallback: search for any Camera3D child
	for child in player.get_children():
		if child is Camera3D:
			return child
		for grandchild in child.get_children():
			if grandchild is Camera3D:
				return grandchild
	
	return null


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Returns whether the grapple is currently attached.
func is_attached() -> bool:
	return _attached


## Returns the current grapple target point (or Vector3.ZERO if not attached).
func get_target_point() -> Vector3:
	return _target_point if _attached else Vector3.ZERO


## Force detach (for external interruption).
func force_detach() -> void:
	_detach()
