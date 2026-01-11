## ChunkCollisionBuilder
## Handles creation of collision shapes for chunk meshes.
## Extracted from ChunkServer to reduce file line count.
class_name ChunkCollisionBuilder
extends RefCounted


## Builds a collision body and trimesh shape from mesh arrays.
## @param mesh_arrays: Array of mesh surface data (vertices, normals, etc.)
## @param space: Physics space RID to add the body to
## @param collision_layer: Layer bits for collision
## @param collision_mask: Mask bits for collision
## @return Dictionary: { body_rid: RID, shape_rid: RID, shape: ConcavePolygonShape3D }
static func build_collision(
	mesh_arrays: Array,
	space: RID,
	collision_layer: int,
	collision_mask: int
) -> Dictionary:
	var result := {
		"body_rid": RID(),
		"shape_rid": RID(),
		"shape": null
	}
	
	if mesh_arrays.is_empty():
		return result
	
	# Create trimesh shape from mesh arrays
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	var shape := mesh.create_trimesh_shape()
	
	if shape == null:
		return result
	
	result["shape"] = shape
	result["shape_rid"] = shape.get_rid()
	
	# Create static body
	var body_rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body_rid, space)
	PhysicsServer3D.body_add_shape(body_rid, result["shape_rid"])
	PhysicsServer3D.body_set_state(
		body_rid, 
		PhysicsServer3D.BODY_STATE_TRANSFORM,
		# Use IDENTITY because mesh vertices already have world offset baked in
		Transform3D.IDENTITY
	)
	
	# Configure collision layers
	PhysicsServer3D.body_set_collision_layer(body_rid, collision_layer)
	PhysicsServer3D.body_set_collision_mask(body_rid, collision_mask)
	
	result["body_rid"] = body_rid
	return result
