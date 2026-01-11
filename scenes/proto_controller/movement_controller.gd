## MovementController
## Node component that handles character movement for ProtoController.
## Can be disabled/swapped at runtime for vehicles, swimming, etc.
class_name MovementController
extends Node


# -------------------------------------------------------------------
# Exports
# -------------------------------------------------------------------

## The CharacterBody3D this controller moves.
@export var target: CharacterBody3D

## Head node for camera-relative movement (optional, for freefly).
@export var head: Node3D

## Movement speeds.
@export var base_speed: float = 7.0
@export var sprint_speed: float = 10.0
@export var freefly_speed: float = 25.0
@export var jump_velocity: float = 4.5

## Movement capabilities.
@export var can_move: bool = true
@export var has_gravity: bool = true
@export var can_jump: bool = true
@export var can_sprint: bool = false

## Input action names.
@export var input_left: String = "ui_left"
@export var input_right: String = "ui_right"
@export var input_forward: String = "ui_up"
@export var input_back: String = "ui_down"
@export var input_jump: String = "ui_accept"
@export var input_sprint: String = "sprint"


# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

var _current_speed: float = 0.0


# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _ready() -> void:
	# Auto-assign target if not set
	if not target:
		target = get_parent() as CharacterBody3D
	
	# Auto-find head node if not set
	if not head and target:
		head = target.get_node_or_null("Head")


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------

## Processes ground-based movement with gravity and jumping.
## Call this from _physics_process when in normal mode.
## @param delta: Physics delta time.
func process_ground_movement(delta: float) -> void:
	if not target:
		return
	
	# Apply gravity
	if has_gravity and not target.is_on_floor():
		target.velocity += target.get_gravity() * delta
	
	# Apply jumping
	if can_jump and Input.is_action_just_pressed(input_jump) and target.is_on_floor():
		target.velocity.y = jump_velocity
	
	# Modify speed based on sprinting
	if can_sprint and Input.is_action_pressed(input_sprint):
		_current_speed = sprint_speed
	else:
		_current_speed = base_speed
	
	# Apply horizontal movement
	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var move_dir := (target.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if move_dir:
			target.velocity.x = move_dir.x * _current_speed
			target.velocity.z = move_dir.z * _current_speed
		else:
			target.velocity.x = move_toward(target.velocity.x, 0, _current_speed)
			target.velocity.z = move_toward(target.velocity.z, 0, _current_speed)
	else:
		target.velocity.x = 0
		target.velocity.z = 0
	
	target.move_and_slide()


## Processes freefly (noclip) movement.
## Call this from _physics_process when in freefly mode.
## @param delta: Physics delta time.
func process_freefly_movement(delta: float) -> void:
	if not target:
		return
	
	var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
	
	# Use head basis for camera-relative movement if available
	var basis: Basis = head.global_basis if head else target.global_basis
	var motion := (basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	motion *= freefly_speed * delta
	
	target.move_and_collide(motion)


## Gets the current movement speed (base or sprint).
func get_current_speed() -> float:
	return _current_speed


## Sets movement enabled state.
func set_movement_enabled(enabled: bool) -> void:
	can_move = enabled


## Sets gravity enabled state.
func set_gravity_enabled(enabled: bool) -> void:
	has_gravity = enabled
