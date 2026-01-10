# ProtoController v1.0 by Brackeys
# CC0 License
# Intended for rapid prototyping of first-person games.
# Happy prototyping!
#
# Modified: Added component-based ability system for modular player behaviors.

extends CharacterBody3D

@onready var raycast := $Head/Camera3D/RayCast3D
@onready var cube_selected: Node3D = $"../CubeSelection"

## Reference to ChunkManager for collision radius updates.
var chunk_manager: Node = null


# -------------------------------------------------------------------
# Movement Exports
# -------------------------------------------------------------------

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


# -------------------------------------------------------------------
# State
# -------------------------------------------------------------------

var mouse_captured : bool = false
var look_rotation : Vector2
var move_speed : float = 0.0
var freeflying : bool = false

## IMPORTANT REFERENCES
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider

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
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	
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
	
	# Check if any ability wants to activate via this input
	if _try_activate_ability_by_input(event):
		return
	
	# Mouse capturing
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		capture_mouse()
	if Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	
	# Look around
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)
	
	# Toggle freefly mode
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		if not freeflying:
			enable_freefly()
		else:
			disable_freefly()
		
	# Block interaction (if no ability consumed input)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		_handle_block_delete()
				
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		_handle_block_place()
	
	# DEBUG: Inspect chunk under player
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
			var chunk: RefCounted = chunk_manager.get_chunk_at_world_pos(global_position)
			if chunk:
				DebugLogger.debug("--- CHUNK INSPECTOR ---", "Debug")
				DebugLogger.debug("Chunk: %s" % chunk.key, "Debug")
				DebugLogger.debug("Offset: %s" % chunk.chunk_offset, "Debug")
				DebugLogger.debug("Collision enabled: %s" % chunk.is_collision_enabled(), "Debug")
				if chunk.has_method("_get_mesh_instance_rid"):
					DebugLogger.debug("Mesh RID: %s" % chunk._mesh_instance_rid, "Debug")
			else:
				DebugLogger.debug("--- CHUNK INSPECTOR: No chunk found at %s" % global_position, "Debug")


func _physics_process(delta: float) -> void:
	# Delegate to active ability
	if _active_ability:
		_active_ability.physics_update(delta)
	
	# Update cooldowns on all abilities
	for ability in _abilities:
		if ability != _active_ability:
			ability.physics_update(delta)
	
	# If active ability is controlling movement, skip default movement
	if _active_ability and _active_ability.is_active:
		_update_block_selection()
		_update_collision_radius()
		return
	
	# If freeflying, handle freefly and nothing else
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		motion *= freefly_speed * delta
		move_and_collide(motion)
		_update_block_selection()
		_update_collision_radius()
		return
	
	# Apply gravity to velocity
	if has_gravity:
		if not is_on_floor():
			velocity += get_gravity() * delta

	# Apply jumping
	if can_jump:
		if Input.is_action_just_pressed(input_jump) and is_on_floor():
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
	
	# Use velocity to actually move
	move_and_slide()
	
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
		_disconnect_ability_signals(_active_ability)
		_active_ability.exit()
	
	_active_ability = ability
	_connect_ability_signals(_active_ability)
	_active_ability.enter(self)
	return true


## Deactivate the current ability.
func deactivate_ability() -> void:
	if _active_ability:
		_disconnect_ability_signals(_active_ability)
		_active_ability.exit()
		_active_ability = null


## Called when active ability finishes (self-deactivates).
func _on_ability_finished() -> void:
	if _active_ability:
		_disconnect_ability_signals(_active_ability)
		_active_ability = null


## Connect signals for an ability.
func _connect_ability_signals(ability: PlayerAbility) -> void:
	if not ability.ability_finished.is_connected(_on_ability_finished):
		ability.ability_finished.connect(_on_ability_finished)


## Disconnect signals for an ability.
func _disconnect_ability_signals(ability: PlayerAbility) -> void:
	if ability.ability_finished.is_connected(_on_ability_finished):
		ability.ability_finished.disconnect(_on_ability_finished)


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


## Tries to activate an ability based on input event.
## Checks each ability for an input action property and activates if matched.
## @return bool: True if an ability was activated.
func _try_activate_ability_by_input(event: InputEvent) -> bool:
	for i in range(_abilities.size()):
		var ability := _abilities[i]
		
		# Check if this ability has an activation input property
		if ability.has_method("get") and ability.get("input_grapple") is String:
			var action_name: String = ability.get("input_grapple")
			if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
				if activate_ability(i):
					# Also forward the input to the now-active ability
					ability.input(event)
					return true
	
	return false


# -------------------------------------------------------------------
# Look / Mouse
# -------------------------------------------------------------------

## Rotate us to look around.
## Base of controller rotates around y (left/right). Head rotates around x (up/down).
## Modifies look_rotation based on rot_input, then resets basis and rotates by look_rotation.
func rotate_look(rot_input : Vector2) -> void:
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-VoxelConstants.LOOK_ANGLE_LIMIT), deg_to_rad(VoxelConstants.LOOK_ANGLE_LIMIT))
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
	if can_move and not InputMap.has_action(input_left):
		push_error("Movement disabled. No InputAction found for input_left: " + input_left)
		can_move = false
	if can_move and not InputMap.has_action(input_right):
		push_error("Movement disabled. No InputAction found for input_right: " + input_right)
		can_move = false
	if can_move and not InputMap.has_action(input_forward):
		push_error("Movement disabled. No InputAction found for input_forward: " + input_forward)
		can_move = false
	if can_move and not InputMap.has_action(input_back):
		push_error("Movement disabled. No InputAction found for input_back: " + input_back)
		can_move = false
	if can_jump and not InputMap.has_action(input_jump):
		push_error("Jumping disabled. No InputAction found for input_jump: " + input_jump)
		can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint):
		push_error("Sprinting disabled. No InputAction found for input_sprint: " + input_sprint)
		can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly):
		push_error("Freefly disabled. No InputAction found for input_freefly: " + input_freefly)
		can_freefly = false


# -------------------------------------------------------------------
# Block Interaction
# -------------------------------------------------------------------

func _handle_block_delete() -> void:
	if raycast.is_colliding():
		var point: Vector3 = raycast.get_collision_point()
		var normal: Vector3 = raycast.get_collision_normal()
		
		# Offset slightly into the block to ensure we get the correct world position
		var hit_pos: Vector3 = point - (normal * VoxelConstants.RAYCAST_INSET)
		
		# Look up chunk via manager
		if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
			var chunk: RefCounted = chunk_manager.get_chunk_at_world_pos(hit_pos)
			
			if chunk and chunk.has_method("delete_block"):
				var block_coords: Vector3i = _get_hit_block(point, normal)
				chunk.delete_block(block_coords)


func _handle_block_place() -> void:
	if raycast.is_colliding():
		var point: Vector3 = raycast.get_collision_point()
		var normal: Vector3 = raycast.get_collision_normal()
		
		# For placement, we want the chunk adjacent to the hit face (where new block goes)
		# Or stick to hit chunk? Usually we modify the chunk where the new block coordinates fall.
		var block_coords: Vector3i = _get_adjacent_block(point, normal)
		var place_pos: Vector3 = Vector3(block_coords.x, block_coords.y, block_coords.z)
		
		if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
			var chunk: RefCounted = chunk_manager.get_chunk_at_world_pos(place_pos)
			
			if chunk and chunk.has_method("add_block"):
				if _resolve_block_overlap(block_coords, normal):
					chunk.add_block(block_coords)


func _resolve_block_overlap(block_coords: Vector3i, normal: Vector3) -> bool:
	var bx := float(block_coords.x)
	var by := float(block_coords.y)
	var bz := float(block_coords.z)

	var pos := global_transform.origin
	
	# rough AABB check:
	var overlap_x: bool = abs(pos.x - bx) < VoxelConstants.PLAYER_HALF_WIDTH
	var overlap_y: bool = abs(pos.y - by) < VoxelConstants.PLAYER_HEIGHT
	var overlap_z: bool = abs(pos.z - bz) < VoxelConstants.PLAYER_HALF_WIDTH
	
	if overlap_x and overlap_y and overlap_z:
		if normal == Vector3.UP:
			var collision: KinematicCollision3D = move_and_collide(Vector3.UP)
			return collision == null
		
		return false
		
	return true


func _update_block_selection() -> void:
	if raycast.is_colliding():
		var point: Vector3 = raycast.get_collision_point()
		var normal: Vector3 = raycast.get_collision_normal()
		var block_coords: Vector3i = _get_hit_block(point, normal)
		
		var hit_pos: Vector3 = point - (normal * VoxelConstants.RAYCAST_INSET)
		
		if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
			var chunk: RefCounted = chunk_manager.get_chunk_at_world_pos(hit_pos)
		
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
	if pos.distance_squared_to(_last_collision_update_pos) > VoxelConstants.COLLISION_UPDATE_THRESHOLD:  # 16^2 = half chunk
		_last_collision_update_pos = pos
		chunk_manager.update_collision_radius(pos)


## Initial collision update after scene is ready.
func _initial_collision_update() -> void:
	if chunk_manager and chunk_manager.has_method("update_collision_radius"):
		_last_collision_update_pos = global_position
		chunk_manager.update_collision_radius(global_position)
