## Test: Player Ability Integration
## GUT unit tests for ability activation, cooldown enforcement, and switching.
## ULTRATHINK: Player requires CharacterBody3D, tests use minimal scene setup.
extends GutTest


# -------------------------------------------------------------------
# Helper: Minimal Player Setup
# -------------------------------------------------------------------

class MockPlayer extends CharacterBody3D:
	## Minimal player for testing ability system.
	## Replicates key exports and methods from player.gd.
	
	@export var ability_templates: Array[PlayerAbility] = []
	
	var _abilities: Array[PlayerAbility] = []
	var _active_ability: PlayerAbility = null
	
	func _ready() -> void:
		for template in ability_templates:
			if template:
				_abilities.append(template.create_instance())
	
	func activate_ability(index: int) -> bool:
		if index < 0 or index >= _abilities.size():
			return false
		
		var ability := _abilities[index]
		if not ability.is_ready():
			return false
		
		if _active_ability:
			if not _active_ability.interruptible:
				return false
			_active_ability.exit()
		
		_active_ability = ability
		_active_ability.enter(self)
		return true
	
	func deactivate_ability() -> void:
		if _active_ability:
			_active_ability.exit()
			_active_ability = null
	
	func get_active_ability() -> PlayerAbility:
		return _active_ability
	
	func get_ability(index: int) -> PlayerAbility:
		if index >= 0 and index < _abilities.size():
			return _abilities[index]
		return null


# -------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------

var _player: MockPlayer


func before_each() -> void:
	_player = MockPlayer.new()
	add_child_autofree(_player)


func after_each() -> void:
	_player = null


# -------------------------------------------------------------------
# Ability Activation Tests
# -------------------------------------------------------------------

func test_activate_ability_with_empty_list_returns_false() -> void:
	var result := _player.activate_ability(0)
	assert_false(result, "No abilities = false")


func test_activate_ability_with_invalid_index_returns_false() -> void:
	var ability := PlayerAbility.new()
	_player._abilities.append(ability)
	
	var result := _player.activate_ability(99)
	assert_false(result, "Invalid index = false")


func test_activate_ability_returns_true_when_ready() -> void:
	var ability := PlayerAbility.new()
	ability.cooldown = 0.0
	_player._abilities.append(ability)
	
	var result := _player.activate_ability(0)
	assert_true(result, "Ready ability activates")


func test_activate_ability_sets_active() -> void:
	var ability := PlayerAbility.new()
	_player._abilities.append(ability)
	
	_player.activate_ability(0)
	
	assert_eq(_player.get_active_ability(), ability)


func test_activate_ability_calls_enter() -> void:
	var ability := PlayerAbility.new()
	_player._abilities.append(ability)
	
	_player.activate_ability(0)
	
	assert_true(ability.is_active, "enter() sets is_active")


# -------------------------------------------------------------------
# Cooldown Enforcement Tests
# -------------------------------------------------------------------

func test_activate_ability_returns_false_on_cooldown() -> void:
	var ability := PlayerAbility.new()
	ability.cooldown = 1.0
	ability.cooldown_remaining = 1.0  # On cooldown
	_player._abilities.append(ability)
	
	var result := _player.activate_ability(0)
	assert_false(result, "Cooldown blocks activation")


func test_ability_becomes_ready_after_cooldown() -> void:
	var ability := PlayerAbility.new()
	ability.cooldown = 1.0
	ability.cooldown_remaining = 1.0
	_player._abilities.append(ability)
	
	# Simulate cooldown expiring
	ability.physics_update(1.0)
	
	assert_true(ability.is_ready())


# -------------------------------------------------------------------
# Deactivation Tests
# -------------------------------------------------------------------

func test_deactivate_ability_clears_active() -> void:
	var ability := PlayerAbility.new()
	_player._abilities.append(ability)
	
	_player.activate_ability(0)
	_player.deactivate_ability()
	
	assert_null(_player.get_active_ability())


func test_deactivate_ability_calls_exit() -> void:
	var ability := PlayerAbility.new()
	_player._abilities.append(ability)
	
	_player.activate_ability(0)
	assert_true(ability.is_active)
	
	_player.deactivate_ability()
	assert_false(ability.is_active, "exit() clears is_active")


func test_deactivate_when_no_active_is_safe() -> void:
	_player.deactivate_ability()
	pass_test("No crash when no active ability")


# -------------------------------------------------------------------
# Ability Switching Tests
# -------------------------------------------------------------------

func test_activate_new_ability_interrupts_previous() -> void:
	var ability1 := PlayerAbility.new()
	ability1.interruptible = true
	var ability2 := PlayerAbility.new()
	_player._abilities.append(ability1)
	_player._abilities.append(ability2)
	
	_player.activate_ability(0)
	assert_eq(_player.get_active_ability(), ability1)
	
	_player.activate_ability(1)
	assert_eq(_player.get_active_ability(), ability2)
	assert_false(ability1.is_active, "Previous ability deactivated")


func test_non_interruptible_ability_blocks_switch() -> void:
	var ability1 := PlayerAbility.new()
	ability1.interruptible = false
	var ability2 := PlayerAbility.new()
	_player._abilities.append(ability1)
	_player._abilities.append(ability2)
	
	_player.activate_ability(0)
	var result := _player.activate_ability(1)
	
	assert_false(result, "Non-interruptible blocks switch")
	assert_eq(_player.get_active_ability(), ability1, "Still active")


func test_switch_to_same_ability_reactivates() -> void:
	var ability := PlayerAbility.new()
	ability.interruptible = true
	_player._abilities.append(ability)
	
	_player.activate_ability(0)
	ability.is_active = false  # Simulate exit
	
	_player.activate_ability(0)
	assert_true(ability.is_active, "Re-entered")


# -------------------------------------------------------------------
# Get Ability Tests
# -------------------------------------------------------------------

func test_get_ability_returns_correct_instance() -> void:
	var ability1 := PlayerAbility.new()
	ability1.display_name = "First"
	var ability2 := PlayerAbility.new()
	ability2.display_name = "Second"
	_player._abilities.append(ability1)
	_player._abilities.append(ability2)
	
	assert_eq(_player.get_ability(0).display_name, "First")
	assert_eq(_player.get_ability(1).display_name, "Second")


func test_get_ability_invalid_index_returns_null() -> void:
	assert_null(_player.get_ability(-1))
	assert_null(_player.get_ability(100))


# -------------------------------------------------------------------
# Multiple Abilities State Isolation
# -------------------------------------------------------------------

func test_abilities_have_independent_cooldowns() -> void:
	var ability1 := PlayerAbility.new()
	ability1.cooldown = 1.0
	var ability2 := PlayerAbility.new()
	ability2.cooldown = 2.0
	_player._abilities.append(ability1)
	_player._abilities.append(ability2)
	
	ability1.start_cooldown()
	
	assert_eq(ability1.cooldown_remaining, 1.0)
	assert_eq(ability2.cooldown_remaining, 0.0, "Unaffected by ability1")


func test_ability_finish_signal_emitted() -> void:
	var ability := PlayerAbility.new()
	_player._abilities.append(ability)
	
	_player.activate_ability(0)
	
	watch_signals(ability)
	_player.deactivate_ability()
	
	assert_signal_emitted(ability, "ability_finished")
