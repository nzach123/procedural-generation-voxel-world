extends CharacterBody3D

## Player controller with component-based ability system.
## Abilities handle specialized behaviors (grapple, etc.) and are delegated input/physics.

@onready var raycast := $Camera3D/RayCast3D
@onready var cube_selected: Node3D = $"../CubeSelection"

## Reference to ChunkManager for collision radius updates.
var chunk_manager: Node = null


# -------------------------------------------------------------------
# Exports
# -------------------------------------------------------------------

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENS = 0.002

## Array of abilities available to this player.
## These are duplicated on init to ensure state isolation.
@export var ability_templates: Array[PlayerAbility] = []


# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

var _yaw: float = 0.0
var _pitch: float = 0.0

## Last position used for collision radius update (throttling).
var _last_collision_update_pos: Vector3 = Vector3.ZERO

## Instantiated abilities (duplicated from templates for state isolation).
var _abilities: Array[PlayerAbility] = []

## Currently active ability (or null if no special ability active).
var _active_ability: PlayerAbility = null


# -------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Find ChunkManager as sibling node
	chunk_manager = get_node_or_null("../ChunkManager")
	
	# Enable collision for chunks near player on startup
	if chunk_manager and chunk_manager.has_method("update_collision_radius"):
		call_deferred("_initial_collision_update")
	
	# Initialize abilities with state isolation
	_initialize_abilities()


func _unhandled_input(event: InputEvent) -> void:
	# Delegate to active ability first
	if _active_ability and _active_ability.input(event):
		return  # Ability consumed the input
	
	# Core player input handling
	if event.is_action_pressed("ui_focus_next"):
		if get_viewport().debug_draw == Viewport.DEBUG_DRAW_WIREFRAME:
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
		else:
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
			
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	
	elif event is InputEventMouseButton and event.button_index == 2 and event.is_pressed():
		_handle_block_delete()
				
	elif event is InputEventMouseButton and event.button_index == 1 and event.is_pressed():
		_handle_block_place()
		
	elif event is InputEventMouseMotion:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch -= event.relative.y * MOUSE_SENS
		_pitch = clamp(_pitch, -PI/2, PI/2)
		
		rotation.y = _yaw
		$Camera3D.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	# Delegate to active ability
	if _active_ability:
		_active_ability.physics_update(delta)
	
	# Update cooldowns on all abilities
	for ability in _abilities:
		if ability != _active_ability:
			ability.physics_update(delta)
	
	# Core movement (can be overridden by ability)
	if not _active_ability or not _active_ability.is_active:
		_process_default_movement(delta)
	
	_update_block_selection()
	_update_collision_radius()


# -------------------------------------------------------------------
# Ability System
# -------------------------------------------------------------------

## Initialize abilities from templates with state isolation.
func _initialize_abilities() -> void:
	_abilities.clear()
	for template in ability_templates:
		if template:
			var instance := template.create_instance()
			_abilities.append(instance)


## Activate an ability by index.
## @param index: Index into _abilities array.
## @return bool: True if activation succeeded.
func activate_ability(index: int) -> bool:
	if index < 0 or index >= _abilities.size():
		return false
	
	var ability := _abilities[index]
	if not ability.is_ready():
		return false  # On cooldown
	
	# Deactivate current ability if interruptible
	if _active_ability:
		if not _active_ability.interruptible:
			return false
		_active_ability.exit()
	
	_active_ability = ability
	_active_ability.enter(self)
	return true


## Deactivate the current ability.
func deactivate_ability() -> void:
	if _active_ability:
		_active_ability.exit()
		_active_ability = null


## Get the currently active ability (or null).
func get_active_ability() -> PlayerAbility:
	return _active_ability


## Get ability by index.
func get_ability(index: int) -> PlayerAbility:
	if index >= 0 and index < _abilities.size():
		return _abilities[index]
	return null


## Get total number of abilities.
func get_ability_count() -> int:
	return _abilities.size()


# -------------------------------------------------------------------
# Movement
# -------------------------------------------------------------------

func _process_default_movement(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


# -------------------------------------------------------------------
# Block Interaction
# -------------------------------------------------------------------

func _handle_block_delete() -> void:
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider:
			var chunk = collider.get_parent()
			
			if chunk.has_method("delete_block"):
				var point = raycast.get_collision_point()
				var normal = raycast.get_collision_normal()
				var block_coords: Vector3i = _get_hit_block(point, normal)
				
				chunk.delete_block(block_coords)


func _handle_block_place() -> void:
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider:
			var chunk = collider.get_parent()
			
			if chunk.has_method("add_block"):
				var point = raycast.get_collision_point()
				var normal = raycast.get_collision_normal()
				var block_coords: Vector3i = _get_adjacent_block(point, normal)
				
				if _resolve_block_overlap(block_coords, normal):
					chunk.add_block(block_coords)


func _resolve_block_overlap(block_coords: Vector3i, normal: Vector3) -> bool:
	var bx := float(block_coords.x)
	var by := float(block_coords.y)
	var bz := float(block_coords.z)

	var pos := global_transform.origin
	
	# rough AABB check:
	var overlap_x = abs(pos.x - bx) < 0.6
	var overlap_y = abs(pos.y - by) < 1.3
	var overlap_z = abs(pos.z - bz) < 0.6
	
	if overlap_x and overlap_y and overlap_z:
		if normal == Vector3.UP:
			var collision = move_and_collide(Vector3.UP)
			return collision == null
		
		return false
		
	return true


func _update_block_selection() -> void:
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if not collider:
			return
			
		var point = raycast.get_collision_point()
		var normal = raycast.get_collision_normal()
		var block_coords: Vector3i = _get_hit_block(point, normal)
		var chunk = collider.get_parent()
		
		if chunk and chunk.has_method("check_block_selected"):
			if chunk.check_block_selected(block_coords):
				cube_selected.visible = true
				cube_selected.global_position = Vector3(block_coords.x, block_coords.y, block_coords.z)
	else:
		cube_selected.visible = false


func _get_hit_block(point: Vector3, normal: Vector3) -> Vector3i:
	return Vector3i(
		roundi(point.x - normal.x * 0.5),
		roundi(point.y - normal.y * 0.5),
		roundi(point.z - normal.z * 0.5)
	)
	

func _get_adjacent_block(point: Vector3, normal: Vector3) -> Vector3i:
	return Vector3i(
		roundi(point.x + normal.x * 0.5),
		roundi(point.y + normal.y * 0.5),
		roundi(point.z + normal.z * 0.5)
	)


# -------------------------------------------------------------------
# Collision Radius
# -------------------------------------------------------------------

## Updates collision radius on ChunkManager when player moves significantly.
func _update_collision_radius() -> void:
	if not chunk_manager or not chunk_manager.has_method("update_collision_radius"):
		return
	
	# Only update if moved more than half a chunk
	var pos := global_position
	if pos.distance_squared_to(_last_collision_update_pos) > 256.0:  # 16^2 = half chunk
		_last_collision_update_pos = pos
		chunk_manager.update_collision_radius(pos)


## Initial collision update after scene is ready.
func _initial_collision_update() -> void:
	if chunk_manager and chunk_manager.has_method("update_collision_radius"):
		_last_collision_update_pos = global_position
		chunk_manager.update_collision_radius(global_position)
