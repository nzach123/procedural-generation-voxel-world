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

## Pull acceleration force (units/sec^2).
## Replaces "pull_speed" to provide additive force instead of fixed velocity.
@export var pull_force: float = 40.0

## Maximum speed allowed while grappling to play nice with chunk loading.
@export var max_grapple_speed: float = 30.0

## Minimum distance from target to auto-release.
@export var release_distance: float = 2.0

## Input action to fire/release grapple.
@export var input_grapple: String = "grapple"

## Cooldown after detaching in seconds.
@export var attach_cooldown: float = 0.2

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

## Cooldown timer to prevent accidental immediate re-attachment.
var _cooldown_timer: float = 0.0

## Visual Rope Instance
var _rope_mesh: MeshInstance3D = null



# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _init() -> void:
	display_name = "Grapple Hook"
	cooldown = 0.0 # Base cooldown handled manually via _cooldown_timer
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
	
	_cooldown_timer = 0.0


func exit() -> void:
	_detach()
	super.exit()


func physics_update(delta: float) -> void:
	super.physics_update(delta)
	
	if not is_active or not player:
		return
		
	# Handle cooldown
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	
	if _attached:
		_process_pull(delta)


func input(event: InputEvent) -> bool:
	if not InputMap.has_action(input_grapple):
		return false
	
	if event.is_action_pressed(input_grapple):
		if _attached:
			# Toggle OFF: Detach but keep momentum
			_detach()
			# We don't exit the ability entirely, allowing quick re-grapples?
			# Actually, if "is_active" means "equipped/selected", then yes.
			# But if abilities are "active only when using", then detach might exit?
			# Design choice: Grapple is an active state. 
			# If we detach, do we want to stop being "Allocated Ability"?
			# For now, yes, let's exit ability on detach to return to neutral state.
			# This allows other abilities to take over if needed.
			_exit_ability()
		else:
			# Toggle ON: Try to attach
			if _cooldown_timer <= 0.0:
				if not _try_attach():
					# Failed to attach - do not stay active if this was a one-shot attempt
					# But if this is "Equipped Item", we stay active.
					# Assuming "Ability" pattern is transient (Press -> Active -> Done).
					# So failure to attach means ability fails to start.
					_exit_ability()
			else:
				_exit_ability()
		return true
	
	return false


# -------------------------------------------------------------------
# Grapple Logic
# -------------------------------------------------------------------

## Looks up chunk at raycast hit position and validates collision readiness.
## @return RefCounted: Valid chunk or null if not found/collision disabled
func _lookup_chunk_at_hit(hit_pos: Vector3, normal: Vector3) -> RefCounted:
	var chunk_manager: Node = player.get("chunk_manager")
	if not chunk_manager:
		return null
	
	var adjusted_pos: Vector3 = hit_pos - (normal * VoxelConstants.RAYCAST_INSET)
	var chunk: RefCounted = null
	
	if chunk_manager.has_method("get_chunk_at_world_pos"):
		chunk = chunk_manager.get_chunk_at_world_pos(adjusted_pos)
	elif chunk_manager.has_method("world_to_chunk_coord") and chunk_manager.has_method("get_chunk"):
		var key: Vector2i = chunk_manager.world_to_chunk_coord(adjusted_pos)
		chunk = chunk_manager.get_chunk(key)
	
	if chunk and chunk.has_method("is_collision_enabled") and not chunk.is_collision_enabled():
		push_warning("GrappleAbility: Rejected grapple to chunk with no collision")
		return null
	
	return chunk


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
	
	# Void Problem Safety: Validate chunk has physics ready
	var chunk: RefCounted = _lookup_chunk_at_hit(result["position"], result["normal"])
	if chunk:
		_attached_chunk = chunk
	elif player.get("chunk_manager") != null:
		return false  # Had chunk manager but chunk invalid
	
	_target_point = result["position"]
	_attached = true
	
	_target_point = result["position"]
	_attached = true
	
	# Task 2.1: Ground Grapple Impulse
	# If on ground, launch upward to prevent dragging
	if player.is_on_floor():
		var jump_impulse: float = 5.0
		if player.get("jump_velocity") != null:
			jump_impulse = player.jump_velocity
		
		# Add a bit extra for "Grapple Jump" feel
		player.velocity.y = jump_impulse * 1.5
	
	# Task 2.2: Attach Feedback (Tug)
	if player.has_method("apply_fov_kick"):
		player.apply_fov_kick(-2.0, 0.15) # Quick zoom in "tug"
	
	# Task 3.1: Initialize Rope Visualization
	_init_rope_visual()
	
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
			_exit_ability()
			return
	
	var current_pos: Vector3 = player.global_position
	var direction_to_target: Vector3 = (_target_point - current_pos).normalized()
	var distance: float = current_pos.distance_to(_target_point)
	
	# Auto-release when close enough
	if distance < release_distance:
		_detach()
		_exit_ability()
		return
	
	# Apply additive force (F=ma logic integration)
	# Force Vector = Direction * ForceScalar
	# Velocity += Force * Delta
	var force_vector: Vector3 = direction_to_target * pull_force
	
	# Add to current velocity (Momentum Preservation)
	player.velocity += force_vector * delta
	
	# Apply Gravity manually since Controller disabled its physics
	# We assume we want gravity active during a swing
	if player.has_method("get_gravity"):
		player.velocity += player.get_gravity() * delta
	else:
		# Fallback standard gravity assumption if method missing
		player.velocity += Vector3.DOWN * 9.8 * delta
	
	# Speed Limit Check
	# We only clamp if we are accelerating BEYOND the limit.
	# If we are already fast but decelerating, don't clamp hard (allow soft re-entry).
	# For now, simple hard clamp provides safety.
	if player.velocity.length() > max_grapple_speed:
		player.velocity = player.velocity.normalized() * max_grapple_speed
	
	# CRITICAL: Must call move_and_slide to actually move the player
	player.move_and_slide()
	
	# Task 3.1: Update Rope Visual
	_update_rope_visual()


## Detaches grapple and resets state.
func _detach() -> void:
	if _attached:
		_attached = false
		_target_point = Vector3.ZERO
		_attached_chunk = null
		_cooldown_timer = attach_cooldown
		var speed: float = player.velocity.length()
		
		# Task 2.2: Detach Feedback (Speed Release)
		if speed > 15.0 and player.has_method("apply_fov_kick"):
			player.apply_fov_kick(5.0, 0.4) # Zoom out "speed" sensation
		
		# Task 3.1: Cleanup Rope
		_cleanup_rope_visual()
		
		grapple_detached.emit()
		# NOTE: We implicitly preserve momentum by NOT zeroing player.velocity here.


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


# -------------------------------------------------------------------
# Visuals (Phase 3)
# -------------------------------------------------------------------

func _init_rope_visual() -> void:
	if not player:
		return
	
	if _rope_mesh:
		_cleanup_rope_visual()
		
	_rope_mesh = MeshInstance3D.new()
	var immediate_mesh = ImmediateMesh.new()
	_rope_mesh.mesh = immediate_mesh
	_rope_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Create a simple standard material
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	_rope_mesh.material_override = material
	
	player.get_parent().add_child(_rope_mesh)


func _update_rope_visual() -> void:
	if not _rope_mesh or not _attached or not player:
		return
		
	var immediate_mesh = _rope_mesh.mesh as ImmediateMesh
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Start point: Camera/Head position (approximation of hand/tool)
	var start_pos = player.global_position + Vector3(0, 1.5, 0) # Rough center
	var cam = _get_camera()
	if cam:
		# Use a point slightly below/right of camera to look like a tool
		var right = cam.global_basis.x
		var down = -cam.global_basis.y
		start_pos = cam.global_position + (right * 0.2) + (down * 0.2)
	
	immediate_mesh.surface_add_vertex(start_pos)
	immediate_mesh.surface_add_vertex(_target_point)
	immediate_mesh.surface_end()


func _cleanup_rope_visual() -> void:
	if _rope_mesh:
		if _rope_mesh.is_inside_tree():
			_rope_mesh.queue_free()
		_rope_mesh = null
