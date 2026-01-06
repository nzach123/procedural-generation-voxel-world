
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and mouse_captured:
		if not _active_ability:
			_handle_block_delete()
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and mouse_captured:
		if not _active_ability:
			_handle_block_place()
			
	if event.is_action_pressed(input_freefly):
		freeflying = !freeflying
		collider.disabled = freeflying
		
		if freeflying:
			velocity = Vector3.ZERO
	
	# DEBUG: Inspect chunk under player
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
			var chunk = chunk_manager.get_chunk_at_world_pos(global_position)
			if chunk:
				print("--- CHUNK INSPECTOR ---")
				print("Chunk: ", chunk.key)
				print("Offset: ", chunk.chunk_offset)
				print("Collision enabled: ", chunk.is_collision_enabled())
				if chunk.has_method("_get_mesh_instance_rid"):
					print("Mesh RID: ", chunk._get_mesh_instance_rid())
			else:
				print("--- CHUNK INSPECTOR: No chunk found at ", global_position)
