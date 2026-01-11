extends "res://addons/gut/test.gd"

var ProtoController = load("res://scenes/proto_controller/proto_controller.gd")
var controller

func before_each():
	controller = ProtoController.new()
	controller.acceleration = 10.0
	controller.friction = 6.0
	controller.air_acceleration = 100.0
	controller.max_speed_ground = 7.0
	controller.max_speed_air = 2.0
	controller.jump_velocity = 4.5
	controller.velocity = Vector3.ZERO

func after_each():
	controller.free()

func test_ground_acceleration():
	var wish_dir = Vector3(0, 0, -1)
	var wish_speed = 7.0
	var delta = 0.016
	
	controller._handle_ground_physics(wish_dir, wish_speed, delta)
	
	var expected_z = -1.12
	assert_almost_eq(controller.velocity.z, expected_z, 0.1, "Should accelerate partially")

func test_ground_friction():
	# Moving forward at max speed
	controller.velocity = Vector3(0, 0, -7)
	var delta = 0.016
	
	# Stop input
	controller._handle_ground_physics(Vector3.ZERO, 0.0, delta)
	
	# _apply_friction:
	# speed = 7.0. control = 7.0.
	# drop = 7.0 * 6.0 * 0.016 = 0.672
	# new_speed = 7.0 - 0.672 = 6.328
	
	var expected_speed = 6.328
	var current_speed = controller.velocity.length()
	
	assert_almost_eq(current_speed, expected_speed, 0.1, "Should slow down due to friction")
	assert_lt(current_speed, 7.0, "Speed should decrease")

func test_air_strafing():
	# Moving forward
	controller.velocity = Vector3(0, 0, -7)
	
	# Wish to move Left (X-)
	var wish_dir = Vector3(-1, 0, 0)
	var wish_speed = 7.0
	var delta = 0.016
	
	# in Air
	controller._handle_air_physics(wish_dir, wish_speed, delta)
	
	# Logic:
	# final_air_speed = min(7, 2) = 2.0
	# accel_speed = 100 * 0.016 * 2.0 = 3.2
	# add_speed = 2.0 - 0 = 2.0
	# accel_speed clamped to 2.0
	# velocity.x += 2.0 * -1 = -2.0
	
	assert_eq(controller.velocity.z, -7.0, "Z velocity should be conserved")
	assert_almost_eq(controller.velocity.x, -2.0, 0.1, "Should gain X velocity from strafe")
	assert_gt(controller.velocity.length(), 7.0, "Should gain speed from air strafing")
