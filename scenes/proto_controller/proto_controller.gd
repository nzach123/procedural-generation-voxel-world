# ProtoController by Brackeys (CC0) - Modified for ability system
extends CharacterBody3D

# Explicit preload for static method access
const BlockInteraction := preload("res://scenes/proto_controller/block_interaction.gd")
const AbilitySystem := preload("res://scenes/proto_controller/ability_system.gd")

@onready var raycast := $Head/Camera3D/RayCast3D
@onready var cube_selected: Node3D = $"../CubeSelection"

## Reference to ChunkManager for collision radius updates.
var chunk_manager: Node = null


# -- Movement Exports --

## Can we move around?
@export var can_move : bool = true
## Are we affected by gravity?
@export var has_gravity : bool = true
## Can we press to jump?
@export var can_jump : bool = true
## Can we hold to run?
@export var can_sprint : bool = false
## Can we press to enter freefly mode (noclip)?
@export var can_freefly : bool = false

@export_group("Speeds")
## Look around rotation speed.
@export var look_speed : float = 0.002
## Normal speed (acting as max speed on ground).
@export var max_speed_ground : float = 7.0
## Speed of jump.
@export var jump_velocity : float = 4.5
## How fast do we run?
@export var max_speed_sprint : float = 10.0
## How fast do we crouch?
@export var max_speed_crouch : float = 3.5
## Max speed we can accelerate TO in air (does not cap momentum, only impulse).
@export var max_speed_air : float = 0.8
## How fast do we freefly?
@export var freefly_speed : float = 25.0

@export_group("Physics Properties")
## How fast we accelerate on the ground (units/sec^2).
@export var acceleration: float = 10.0
## How fast we decelerate on the ground (units/sec^2).
@export var friction: float = 6.0
## How fast we can change direction in the air (units/sec^2).
@export var air_acceleration: float = 100.0
## Max speed we can accelerate TO in air (does not cap momentum, only impulse).
# REMOVED old air_move_speed, replaced by max_speed_air above
## Maximum number of jumps allowed (e.g., 2 for double jump).
@export var max_jumps: int = 2

@export_group("Input Actions")
## Name of Input Action to move Left.
@export var input_left : String = "ui_left"
## Name of Input Action to move Right.
@export var input_right : String = "ui_right"
## Name of Input Action to move Forward.
@export var input_forward : String = "ui_up"
## Name of Input Action to move Backward.
@export var input_back : String = "ui_down"
## Name of Input Action to Jump.
@export var input_jump : String = "ui_accept"
## Name of Input Action to Sprint.
@export var input_sprint : String = "sprint"
## Name of Input Action to Crouch.
@export var input_crouch : String = "crouch"
## Name of Input Action to toggle freefly mode.
@export var input_freefly : String = "freefly"

@export_group("Abilities")
## Array of abilities available to this player.
## These are duplicated on init to ensure state isolation between sessions.
@export var ability_templates: Array[PlayerAbility] = []


# -- State --

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false
var jump_count : int = 0

# Crouch State
var _original_capsule_height: float = 2.0
var _original_head_y: float = 1.7
var _crouch_height: float = 1.0 # Target capsule height
var _crouching: bool = false
var _shapecast: ShapeCast3D = null


@onready var head: Node3D = $Head          ## Head node for camera
@onready var collider: CollisionShape3D = $Collider
var _last_collision_update_pos: Vector3 = Vector3.ZERO  ## For collision radius throttling

var _ability_system: RefCounted = null  ## AbilitySystem component


# -- Lifecycle --

func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	
	# Store original dimensions
	if collider.shape is CapsuleShape3D or collider.shape is CylinderShape3D:
		_original_capsule_height = collider.shape.height
	_original_head_y = head.position.y
	
	# Find ChunkManager as sibling node
	chunk_manager = get_node_or_null("../ChunkManager")
	
	# Setup Safety ShapeCast for uncrouching
	_shapecast = ShapeCast3D.new()
	_shapecast.shape = collider.shape.duplicate()
	if _shapecast.shape is CapsuleShape3D:
		_shapecast.shape.height = _original_capsule_height
	_shapecast.position.y = _original_capsule_height / 2.0 # Anchor check relative to bottom
	_shapecast.target_position = Vector3.ZERO
	_shapecast.max_results = 1
	_shapecast.enabled = false # Only enable when checking
	# Add to collider so it moves with us, or body? Body.
	add_child(_shapecast)

	# Enable collision for chunks near player on startup
	if chunk_manager and chunk_manager.has_method("update_collision_radius"):
		call_deferred("_initial_collision_update")
	
	# Initialize ability system
	_ability_system = AbilitySystem.new()
	_ability_system.initialize(self, ability_templates)


func _unhandled_input(event: InputEvent) -> void:
	# Delegate to ability system
	if _ability_system and _ability_system.handle_input(event):
		return
	
	# Handle mouse capture
	_handle_mouse_capture()
	
	# Handle look rotation
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)
		return
	
	# Handle freefly toggle
	if _handle_freefly_toggle():
		return
	
	# Handle block interaction
	_handle_block_input(event)


## Handles mouse capture/release logic.
func _handle_mouse_capture() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	elif Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()


## Handles freefly mode toggle.
## @return bool: True if toggle was handled.
func _handle_freefly_toggle() -> bool:
	if not can_freefly or not Input.is_action_just_pressed(input_freefly):
		return false
	
	if freeflying:
		disable_freefly()
	else:
		enable_freefly()
	return true


## Handles block placement and deletion input.
func _handle_block_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.is_pressed():
		return
	
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_block_delete()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_handle_block_place()
	


func _physics_process(delta: float) -> void:
	# Delegate to ability system
	if _ability_system:
		_ability_system.physics_update(delta)
	
	# If active ability is controlling movement, skip default movement
	if _ability_system and _ability_system.is_active_controlling():
		_update_block_selection()
		_update_collision_radius()
		return
	
	# If freeflying, handle freefly and nothing else
	if can_freefly and freeflying:
		_process_freefly_movement(delta)
		return
	
	# Normal ground movement
	_process_ground_movement(delta)
	
	_update_block_selection()
	_update_collision_radius()


## Handles freefly (noclip) movement.
func _process_freefly_movement(delta: float) -> void:
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	motion *= freefly_speed * delta
	move_and_collide(motion)
	_update_block_selection()
	_update_collision_radius()


## Handles normal ground movement with physics-based acceleration.
func _process_ground_movement(delta: float) -> void:
	# 1. Handle Jumping Logic
	if is_on_floor():
		jump_count = 0
	
	if can_jump and Input.is_action_just_pressed(input_jump):
		if is_on_floor() or jump_count < max_jumps:
			velocity.y = jump_velocity
			jump_count += 1
	
	# 2. Apply Gravity
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	# 3. Determine move direction and speed
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	var transform_basis_rot := transform.basis
	# Helper to orient wish direction relative to camera/player
	var wish_dir := (transform_basis_rot * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Determine speed based on state priority: Crouch > Sprint > Walk
	var wish_speed: float = max_speed_ground
	
	# Check crouch input
	var wants_crouch = Input.is_action_pressed(input_crouch)
	
	# Safety Check: If we want to stand up (not crouching), check overhead
	if _crouching and not wants_crouch:
		if _can_uncrouch():
			_crouching = false
		else:
			# Blocked, force crouch
			_crouching = true
	else:
		_crouching = wants_crouch
	
	if _crouching:
		wish_speed = max_speed_crouch
	elif can_sprint and Input.is_action_pressed(input_sprint):
		wish_speed = max_speed_sprint
	
	# If not moving, wish_speed is 0 for deceleration, but direction matters for friction
	if not can_move:
		wish_speed = 0.0
		wish_dir = Vector3.ZERO
	
	# 4. Delegate to appropriate physics state
	if is_on_floor():
		_handle_ground_physics(wish_dir, wish_speed, delta)
	else:
		_handle_air_physics(wish_dir, wish_speed, delta)

	# 5. Handle Crouch Logic (Hull manipulation)
	_handle_crouch_hull(delta)

	move_and_slide()


## Applies ground friction and acceleration.
func _handle_ground_physics(wish_dir: Vector3, wish_speed: float, delta: float) -> void:
	# Apply friction first
	_apply_friction(delta)
	
	# Then accelerate
	if wish_dir != Vector3.ZERO:
		_accelerate(wish_dir, wish_speed, acceleration, delta)
	else:
		# If no input, we just let friction do the work. 
		# Ensure velocity doesn't drift infinitely small
		if velocity.length_squared() < 0.01:
			velocity.x = 0
			velocity.z = 0


## Applies air acceleration (air strafing).
func _handle_air_physics(wish_dir: Vector3, wish_speed: float, delta: float) -> void:
	# No friction in air
	
	# Source Air Logic:
	# Cap wish_speed to air max specific
	var air_target_speed = min(wish_speed, max_speed_air)
	
	if wish_dir != Vector3.ZERO:
		_accelerate(wish_dir, air_target_speed, air_acceleration, delta)


## Applies Source-style acceleration.
func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	# Project current velocity onto the wish direction
	# velocity.x and .z only (planar - using dot product on 3D vectors is fine if y is 0 or handled elsewhere, 
	# but strictly for ground/air movement we usually care about horizontal).
	# Assuming wish_dir is horizontal (y=0).
	
	var current_speed_in_wish_dir = velocity.dot(wish_dir)
	var add_speed = wish_speed - current_speed_in_wish_dir
	
	if add_speed <= 0:
		return # Already going fast enough in this direction
	
	# Source Math: accel_speed = accel * delta * wish_speed
	var accel_speed = accel * delta * wish_speed
	
	# Cap acceleration so we don't overshoot
	if accel_speed > add_speed:
		accel_speed = add_speed
	
	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z


## Handle Hull resizing for crouching.
## Standard: Height 2.0, PosY 1.0 (Center) -> Feet at 0.0, Head at 2.0.
## Ground Crouch: Height 1.0, PosY 0.5 (Center) -> Feet at 0.0, Head at 1.0. (Shrink from Top properly).
## Air Crouch: Height 1.0, PosY 1.5 (Center) -> Feet at 1.0, Head at 2.0. (Shrink from Bottom / Raise Feet).
func _handle_crouch_hull(delta: float) -> void:
	var target_height: float = _original_capsule_height
	var target_y: float = _original_capsule_height / 2.0 # Default center
	var target_head_y: float = _original_head_y

	if _crouching:
		target_height = _crouch_height
		if is_on_floor():
			# Ground Crouch: Shrink down (Feet stay on ground)
			target_y = _crouch_height / 2.0
			target_head_y = _original_head_y - (_original_capsule_height - _crouch_height) # Rough approx
		else:
			# Air Crouch: Legs Up (Head stays at top)
			# Top is (OriginalH), Bottom is (OriginalH - CrouchH)
			# Center is (Top + Bottom) / 2 = (OriginalH + (OriginalH - CrouchH)) / 2
			# = (2.0 + 1.0) / 2 = 1.5
			target_y = _original_capsule_height - (_crouch_height / 2.0)
			# Ensure head stays relative to body, or just keep head high?
			# Usually camera stays same height in world space during air crouch.
			target_head_y = _original_head_y

	# Smooth transitions for visual feel, but Physics should ideally be snappy.
	# For simplicity and correctness in this phase, we snap the physics hull.
	# Camera can smooth if needed.
	
	if collider.shape is CapsuleShape3D or collider.shape is CylinderShape3D:
		var current_height = collider.shape.height
		var current_y = collider.position.y
		
		if current_height != target_height:
			collider.shape.height = target_height
		
		# Move Collider Position
		if current_y != target_y:
			# ORIGIN SHIFT FIX:
			# Calculate bottom offset using OLD height and NEW height.
			var old_bottom = current_y - (current_height / 2.0)
			var new_bottom = target_y - (target_height / 2.0)
			var diff = new_bottom - old_bottom
			
			# ONLY compensate if we are extending down (Diff < 0) to avoid embedding in floor.
			if diff < -0.001:
				global_position.y -= diff
				# COUNTER-SHIFT CAMERA:
				head.position.y += diff

			collider.position.y = target_y
			
	# Smooth Camera
	head.position.y = move_toward(head.position.y, target_head_y, delta * 10.0)


## Checks if there is room to uncrouch.
func _can_uncrouch() -> bool:
	if not _shapecast:
		return true
		
	# Check from bottom up to full height
	_shapecast.global_position = global_position
	# We want to check if the FULL height capsule would collide.
	# The shapecast shape is already set to full height in _ready.
	_shapecast.position.y = _original_capsule_height / 2.0
	
	_shapecast.force_shapecast_update()
	return not _shapecast.is_colliding()


## Applies ground friction to velocity (horizontal only).
func _apply_friction(delta: float) -> void:
	var speed = Vector3(velocity.x, 0, velocity.z).length()
	if speed < 0.001:
		velocity.x = 0
		velocity.z = 0
		return
		
	# Determine drop amount
	# Source uses: control = speed < stop_speed ? stop_speed : speed;
	# new_speed = speed - (control * friction * delta)
	# Simplified linear friction here:
	
	var control: float = speed if speed > 1.0 else 1.0 # "Stop speed" of 1.0
	var drop: float = control * friction * delta
	
	var new_speed: float = speed - drop
	if new_speed < 0:
		new_speed = 0
		
	new_speed /= speed # Scale factor
	
	velocity.x *= new_speed
	velocity.z *= new_speed


# -- Ability System (Delegated) --

## Activate an ability by index.
func activate_ability(index: int) -> bool:
	return _ability_system.activate(index) if _ability_system else false


## Deactivate the current ability.
func deactivate_ability() -> void:
	if _ability_system:
		_ability_system.deactivate()


## Get the currently active ability (or null).
func get_active_ability() -> PlayerAbility:
	return _ability_system.get_active() if _ability_system else null


## Get ability by index.
func get_ability(index: int) -> PlayerAbility:
	return _ability_system.get_ability(index) if _ability_system else null


## Get total number of abilities.
func get_ability_count() -> int:
	return _ability_system.get_count() if _ability_system else 0


# -- Look / Mouse --

## Rotate us to look around.
## Base of controller rotates around y (left/right). Head rotates around x (up/down).
## Modifies look_rotation based on rot_input, then resets basis and rotates by look_rotation.
func rotate_look(rot_input : Vector2) -> void:
	look_rotation.x -= rot_input.y * look_speed
	var min_angle: float = deg_to_rad(-VoxelConstants.LOOK_ANGLE_LIMIT)
	var max_angle: float = deg_to_rad(VoxelConstants.LOOK_ANGLE_LIMIT)
	look_rotation.x = clamp(look_rotation.x, min_angle, max_angle)
	look_rotation.y -= rot_input.x * look_speed
	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)


func enable_freefly() -> void:
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO


func disable_freefly() -> void:
	collider.disabled = false
	freeflying = false


func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false


## Checks if some Input Actions haven't been created.
## Disables functionality accordingly.
func check_input_mappings() -> void:
	var disabled := ProtoInputHandler.validate_mappings(self)
	ProtoInputHandler.apply_disabled_features(self, disabled)


# -- Block Interaction --

func _handle_block_delete() -> void:
	BlockInteraction.delete_block_from_raycast(raycast, chunk_manager)


func _handle_block_place() -> void:
	BlockInteraction.place_block_from_raycast(raycast, chunk_manager, self)


func _update_block_selection() -> void:
	BlockInteraction.update_selection(raycast, chunk_manager, cube_selected)


# -- Collision Radius --

## Updates collision radius on ChunkManager when player moves significantly.
func _update_collision_radius() -> void:
	if not chunk_manager or not chunk_manager.has_method("update_collision_radius"):
		return
	
	# Only update if moved more than half a chunk
	var pos: Vector3 = global_position
	var distance_sq: float = pos.distance_squared_to(_last_collision_update_pos)
	if distance_sq > VoxelConstants.COLLISION_UPDATE_THRESHOLD:
		_last_collision_update_pos = pos
		chunk_manager.update_collision_radius(pos)


## Initial collision update after scene is ready.
func _initial_collision_update() -> void:
	if chunk_manager and chunk_manager.has_method("update_collision_radius"):
		_last_collision_update_pos = global_position
		chunk_manager.update_collision_radius(global_position)
