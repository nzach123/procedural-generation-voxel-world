## VoxelConstants - Centralized constants for voxel engine.
## This eliminates magic numbers flagged by the linter.
class_name VoxelConstants
extends RefCounted


# -------------------------------------------------------------------
# Chunk Dimensions
# -------------------------------------------------------------------

## Width/depth of a chunk in voxels (X and Z axes).
const CHUNK_SIZE: int = 32

## Height of a chunk in voxels (Y axis).
const CHUNK_HEIGHT: int = 32

## Width of a section (sub-chunk) in voxels.
const SECTION_SIZE: int = 16

## Total height of a column in voxels.
const COLUMN_HEIGHT: int = 256


# -------------------------------------------------------------------
# Voxel Positioning
# -------------------------------------------------------------------

## Offset to center voxels on grid (half-block offset for mesh vertices).
const VOXEL_OFFSET: float = -0.5


# -------------------------------------------------------------------
# Mesh Building
# -------------------------------------------------------------------

## Number of vertices per face (quad).
const VERTICES_PER_FACE: int = 4

## Number of triangles per face.
const TRIANGLES_PER_FACE: int = 2

## Number of indices per face (2 triangles * 3 vertices).
const INDICES_PER_FACE: int = 6


# -------------------------------------------------------------------
# Collision
# -------------------------------------------------------------------

## Collision layer for terrain chunks.
const TERRAIN_COLLISION_LAYER: int = 1

## Collision mask for player detecting terrain.
const PLAYER_TERRAIN_MASK: int = 1


# -------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------

## Maximum RLE run length (fits in one byte).
const MAX_RLE_RUN: int = 255

## Chunk file header size in bytes.
const CHUNK_HEADER_SIZE: int = 4


# -------------------------------------------------------------------
# Raycast & Physics
# -------------------------------------------------------------------

## Offset for raycasts to hit inside block (prevents edge precision issues).
const RAYCAST_INSET: float = 0.05

## Half chunk distance for collision update threshold.
const COLLISION_UPDATE_THRESHOLD: float = 256.0

## Player hitbox half-width for block overlap detection.
const PLAYER_HALF_WIDTH: float = 0.6

## Player hitbox height for block overlap detection.
const PLAYER_HEIGHT: float = 1.3


# -------------------------------------------------------------------
# Look Limits
# -------------------------------------------------------------------

## Maximum up/down look angle in degrees.
const LOOK_ANGLE_LIMIT: int = 85


# -------------------------------------------------------------------
# Terrain
# -------------------------------------------------------------------

## Max terrain layer for stone (above this = stone, below = grass).
const STONE_LAYER_HEIGHT: int = 15

## Default noise seed.
const DEFAULT_NOISE_SEED: int = 20140114

