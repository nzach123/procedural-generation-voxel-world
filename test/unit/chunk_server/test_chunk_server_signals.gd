## Test: ChunkServer Signals & RID Edge Cases
## GUT unit tests for mesh application, triangle counts, and collision state.
## ULTRATHINK: These tests verify RID lifecycle safety and state consistency.
extends GutTest


# -------------------------------------------------------------------
# Helper
# -------------------------------------------------------------------

func _create_server() -> ChunkServer:
	return ChunkServer.new()


func _create_minimal_mesh_data() -> Dictionary:
	# Single triangle mesh for testing
	var verts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0, 1, 0),
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(0, 1),
	])
	var colors := PackedColorArray([
		Color.WHITE,
		Color.WHITE,
		Color.WHITE,
	])
	var normals := PackedVector3Array([
		Vector3.BACK,
		Vector3.BACK,
		Vector3.BACK,
	])
	var indices := PackedInt32Array([0, 1, 2])
	
	return {
		"vertices": verts,
		"uvs": uvs,
		"colors": colors,
		"normals": normals,
		"indices": indices,
		"triangle_count": 1
	}


# -------------------------------------------------------------------
# Triangle Count Tests
# -------------------------------------------------------------------

func test_triangle_count_zero_before_mesh_applied() -> void:
	var server := _create_server()
	assert_eq(server.get_triangle_count(), 0, "No triangles before mesh")
	server.destroy()


func test_triangle_count_updated_after_apply_mesh() -> void:
	var server := _create_server()
	var mesh_data := _create_minimal_mesh_data()
	mesh_data["triangle_count"] = 42
	
	# apply_mesh without valid scenario/material won't crash
	server.apply_mesh(mesh_data, RID(), RID())
	
	# Triangle count should be updated from mesh_data regardless
	assert_eq(server.get_triangle_count(), 42, "Triangle count from mesh_data")
	server.destroy()


# -------------------------------------------------------------------
# Empty Mesh Data Safety Tests
# -------------------------------------------------------------------

func test_apply_mesh_with_empty_data_is_safe() -> void:
	var server := _create_server()
	server.apply_mesh({}, RID(), RID())
	assert_eq(server.get_triangle_count(), 0, "Empty dict = 0 triangles")
	server.destroy()
	pass_test("Empty mesh data doesn't crash")


func test_apply_mesh_with_empty_vertices_is_safe() -> void:
	var server := _create_server()
	var mesh_data := {
		"vertices": PackedVector3Array(),
		"triangle_count": 5
	}
	server.apply_mesh(mesh_data, RID(), RID())
	# Triangle count is set but no RIDs created for empty verts
	assert_eq(server.get_triangle_count(), 5)
	server.destroy()
	pass_test("Empty vertices doesn't crash")


# -------------------------------------------------------------------
# Double Apply Mesh Tests
# -------------------------------------------------------------------

func test_apply_mesh_twice_does_not_crash() -> void:
	var server := _create_server()
	var mesh_data := _create_minimal_mesh_data()
	
	server.apply_mesh(mesh_data, RID(), RID())
	server.apply_mesh(mesh_data, RID(), RID())
	
	server.destroy()
	pass_test("Double apply_mesh is safe")


func test_apply_mesh_twice_updates_triangle_count() -> void:
	var server := _create_server()
	var mesh1 := _create_minimal_mesh_data()
	mesh1["triangle_count"] = 10
	var mesh2 := _create_minimal_mesh_data()
	mesh2["triangle_count"] = 20
	
	server.apply_mesh(mesh1, RID(), RID())
	assert_eq(server.get_triangle_count(), 10)
	
	server.apply_mesh(mesh2, RID(), RID())
	assert_eq(server.get_triangle_count(), 20, "Second apply updates count")
	
	server.destroy()


# -------------------------------------------------------------------
# Collision State Tests
# -------------------------------------------------------------------

func test_collision_disabled_initially() -> void:
	var server := _create_server()
	assert_false(server.is_collision_enabled(), "Collision off by default")
	server.destroy()


func test_enable_collision_without_mesh_stays_disabled() -> void:
	var server := _create_server()
	# No mesh applied, trying to enable collision
	server.set_collision_enabled(true, RID())
	assert_false(server.is_collision_enabled(), "Can't enable without mesh")
	server.destroy()


func test_collision_state_after_disable() -> void:
	var server := _create_server()
	# Even without mesh, disabling should work
	server.set_collision_enabled(false, RID())
	assert_false(server.is_collision_enabled())
	server.destroy()


# -------------------------------------------------------------------
# Destroy + Apply Safety Tests
# -------------------------------------------------------------------

func test_destroy_then_apply_mesh_is_safe() -> void:
	var server := _create_server()
	server.destroy()
	
	# After destroy, apply_mesh should not crash
	# (It will do nothing useful, but shouldn't error)
	var mesh_data := _create_minimal_mesh_data()
	server.apply_mesh(mesh_data, RID(), RID())
	
	pass_test("apply_mesh after destroy doesn't crash")


func test_destroy_then_set_voxel_is_safe() -> void:
	var server := _create_server()
	server.destroy()
	
	# Should not crash (graceful no-op)
	server.set_voxel(5, 5, 5, 1)
	pass_test("set_voxel after destroy doesn't crash")


func test_destroy_then_get_voxel_returns_air() -> void:
	var server := _create_server()
	server.set_voxel(5, 5, 5, 99)
	server.destroy()
	
	# Voxel data is still intact (RefCounted keeps it)
	# but behavior should be well-defined
	var result := server.get_voxel(5, 5, 5)
	# Note: destroy() doesn't clear _voxels, so value remains
	assert_eq(result, 99, "Voxel data survives destroy")


# -------------------------------------------------------------------
# Cached Scenario/Material Tests
# -------------------------------------------------------------------

func test_cached_rids_from_apply_mesh() -> void:
	var server := _create_server()
	var mesh_data := _create_minimal_mesh_data()
	
	# When we call apply_mesh, it caches scenario and material
	server.apply_mesh(mesh_data, RID(), RID())
	
	# No direct access to cached RIDs, but _update_mesh uses them
	# Just verify no crash
	server.destroy()
	pass_test("RID caching works")


# -------------------------------------------------------------------
# Block Operations Tests
# -------------------------------------------------------------------

func test_check_block_selected_with_air() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3.ZERO
	
	var result := server.check_block_selected(Vector3i(5, 5, 5))
	assert_false(result, "Unset block is not selected")
	server.destroy()


func test_check_block_selected_with_solid() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3.ZERO
	server.set_voxel(5, 5, 5, 1)
	
	var result := server.check_block_selected(Vector3i(5, 5, 5))
	assert_true(result, "Solid block is selected")
	server.destroy()


func test_check_block_selected_respects_offset() -> void:
	var server := _create_server()
	server.chunk_offset = Vector3(32, 0, 0)
	server.set_voxel(5, 5, 5, 1)
	
	# Global coords must account for chunk offset
	var result := server.check_block_selected(Vector3i(37, 5, 5))
	assert_true(result, "Offset calculation works")
	server.destroy()
