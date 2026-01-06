# Hand-off: Voxel Engine - Phase 3 (Server-Based Chunks)

## 1. Project Status Summary
We have completed the migration from Node-based `Chunk.tscn` scenes to a high-performance **ChunkServer (RefCounted)** architecture. This eliminates scene tree overhead for thousands of chunks and allows direct RID management.

-   **Architecture:** `ChunkServer` extends `RefCounted`. Manages `RenderingServer` and `PhysicsServer3D` RIDs directly.
-   **Interaction:** Block placement/removal is restored via coordinate conversion (Global -> Local).
-   **Stability:** Major crashes (Double-free, Out-Of-Bounds) and data corruption (Serializer mismatch) have been resolved.

---

## 2. Recent Commits (Branch: `chunk-server-migration`)
-   **Refactor:** Replaced `Chunk` nodes with `ChunkServer` class.
-   **Fix:** `ChunkSerializer` now uses 64-bit coordinates (moved to `user://chunks_v3/`).
-   **Fix:** `ChunkManager` auto-regenerates corrupted chunks (0 triangles) instead of crashing.
-   **Fix:** Explicit `destroy()` pattern implemented to mitigate `RefCounted` lifecycle race conditions.

---

## 3. Key Systems & Constraints
-   **ChunkServer:** Lightweight logic-only class. MUST be destroyed explicitly via `chunk.destroy()` to ensure RIDs are freed on the main thread before the reference is lost.
-   **Collision:** Uses "Lazy Collision". `_collision_enabled` flag must be managed carefully. `_build_collision()` manually toggles this.
-   **Thread Safety:** `WorkerThreadPool` handles generation/loading. `ChunkManager` handles main-thread application.

---

## 4. Known Issues (Active)

~~### ⚠️ "Null Instance" Warning on Unload~~ **FIXED**

**Resolution:** Added `_destroyed` guard flag to `ChunkServer.destroy()` and `_notification(PREDELETE)`. Cleanup is now idempotent. All 21 unit tests pass.

~~### ⚠️ "material is null" Errors~~ **FIXED**

**Resolution:** Added RID validity guard in `ChunkManager._do_apply_chunk_data()`. Chunks now re-queue if material not yet initialized.

---

## 5. Next Steps
1.  ~~**Investigate RefCounted Lifecycle:**~~ ✅ Fixed via `_destroyed` guard pattern.
2.  **Optimize Meshing:** Integrate `SurfaceTool` on threads to avoid main-thread array copies.
3.  **LOD Implementation:** Use the lightweight `ChunkServer` structure to implement distant LOD meshes.

