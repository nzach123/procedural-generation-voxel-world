## BlockInteraction
## Handles voxel block interaction (delete/place/select) for player controllers.
## Static utility extracted from proto_controller to reduce file size.
class_name BlockInteraction
extends RefCounted


## Calculates the block coordinates that a raycast hit.
## @param point: Raycast hit point in world space
## @param normal: Surface normal at hit point
## @return Vector3i: Block coordinates
static func get_hit_block(point: Vector3, normal: Vector3) -> Vector3i:
	return Vector3i(
		roundi(point.x - normal.x * 0.5),
		roundi(point.y - normal.y * 0.5),
		roundi(point.z - normal.z * 0.5)
	)


## Calculates the adjacent block coordinates (for placement).
## @param point: Raycast hit point in world space
## @param normal: Surface normal at hit point
## @return Vector3i: Adjacent block coordinates
static func get_adjacent_block(point: Vector3, normal: Vector3) -> Vector3i:
	return Vector3i(
		roundi(point.x + normal.x * 0.5),
		roundi(point.y + normal.y * 0.5),
		roundi(point.z + normal.z * 0.5)
	)


## Checks if placing a block would overlap with the player.
## @param block_coords: Block position to check
## @param player_pos: Player's global position
## @return bool: True if overlapping
static func check_player_overlap(block_coords: Vector3i, player_pos: Vector3) -> bool:
	var bx := float(block_coords.x)
	var by := float(block_coords.y)
	var bz := float(block_coords.z)
	
	var overlap_x: bool = abs(player_pos.x - bx) < VoxelConstants.PLAYER_HALF_WIDTH
	var overlap_y: bool = abs(player_pos.y - by) < VoxelConstants.PLAYER_HEIGHT
	var overlap_z: bool = abs(player_pos.z - bz) < VoxelConstants.PLAYER_HALF_WIDTH
	
	return overlap_x and overlap_y and overlap_z


## Deletes a block from a raycast hit.
## @param raycast: The RayCast3D node with collision data
## @param chunk_manager: Reference to ChunkManager
static func delete_block_from_raycast(raycast: RayCast3D, chunk_manager: Node) -> void:
	if not raycast.is_colliding():
		return
	
	var point: Vector3 = raycast.get_collision_point()
	var normal: Vector3 = raycast.get_collision_normal()
	var hit_pos: Vector3 = point - (normal * VoxelConstants.RAYCAST_INSET)
	
	if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
		var chunk: RefCounted = chunk_manager.get_chunk_at_world_pos(hit_pos)
		if chunk and chunk.has_method("delete_block"):
			var block_coords: Vector3i = get_hit_block(point, normal)
			chunk.delete_block(block_coords)


## Places a block from a raycast hit.
## @param raycast: The RayCast3D node with collision data
## @param chunk_manager: Reference to ChunkManager
## @param player: Player node for overlap resolution
## @return bool: True if block was placed
static func place_block_from_raycast(raycast: RayCast3D, chunk_manager: Node, player: CharacterBody3D) -> bool:
	if not raycast.is_colliding():
		return false
	
	var point: Vector3 = raycast.get_collision_point()
	var normal: Vector3 = raycast.get_collision_normal()
	var block_coords: Vector3i = get_adjacent_block(point, normal)
	var place_pos: Vector3 = Vector3(block_coords.x, block_coords.y, block_coords.z)
	
	if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
		var chunk: RefCounted = chunk_manager.get_chunk_at_world_pos(place_pos)
		if chunk and chunk.has_method("add_block"):
			# Check for player overlap
			if check_player_overlap(block_coords, player.global_position):
				if normal == Vector3.UP:
					var collision: KinematicCollision3D = player.move_and_collide(Vector3.UP)
					if collision != null:
						return false
				else:
					return false
			chunk.add_block(block_coords)
			return true
	return false


## Updates block selection highlight from raycast.
## @param raycast: The RayCast3D node
## @param chunk_manager: Reference to ChunkManager
## @param selection_node: Node3D to position at selected block
static func update_selection(raycast: RayCast3D, chunk_manager: Node, selection_node: Node3D) -> void:
	if not raycast.is_colliding():
		selection_node.visible = false
		return
	
	var point: Vector3 = raycast.get_collision_point()
	var normal: Vector3 = raycast.get_collision_normal()
	var block_coords: Vector3i = get_hit_block(point, normal)
	var hit_pos: Vector3 = point - (normal * VoxelConstants.RAYCAST_INSET)
	
	if chunk_manager and chunk_manager.has_method("get_chunk_at_world_pos"):
		var chunk: RefCounted = chunk_manager.get_chunk_at_world_pos(hit_pos)
		if chunk and chunk.has_method("check_block_selected"):
			if chunk.check_block_selected(block_coords):
				selection_node.visible = true
				selection_node.global_position = Vector3(block_coords.x, block_coords.y, block_coords.z)
				return
	
	selection_node.visible = false
