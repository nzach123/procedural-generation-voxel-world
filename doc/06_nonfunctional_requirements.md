# 06. Non-Functional Requirements

## 1. Performance
The system is designed for high throughput and low latency.

| Metric | Target | Constraints |
| :--- | :--- | :--- |
| **Frame Rate** | > 60 FPS | Tested on mid-range desktop hardware (e.g., GTX 1060 equivalent). |
| **Draw Calls** | < 1000 | For scene with >100 loaded chunks. Requires merged meshes. |
| **Generation Time** | < 5ms (Main Thread) | All heavy lifting must occur on worker threads. Main thread only uploads arrays. |

*Optimization Note:* If `Node3D` overhead becomes a bottleneck at >500 chunks, the rendering layer will be migrated to use the `RenderingServer` API directly, bypassing the SceneTree.

## 2. Scalability
-   **Memory Usage:** Voxel data should be tightly packed. Avoid Python/GDScript lists for voxel storage. Use `PackedByteArray`.
-   **World Size:** Infinite on X/Z axes. Key constraint is floating point precision at extreme distances (Godot uses 32-bit float for vectors, precision issues > 100km).

## 3. Reliability
-   **Thread Safety:** The `ChunkManager` must guard `active_chunks` dictionary access if modified by multiple threads (though refined design defaults to Main Thread ownership of logic, Threads ownership of calculation).
-   **Crash Prevention:** `get_voxel` must include bounds checking to prevent index-out-of-bounds errors during development.

## 4. Maintenance
-   **Asset Pipeline:** Adding a block should require 0 lines of code changes (Resource-only).
