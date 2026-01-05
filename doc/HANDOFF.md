# Hand-off: Voxel Engine - Player Tracking Loop

## 1. Project Status Summary
We have successfully transitioned the **RevVoxelEngine** from a static 4x4 grid to an **infinite, streaming terrain system**. 

- **Infinite Streaming:** Chunks now load/unload dynamically around the player using a 0.5s heartbeat timer.
- **Persistence:** Modifications (and generated terrain) are saved/loaded to `user://save/` using RLE compression.
- **Performance:** Implemented a time-budgeted mesh apply queue (2ms/frame) and deferred collision builds to eliminate loading hitches.
- **Thread Safety:** Implemented thread-local `FastNoiseLite` copies to prevent race conditions during generation.

---

## 2. Recent Commits (Branch: `player-tracking-loop`)
- `7bb3874`: **feat: implement Player Tracking Loop**
    - Adds spiral priority loading, memory cap (400 chunks), and origin shifting (5000 units).
- `b80e69a`: **perf: fix loading hitch with time-budgeted mesh applies**
    - Defers collision builds to next frame and budgets mesh uploads to 2ms/frame.

---

## 3. Key Systems & Constraints
- **ChunkManager:** Central orchestrator. Uses `_load_priority_offsets` for closest-first loading.
- **Spiral Loading:** Pre-computed list of neighbors sorted by distance squared.
- **Void Edge Fix:** Neighbor-triggered remesh queue (`_edge_remesh_queue`) batches border updates to fix seams as new chunks appear.
- **Collision:** Lazy collision is essential. Chunks outside `collision_radius` have no physics body.

---

## 4. Senior Developer Gotchas (Solved)
- ✅ **Loading Deadlocks:** Rejected a "wait for 3x3 neighbors" approach in favor of "immediate mesh + neighbor-triggered remesh".
- ✅ **GC Pressure:** Replaced `Dictionary.keys()` iteration with direct dictionary iteration to avoid 0.5s array allocations.
- ✅ **Thread Safety:** Worker tasks now create their own `FastNoiseLite` instances using cached seed/frequency.

---

## 5. Next Steps
1. **Modernize BlockRegistry:** Currently, the system still uses the legacy `BlockDefinitions`. The modern resource-based `BlockRegistry` (with `BlockData` resources) is ready but needs to be fully integrated into `Chunk` meshing.
2. **LOD System:** Implement simplified mesh generation for chunks beyond a certain radius.
3. **Biomes:** Move from single-scale noise to a biome-layer noise system.
4. **Origin Shifting Testing:** Verify the physics stability when the player crosses the 5000-unit threshold.

---

## 6. How to Continue
The latest work is on the `player-tracking-loop` branch. Run the `voxel_engine.tscn` to see the infinite terrain in action. Check `doc/walkthrough.md` for a deeper technical breakdown of method additions.
