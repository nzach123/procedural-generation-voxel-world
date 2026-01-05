# 04. Interfaces and APIs

## 1. Public Script APIs

### BlockRegistry (`scripts/singletons/block_registry.gd`)
Global access point for block definitions.

| Method | Inputs | Returns | Description |
| :--- | :--- | :--- | :--- |
| `register_block` | `id: int`, `data: BlockData` | `void` | Registers a new block type. |
| `get_block_data` | `id: int` | `BlockData` | Retrieves the resource for a given ID. |

### ChunkManager (`scripts/chunk_manager.gd`)
Primary controller for the world.

| Method | Inputs | Returns | Description |
| :--- | :--- | :--- | :--- |
| `get_chunk` | `coord: Vector3i` | `Chunk` | Returns the chunk node at the specific grid coordinate. Returns `null` if not loaded. |
| `set_voxel` | `global_pos: Vector3`, `block_id: int` | `void` | High-level API to modify the world at a specific global position. |

### ChunkSerializer (`scripts/chunk_serializer.gd`)
Handles data persistence.

| Method | Inputs | Returns | Description |
| :--- | :--- | :--- | :--- |
| `save_chunk` | `chunk: Chunk` | `void` | Compresses and writes chunk data to `user://save/chunk_X_Y_Z.chk`. |
| `load_chunk` | `coord: Vector3i` | `PackedByteArray` | Reads and decompresses chunk data from disk. Returns null if missing. |

### InteractionContext (`scripts/resources/interaction_context.gd`)
State container for player tools.

| Field | Type | Description |
| :--- | :--- | :--- |
| `selected_block_id` | `int` | ID of the block to place. |
| `brush_radius` | `int` | Size of the modification sphere (default 1). |

### Chunk (`scripts/chunk.gd`)
Low-level unit access.

| Method | Inputs | Returns | Description |
| :--- | :--- | :--- | :--- |
| `get_voxel` | `local_x: int, local_y: int, local_z: int` | `int` | Returns the block ID at local coordinates using the flat index formula. |
| `_generate_mesh` | `void` | `void` | Triggers the mesh generation pipeline (internal). |

## 2. Input Map
The system listens for the following abstract input actions:

| Action Name | Type | Keybind (Default) | Description |
| :--- | :--- | :--- | :--- |
| `move_forward` | Axis | `W` | Player movement. |
| `move_back` | Axis | `S` | Player movement. |
| `move_left` | Axis | `A` | Player movement. |
| `move_right` | Axis | `D` | Player movement. |
| `jump` | Button | `Space` | Player jump. |
| `attack` | Button | `Left Mouse Button` | Destroy block (set to air). |
| `interact` | Button | `Right Mouse Button` | Place block. |

## 3. Events / Signals
*(Future implementation may include signals for ChunkLoaded or VoxelChanged, currently handled via direct method calls)*
