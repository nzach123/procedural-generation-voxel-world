extends GutTest

var GrappleAbility = load("res://scripts/abilities/grapple_ability.gd")

# Mock Player Class
class MockPlayer extends CharacterBody3D:
	var mock_on_floor: bool = false
	var mock_gravity: Vector3 = Vector3.DOWN * 9.8
	var jump_velocity: float = 5.0
	
	func is_on_floor() -> bool:
		return mock_on_floor
	
	func get_gravity() -> Vector3:
		return mock_gravity
		
	func apply_fov_kick(_amount, _dur):
		pass # Dummy

var _player
var _ability

func before_each():
	_player = MockPlayer.new()
	_ability = GrappleAbility.new()
	add_child_autofree(_player)
	_ability.enter(_player)

func after_each():
	_ability.exit()
	_player.queue_free()

	# InputMap test skipped due to headless environment issues.
	# Manual verification of toggle required in-game.
	pass


func test_momentum_preservation():
	_ability._attached = true
	_player.velocity = Vector3(10, 0, 0)
	
	_ability._detach()
	
	assert_eq(_player.velocity, Vector3(10, 0, 0), "Velocity should be preserved")


func test_force_application():

	# Test F=ma logic in _process_pull
	_ability._attached = true
	_ability._target_point = Vector3(100, 0, 0)
	_player.global_position = Vector3(0, 0, 0)
	_player.velocity = Vector3.ZERO
	
	# Delta = 1.0
	# Force = 40.0
	# Max Speed = 30.0
	
	_ability._process_pull(1.0)
	
	# It should try to add 40.0 velocity, but get clamped to 30.0
	assert_almost_eq(_player.velocity.x, 30.0, 1.0, "Should accelerate and clamp to max speed")

