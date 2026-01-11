## MeshBuilder
## Static utility for generating ArrayMesh data from voxel arrays.
## All methods are pure functions suitable for threading.
class_name MeshBuilder
extends RefCounted


# -- Face Vertices --
# Pre-computed vertex offsets for each face (v0, v1, v2, v3 in winding order)
const FACE_VERTICES := {
	BlockDefinitions.Face.POS_X: [Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, -0.5, -0.5)],
	BlockDefinitions.Face.NEG_X: [Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, -0.5, 0.5)],
	BlockDefinitions.Face.POS_Y: [Vector3(-0.5, 0.5, 0.5), Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5)],
	BlockDefinitions.Face.NEG_Y: [Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, -0.5, -0.5)],
	BlockDefinitions.Face.POS_Z: [Vector3(-0.5, -0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, -0.5, 0.5)],
	BlockDefinitions.Face.NEG_Z: [Vector3(0.5, -0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, -0.5, -0.5)],
}

const FACE_NORMALS := {
	BlockDefinitions.Face.POS_X: Vector3.RIGHT,
	BlockDefinitions.Face.NEG_X: Vector3.LEFT,
	BlockDefinitions.Face.POS_Y: Vector3.UP,
	BlockDefinitions.Face.NEG_Y: Vector3.DOWN,
	BlockDefinitions.Face.POS_Z: Vector3.BACK,
	BlockDefinitions.Face.NEG_Z: Vector3.FORWARD,
}


## Adds a quad face to mesh arrays.
## @param arrays: Dictionary with verts, uvs, colors, normals, indices arrays
## @param base_index: Current vertex index
## @param pos: Block world position
## @param face: BlockDefinitions.Face enum value
## @param block_id: Block type for UV lookup
## @param color: Chunk color tint
## @param tiles_per_row: Atlas tile count per row
## @return int: Number of vertices added (always 4)
static func add_face(
	arrays: Dictionary,
	base_index: int,
	pos: Vector3,
	face: int,
	block_id: int,
	color: Color,
	tiles_per_row: int = 2
) -> int:
	var verts: PackedVector3Array = arrays.verts
	var uvs: PackedVector2Array = arrays.uvs
	var colors: PackedColorArray = arrays.colors
	var normals: PackedVector3Array = arrays.normals
	var indices: PackedInt32Array = arrays.indices
	
	var face_verts: Array = FACE_VERTICES[face]
	var normal: Vector3 = FACE_NORMALS[face]
	
	# Add vertices
	for v in face_verts:
		verts.append(pos + v)
	
	# Add normals
	for i in 4:
		normals.append(normal)
	
	# Add colors
	for i in 4:
		colors.append(color)
	
	# Calculate UVs from atlas
	var tile_index: int = 0
	if BlockDefinitions.BLOCK_TILES.has(block_id):
		var face_map: Dictionary = BlockDefinitions.BLOCK_TILES[block_id]
		if face_map.has(face):
			tile_index = face_map[face]
	
	var tile_size: float = 1.0 / tiles_per_row
	var col: int = tile_index % tiles_per_row
	var row: int = tile_index / tiles_per_row
	var base_uv := Vector2(col * tile_size, row * tile_size)
	
	uvs.append(base_uv + Vector2(0, tile_size))
	uvs.append(base_uv + Vector2(0, 0))
	uvs.append(base_uv + Vector2(tile_size, 0))
	uvs.append(base_uv + Vector2(tile_size, tile_size))
	
	# Add indices (two triangles)
	indices.append(base_index + 0)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index + 0)
	indices.append(base_index + 2)
	indices.append(base_index + 3)
	
	return 4


## Creates empty mesh arrays dictionary.
static func create_arrays() -> Dictionary:
	return {
		"verts": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
	}


## Converts internal arrays to Godot mesh format.
static func to_mesh_data(arrays: Dictionary, triangle_count: int) -> Dictionary:
	return {
		"vertices": arrays.verts,
		"uvs": arrays.uvs,
		"colors": arrays.colors,
		"normals": arrays.normals,
		"indices": arrays.indices,
		"triangle_count": triangle_count,
	}
