# 05. Logic and Workflows

## 1. Workflows

### Chunk Generation Pipeline
This workflow ensures that heavy computational tasks do not block the main render thread.

1.  **Request:** `ChunkManager` identifies a missing chunk at coordinate `C`.
2.  **Thread Dispatch:** `WorkerThreadPool` spawns a task binding `C`.
3.  **Stage A (Data Generation):**
    -   Iterate `x, z` (0..15).
    -   Sample `FastNoiseLite` at global position `(C.x * W + x, C.z * D + z)`.
    -   Iterate `y` (0..63).
    -   Determine Block ID (e.g., if y < height: Dirt, else: Air).
    -   Write to `PackedByteArray`.
4.  **Stage B (Mesh Generation):**
    -   Input: The populated `PackedByteArray`.
    -   Action: Iterate all voxels, perform face culling checks.
    -   Output: `verts`, `indices`, `uvs` arrays.
5.  **Stage C (Apply):**
    -   Deferred Call to Main Thread.
    -   `mesh_instance.mesh.add_surface_from_arrays(...)`.
    -   Create collision shape.

### Terrain Modification Logic
1.  **Input:** Raycast hit at `GlobalPosition` with Normal `N`.
2.  **Adjustment:**
    -   **Place:** `Target = GlobalPosition + (N * 0.5)`
    -   **Break:** `Target = GlobalPosition - (N * 0.5)`
3.  **Coordinate Mapping:** Convert `Target` to `ChunkCoord` and `LocalIdx`.
4.  **Update:** Set voxel ID in memory.
5.  **Regenerate:** Trigger specific chunk mesh rebuild.

## 2. Algorithms

### Coordinate Conversion
Handling infinite negative coordinates requires robust floor logic.

**World to Chunk Coordinate:**
```gdscript
var chunk_x = floor(global_pos.x / CHUNK_WIDTH)
var chunk_z = floor(global_pos.z / CHUNK_DEPTH)
return Vector3i(chunk_x, 0, chunk_z)
```

**World to Local Voxel:**
```gdscript
# Standard modulo can return negative results for negative numbers in some languages.
# Godot's posmod() handles this correctly.
var local_x = posmod(global_pos.x, CHUNK_WIDTH)
var local_z = posmod(global_pos.z, CHUNK_DEPTH)
var local_y = global_pos.y # Y is local to chunk height in this version
return Vector3i(local_x, local_y, local_z)
```

### Greedy Meshing (Simplified)
To optimize draw calls, we perform a basic transparency check before adding faces.
-   Inside Loop `(x, y, z)`:
    -   If `voxel[i] == AIR`: Continue.
    -   Check Neighbor `(x+1, y, z)`:
        -   If `neighbor` is `AIR` or `TRANSPARENT`: Add **Right Face**.
    -   Repeat for all 6 directions.
    -   *Note: Phase 1 does not implement full greedy meshing (combining faces), just face culling.*
