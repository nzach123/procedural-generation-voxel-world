## AbilitySystem
## Manages player abilities, activation, and input handling.
## Extracted from ProtoController to reduce file complexity.
class_name AbilitySystem
extends RefCounted


## Currently active ability (or null)
var _active_ability: PlayerAbility = null

## Instantiated abilities (duped from templates)
var _abilities: Array[PlayerAbility] = []

## Reference to owning player for ability callbacks
var _player: CharacterBody3D = null


## Initialize with ability templates.
## @param player: The CharacterBody3D that owns these abilities
## @param templates: Array of ability resources to instantiate
func initialize(player: CharacterBody3D, templates: Array[PlayerAbility]) -> void:
	_player = player
	_abilities.clear()
	for template in templates:
		if template:
			var instance := template.create_instance()
			_abilities.append(instance)


## Process physics update for all abilities.
## @param delta: Physics delta time
func physics_update(delta: float) -> void:
	# Delegate to active ability
	if _active_ability:
		_active_ability.physics_update(delta)
	
	# Update cooldowns on all abilities
	for ability in _abilities:
		if ability != _active_ability:
			ability.physics_update(delta)


## Handle input for abilities.
## @param event: Input event to process
## @return bool: True if input was consumed
func handle_input(event: InputEvent) -> bool:
	# Delegate to active ability first
	if _active_ability and _active_ability.input(event):
		return true
	
	# Check if any ability wants to activate via this input
	return _try_activate_by_input(event)


## Activate an ability by index.
## @param index: Index into abilities array
## @return bool: True if activation succeeded
func activate(index: int) -> bool:
	if index < 0 or index >= _abilities.size():
		return false
	
	var ability := _abilities[index]
	if not ability.is_ready():
		return false  # On cooldown
	
	# Deactivate current ability if interruptible
	if _active_ability:
		if not _active_ability.interruptible:
			return false
		_disconnect_signals(_active_ability)
		_active_ability.exit()
	
	_active_ability = ability
	_connect_signals(_active_ability)
	_active_ability.enter(_player)
	return true


## Deactivate the current ability.
func deactivate() -> void:
	if _active_ability:
		_disconnect_signals(_active_ability)
		_active_ability.exit()
		_active_ability = null


## Returns true if the active ability is controlling movement.
func is_active_controlling() -> bool:
	return _active_ability != null and _active_ability.is_active


## Get the currently active ability (or null).
func get_active() -> PlayerAbility:
	return _active_ability


## Get ability by index.
func get_ability(index: int) -> PlayerAbility:
	if index >= 0 and index < _abilities.size():
		return _abilities[index]
	return null


## Get total number of abilities.
func get_count() -> int:
	return _abilities.size()


# -- Private --

## Tries to activate an ability based on input event.
func _try_activate_by_input(event: InputEvent) -> bool:
	for i in range(_abilities.size()):
		var ability := _abilities[i]
		
		# Check if this ability has an activation input property
		if ability.has_method("get") and ability.get("input_grapple") is String:
			var action_name: String = ability.get("input_grapple")
			if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
				if activate(i):
					# Also forward the input to the now-active ability
					ability.input(event)
					return true
	
	return false


## Called when active ability finishes (self-deactivates).
func _on_ability_finished() -> void:
	if _active_ability:
		_disconnect_signals(_active_ability)
		_active_ability = null


## Connect signals for an ability.
func _connect_signals(ability: PlayerAbility) -> void:
	if not ability.ability_finished.is_connected(_on_ability_finished):
		ability.ability_finished.connect(_on_ability_finished)


## Disconnect signals for an ability.
func _disconnect_signals(ability: PlayerAbility) -> void:
	if ability.ability_finished.is_connected(_on_ability_finished):
		ability.ability_finished.disconnect(_on_ability_finished)
