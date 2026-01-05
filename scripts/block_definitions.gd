## BlockDefinitions
## Legacy compatibility layer providing block types and face enums.
## Will be deprecated in favor of BlockRegistry + BlockData resources.
extends Node


## Block type enum - maps to byte values in voxel storage.
enum BlockType {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
}


## Face direction enum for texture mapping.
enum Face {
	POS_X = 0,
	NEG_X = 1,
	POS_Y = 2,
	NEG_Y = 3,
	POS_Z = 4,
	NEG_Z = 5,
}


## Tile indices for each block type and face.
## Format: BLOCK_TILES[BlockType][Face] -> tile_index
const BLOCK_TILES: Dictionary = {
	BlockType.AIR: {},
	BlockType.GRASS: {
		Face.POS_X: 0,
		Face.NEG_X: 0,
		Face.POS_Y: 1,
		Face.NEG_Y: 2,
		Face.POS_Z: 0,
		Face.NEG_Z: 0,
	},
	BlockType.DIRT: {
		Face.POS_X: 2,
		Face.NEG_X: 2,
		Face.POS_Y: 2,
		Face.NEG_Y: 2,
		Face.POS_Z: 2,
		Face.NEG_Z: 2,
	},
	BlockType.STONE: {
		Face.POS_X: 3,
		Face.NEG_X: 3,
		Face.POS_Y: 3,
		Face.NEG_Y: 3,
		Face.POS_Z: 3,
		Face.NEG_Z: 3,
	},
}
