## Test: PlayerAbility
## GUT unit tests for ability.gd base class.
extends GutTest


# -------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------

var _ability: PlayerAbility = null


func before_each() -> void:
	_ability = PlayerAbility.new()


func after_each() -> void:
	_ability = null


# -------------------------------------------------------------------
# Default Values Tests
# -------------------------------------------------------------------

func test_default_display_name() -> void:
	assert_eq(_ability.display_name, "Ability")


func test_default_cooldown() -> void:
	assert_eq(_ability.cooldown, 0.0)


func test_default_interruptible() -> void:
	assert_true(_ability.interruptible)


func test_default_is_active() -> void:
	assert_false(_ability.is_active)


func test_default_cooldown_remaining() -> void:
	assert_eq(_ability.cooldown_remaining, 0.0)


# -------------------------------------------------------------------
# Lifecycle Tests
# -------------------------------------------------------------------

func test_enter_sets_player_and_active() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	
	assert_eq(_ability.player, mock_player)
	assert_true(_ability.is_active)


func test_exit_clears_active_and_emits_signal() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	
	watch_signals(_ability)
	_ability.exit()
	
	assert_false(_ability.is_active)
	assert_signal_emitted(_ability, "ability_finished")


func test_physics_update_decrements_cooldown() -> void:
	_ability.cooldown_remaining = 1.0
	
	_ability.physics_update(0.5)
	
	assert_eq(_ability.cooldown_remaining, 0.5)


func test_physics_update_clamps_cooldown_to_zero() -> void:
	_ability.cooldown_remaining = 0.3
	
	_ability.physics_update(0.5)
	
	assert_eq(_ability.cooldown_remaining, 0.0)


func test_input_returns_false_by_default() -> void:
	var event := InputEventKey.new()
	assert_false(_ability.input(event))


# -------------------------------------------------------------------
# Cooldown Tests
# -------------------------------------------------------------------

func test_is_ready_when_no_cooldown() -> void:
	assert_true(_ability.is_ready())


func test_is_ready_false_when_on_cooldown() -> void:
	_ability.cooldown_remaining = 1.0
	assert_false(_ability.is_ready())


func test_start_cooldown_sets_remaining() -> void:
	_ability.cooldown = 2.5
	_ability.start_cooldown()
	assert_eq(_ability.cooldown_remaining, 2.5)


# -------------------------------------------------------------------
# State Isolation Tests
# -------------------------------------------------------------------

func test_clear_state_clears_all() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	_ability.cooldown_remaining = 5.0
	
	_ability.clear_state()
	
	assert_null(_ability.player)
	assert_eq(_ability.cooldown_remaining, 0.0)
	assert_false(_ability.is_active)


func test_create_instance_returns_deep_duplicate() -> void:
	_ability.display_name = "Test"
	_ability.cooldown = 3.0
	
	var instance := _ability.create_instance()
	
	assert_not_null(instance)
	assert_ne(instance, _ability, "Should be different object")
	assert_eq(instance.display_name, "Test")
	assert_eq(instance.cooldown, 3.0)


func test_duplicate_state_is_isolated() -> void:
	var ability1 := PlayerAbility.new()
	var ability2 := ability1.create_instance()
	
	ability1.cooldown_remaining = 10.0
	
	assert_eq(ability2.cooldown_remaining, 0.0, "Duplicated ability should have independent state")


func test_ability_is_resource() -> void:
	assert_true(_ability is Resource)
