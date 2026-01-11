## ProtoInputHandler
## Handles input mapping validation for ProtoController.
## Extracted to reduce complexity in proto_controller.gd.
class_name ProtoInputHandler
extends RefCounted


## Mapping configuration structure
class MappingConfig:
	var action_name: String
	var feature_name: String
	var feature_enabled_ref: String  # Name of property to disable if missing
	
	func _init(action: String, feature: String, enabled_ref: String) -> void:
		action_name = action
		feature_name = feature
		feature_enabled_ref = enabled_ref


## Validates all input mappings exist in InputMap.
## Returns a dictionary of features that should be disabled.
## @param controller: The ProtoController to validate mappings for
## @return Dictionary: {feature_name: bool} - which features should be disabled
static func validate_mappings(controller: CharacterBody3D) -> Dictionary:
	var disabled := {}
	
	# Movement mappings
	if controller.can_move:
		disabled["can_move"] = not _check_movement_actions(controller)
	
	# Jump mapping
	if controller.can_jump:
		if not InputMap.has_action(controller.input_jump):
			push_error("Jumping disabled. No InputAction found for input_jump: " + controller.input_jump)
			disabled["can_jump"] = true
	
	# Sprint mapping
	if controller.can_sprint:
		if not InputMap.has_action(controller.input_sprint):
			push_error("Sprinting disabled. No InputAction found for input_sprint: " + controller.input_sprint)
			disabled["can_sprint"] = true
	
	# Freefly mapping
	if controller.can_freefly:
		if not InputMap.has_action(controller.input_freefly):
			push_error("Freefly disabled. No InputAction found for input_freefly: " + controller.input_freefly)
			disabled["can_freefly"] = true
	
	return disabled


## Checks all movement input actions exist.
## @return bool: True if all movement actions exist
static func _check_movement_actions(controller: CharacterBody3D) -> bool:
	var actions := [
		["input_left", controller.input_left],
		["input_right", controller.input_right],
		["input_forward", controller.input_forward],
		["input_back", controller.input_back],
	]
	
	for pair in actions:
		var prop_name: String = pair[0]
		var action_name: String = pair[1]
		if not InputMap.has_action(action_name):
			push_error("Movement disabled. No InputAction found for %s: %s" % [prop_name, action_name])
			return false
	
	return true


## Applies disabled features dictionary to controller.
static func apply_disabled_features(controller: CharacterBody3D, disabled: Dictionary) -> void:
	if disabled.get("can_move", false):
		controller.can_move = false
	if disabled.get("can_jump", false):
		controller.can_jump = false
	if disabled.get("can_sprint", false):
		controller.can_sprint = false
	if disabled.get("can_freefly", false):
		controller.can_freefly = false
