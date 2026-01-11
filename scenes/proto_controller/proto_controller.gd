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
## Normal speed.
@export var base_speed : float = 7.0
## Speed of jump.
@export var jump_velocity : float = 4.5
## How fast do we run?
@export var sprint_speed : float = 10.0
## How fast do we freefly?
@export var freefly_speed : float = 25.0

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

@onready var head: Node3D = $Head          ## Head node for camera
@onready var collider: CollisionShape3D = $Collider
var _last_collision_update_pos: Vector3 = Vector3.ZERO  ## For collision radius throttling

var _ability_system: RefCounted = null  ## AbilitySystem component


# -- Lifecycle --

func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	
	# Find ChunkManager as sibling node
	chunk_manager = get_node_or_null("../ChunkManager")
	
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


## Handles normal ground movement with gravity, jumping, and sprinting.
func _process_ground_movement(delta: float) -> void:
	# Apply gravity
	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	# Apply jumping
	if can_jump and Input.is_action_just_pressed(input_jump) and is_on_floor():
		velocity.y = jump_velocity

	# Modify speed based on sprinting
	if can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed

	# Apply desired movement to velocity
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if move_dir:
			velocity.x = move_dir.x * move_speed
			velocity.z = move_dir.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.y = 0
	
	move_and_slide()


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
