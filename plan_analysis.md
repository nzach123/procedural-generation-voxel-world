# Plan Analysis: Voxel Terrain System v2.1

## Core Objectives
1.  **High-Performance Procedural Gen:** 32x32x32 chunks generated on background threads.
2.  **Scalable Rendering:** Direct ArrayMesh manipulation, fallback to RenderingServer.
3.  **Persistence:** RLE-compressed binary storage.
4.  **Modifiability:** Runtime voxel manipulation via helper interaction contexts.

## Data Flow Analysis
-   **User Input** \> `InteractionContext` \> `VoxelInteraction` \> `ChunkManager`.
-   `ChunkManager` \> `WorkerThreadPool` \> `Chunk` Data Generation \> `PackedByteArray`.
-   `Chunk` Data \> `WorkerThreadPool` \> `Meshing` Algorithm \> `RenderingServer`.
-   `Chunk` Data \> `ChunkSerializer` \> Disk (`.chk`).

## Risks & Mitigations
| Risk | Severity | Mitigation |
| :--- | :--- | :--- |
| **Thread Safety** | High | Strict separation of "Data Gen" (Thread) and "Node/Scene" updates (Main). `call_deferred` is critical. |
| **GDScript Performance** | Medium | Heavy loops in GDScript for 32^3 volumes (32k iterations) can be slow. Mitigation: Use Typed GDScript (`: int`, `: float`) strictly. |
| **Memory Fragmentation** | Low | `PackedByteArray` mitigates this, but frequent resizing of dynamic mesh arrays `resize()` needs management. |
| **Complexity Overload** | Medium | The separation of Rendering, Physics, and Data into different pipelines increases cognitive load. Agents must stick to their specific domains. |

## Optimizations
1.  **Shared Arrays:** Reuse a single global `PackedVector3Array` buffer for meshing on the thread to avoid allocation overhead, clearing it between chunks.
2.  **Lazy Physics:** Do not generate collision shapes for chunks > 20 meters away from the player.
