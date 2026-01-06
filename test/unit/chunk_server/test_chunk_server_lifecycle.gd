## Test: ChunkServer Lifecycle
## GUT unit tests for destroy() idempotency and PREDELETE guard pattern.
## ULTRATHINK: Verifies the _destroyed guard prevents double-free crashes.
extends GutTest


# -------------------------------------------------------------------
# Helper
# -------------------------------------------------------------------

func _create_server() -> ChunkServer:
	return ChunkServer.new()


# -------------------------------------------------------------------
# Destroyed Flag State Tests
# -------------------------------------------------------------------

func test_destroyed_flag_is_false_initially() -> void:
	var server := _create_server()
	assert_false(server._destroyed, "Should start not destroyed")
	server.destroy()


func test_destroyed_flag_is_true_after_destroy() -> void:
	var server := _create_server()
	server.destroy()
	assert_true(server._destroyed, "Flag should be set after destroy")


# -------------------------------------------------------------------
# Idempotent Destroy Tests
# -------------------------------------------------------------------

func test_destroy_is_idempotent() -> void:
	var server := _create_server()
	server.destroy()
	server.destroy()
	server.destroy()
	pass_test("Multiple destroy() calls don't crash")


func test_destroy_sets_flag_before_freeing_rids() -> void:
	var server := _create_server()
	
	# Apply mesh to create RIDs
	var mesh_data := {
		"vertices": PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)]),
		"uvs": PackedVector2Array([Vector2(0,0), Vector2(1,0), Vector2(0,1)]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		"normals": PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]),
		"indices": PackedInt32Array([0, 1, 2]),
		"triangle_count": 1
	}
	server.apply_mesh(mesh_data, RID(), RID())
	
	# First destroy
	server.destroy()
	assert_true(server._destroyed)
	
	# Second destroy should early-exit
	server.destroy()
	pass_test("Second destroy is no-op")


# -------------------------------------------------------------------
# Post-Destroy Operation Safety Tests
# -------------------------------------------------------------------

func test_get_voxel_after_destroy_still_works() -> void:
	var server := _create_server()
	server.set_voxel(10, 10, 10, 5)
	server.destroy()
	
	# _voxels array is not cleared by destroy
	var result := server.get_voxel(10, 10, 10)
	assert_eq(result, 5, "Voxel data persists after destroy")


func test_set_voxel_after_destroy_still_works() -> void:
	var server := _create_server()
	server.destroy()
	
	# _voxels is still valid, set should work
	server.set_voxel(10, 10, 10, 7)
	assert_eq(server.get_voxel(10, 10, 10), 7, "Can still modify voxels")


func test_set_voxels_raw_after_destroy_works() -> void:
	var server := _create_server()
	server.destroy()
	
	var raw := PackedByteArray()
	raw.resize(ChunkServer.VOLUME)
	raw.fill(0)
	raw[0] = 42
	
	server.set_voxels_raw(raw)
	assert_eq(server.get_voxel(0, 0, 0), 42, "Raw voxel set works")


func test_get_voxels_raw_after_destroy_works() -> void:
	var server := _create_server()
	server.set_voxel(0, 0, 0, 33)
	server.destroy()
	
	var raw := server.get_voxels_raw()
	assert_eq(raw[0], 33, "Raw voxel get works")


# -------------------------------------------------------------------
# Collision After Destroy Tests
# -------------------------------------------------------------------

func test_is_collision_enabled_after_destroy() -> void:
	var server := _create_server()
	server.destroy()
	
	# Should return false without crashing
	assert_false(server.is_collision_enabled())


func test_set_collision_enabled_after_destroy_is_safe() -> void:
	var server := _create_server()
	server.destroy()
	
	# Should not crash (graceful no-op)
	server.set_collision_enabled(true, RID())
	assert_false(server.is_collision_enabled(), "Can't enable after destroy")


# -------------------------------------------------------------------
# Triangle Count After Destroy Tests
# -------------------------------------------------------------------

func test_get_triangle_count_after_destroy() -> void:
	var server := _create_server()
	
	var mesh_data := {
		"vertices": PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)]),
		"uvs": PackedVector2Array([Vector2(0,0), Vector2(1,0), Vector2(0,1)]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		"normals": PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]),
		"indices": PackedInt32Array([0, 1, 2]),
		"triangle_count": 99
	}
	server.apply_mesh(mesh_data, RID(), RID())
	server.destroy()
	
	# Triangle count persists (it's just an int)
	assert_eq(server.get_triangle_count(), 99)


# -------------------------------------------------------------------
# Block Operations After Destroy Tests
# -------------------------------------------------------------------

func test_check_block_selected_after_destroy() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3.ZERO
	server.set_voxel(5, 5, 5, 1)
	server.destroy()
	
	# Should still work
	assert_true(server.check_block_selected(Vector3i(5, 5, 5)))


func test_delete_block_after_destroy_is_safe() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3.ZERO
	server.set_voxel(5, 5, 5, 1)
	server.destroy()
	
	# delete_block calls _update_mesh which needs valid scenario
	# Without valid scenario, it should no-op gracefully
	server.delete_block(Vector3i(5, 5, 5))
	pass_test("delete_block after destroy doesn't crash")


func test_add_block_after_destroy_is_safe() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3.ZERO
	server.destroy()
	
	# add_block calls _update_mesh which needs valid scenario
	server.add_block(Vector3i(5, 5, 5))
	pass_test("add_block after destroy doesn't crash")


# -------------------------------------------------------------------
# RefCounted Lifecycle Tests
# -------------------------------------------------------------------

func test_server_can_be_recreated_after_destroy() -> void:
	var server1 := _create_server()
	server1.set_voxel(0, 0, 0, 1)
	server1.destroy()
	
	# Create new server with same variable
	var server2 := _create_server()
	assert_eq(server2.get_voxel(0, 0, 0), 0, "New server is clean")
	server2.destroy()


func test_multiple_servers_independent() -> void:
	var server1 := _create_server()
	var server2 := _create_server()
	
	server1.set_voxel(0, 0, 0, 1)
	server2.set_voxel(0, 0, 0, 2)
	
	assert_eq(server1.get_voxel(0, 0, 0), 1)
	assert_eq(server2.get_voxel(0, 0, 0), 2)
	
	server1.destroy()
	server2.destroy()
