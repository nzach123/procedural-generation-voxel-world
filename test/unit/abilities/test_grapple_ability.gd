## Test: GrappleAbility
## GUT unit tests for grapple_ability.gd.
extends GutTest


# -------------------------------------------------------------------
# Setup
# -------------------------------------------------------------------

var _ability: GrappleAbility = null


func before_each() -> void:
	_ability = GrappleAbility.new()


func after_each() -> void:
	_ability = null


# -------------------------------------------------------------------
# Default Values Tests
# -------------------------------------------------------------------

func test_default_display_name() -> void:
	assert_eq(_ability.display_name, "Grapple Hook")


func test_default_cooldown() -> void:
	assert_eq(_ability.cooldown, 0.5)


func test_default_max_range() -> void:
	assert_eq(_ability.max_range, 50.0)


func test_default_pull_speed() -> void:
	assert_eq(_ability.pull_speed, 15.0)


func test_default_release_distance() -> void:
	assert_eq(_ability.release_distance, 2.0)


func test_default_not_attached() -> void:
	assert_false(_ability.is_attached())


func test_default_target_point_zero() -> void:
	assert_eq(_ability.get_target_point(), Vector3.ZERO)


# -------------------------------------------------------------------
# Inheritance Tests
# -------------------------------------------------------------------

func test_extends_player_ability() -> void:
	assert_true(_ability is PlayerAbility)


func test_is_resource() -> void:
	assert_true(_ability is Resource)


# -------------------------------------------------------------------
# Cached Ray Params Tests
# -------------------------------------------------------------------

func test_ray_params_initialized_on_enter() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	# Ray params should be null before enter
	assert_null(_ability._ray_params)
	
	_ability.enter(mock_player)
	
	# Ray params should be initialized after enter
	assert_not_null(_ability._ray_params)
	assert_true(_ability._ray_params is PhysicsRayQueryParameters3D)


func test_ray_params_reused_on_multiple_enters() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	var first_params := _ability._ray_params
	
	_ability.exit()
	_ability.enter(mock_player)
	
	# Should reuse the same params object
	assert_eq(_ability._ray_params, first_params)


func test_ray_params_collision_mask_set() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.collision_mask = 7
	_ability.enter(mock_player)
	
	assert_eq(_ability._ray_params.collision_mask, 7)


# -------------------------------------------------------------------
# State Tests
# -------------------------------------------------------------------

func test_enter_sets_active() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	
	assert_true(_ability.is_active)


func test_exit_clears_attached() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	_ability._attached = true
	_ability._target_point = Vector3(10, 10, 10)
	
	_ability.exit()
	
	assert_false(_ability.is_attached())
	assert_eq(_ability.get_target_point(), Vector3.ZERO)


func test_force_detach_clears_state() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	_ability._attached = true
	_ability._target_point = Vector3(10, 10, 10)
	
	_ability.force_detach()
	
	assert_false(_ability.is_attached())


func test_detach_starts_cooldown() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	_ability._attached = true
	_ability.cooldown = 1.0
	
	_ability.force_detach()
	
	assert_eq(_ability.cooldown_remaining, 1.0)


# -------------------------------------------------------------------
# Signal Tests
# -------------------------------------------------------------------

func test_grapple_detached_signal_on_force_detach() -> void:
	var mock_player := CharacterBody3D.new()
	add_child_autofree(mock_player)
	
	_ability.enter(mock_player)
	_ability._attached = true
	
	watch_signals(_ability)
	_ability.force_detach()
	
	assert_signal_emitted(_ability, "grapple_detached")


# -------------------------------------------------------------------
# Create Instance Tests
# -------------------------------------------------------------------

func test_create_instance_duplicates_settings() -> void:
	_ability.max_range = 100.0
	_ability.pull_speed = 25.0
	
	var instance := _ability.create_instance() as GrappleAbility
	
	assert_not_null(instance)
	assert_eq(instance.max_range, 100.0)
	assert_eq(instance.pull_speed, 25.0)


func test_duplicate_state_isolation() -> void:
	var ability1 := GrappleAbility.new()
	var ability2 := ability1.create_instance() as GrappleAbility
	
	ability1._attached = true
	
	assert_false(ability2._attached)
