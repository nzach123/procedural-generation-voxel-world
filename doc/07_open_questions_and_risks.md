# 07. Open Questions and Risks

## 1. Known Unknowns
-   **Maximum Chunk Height:** Can we increase height > 64 without performance cliffs?
    -   *Risk:* Iteration time increases cubically.
-   **Physics Baking Cost:** How expensive is `create_trimesh_collision()` on the main thread?
    -   *Mitigation:* Only generate collision for chunks near the player.

## 2. Design Risks & Mitigations

### R1: Coordinate Math Errors
**Description:** Converting global negative positions (e.g., -15.5) to local chunk indices is prone to off-by-one errors.
**Mitigation:**
-   Use Godot's `posmod` instead of `%`.
-   Write a specific unit test `tests/test_coordinates.gd` to verify mapping of boundary values (-1, -16, -17).

### R2: UV Bleeding (Texture Artifacts)
**Description:** Using a simple texture atlas without `Texture2DArray` may cause pixel bleeding at distance due to mipmapping.
**Mitigation:**
-   **Phase 1:** Disable Mipmaps + Use Nearest Neighbor filtering.
-   **Phase 2:** Upgrade to `Texture2DArray` if visual quality is unacceptable.

### R3: Memory Fragmentation
**Description:** Frequent resizing of arrays in GDScript can cause GC spikes.
**Mitigation:**
-   Pre-allocate `Packed*Array` sizes where possible.
-   Reuse array instances if generation becomes a bottleneck.

### R4: Floating Point Precision (Drift)
**Description:** At >4000 units from origin, 32-bit float precision degrades, causing jitter.
**Mitigation:**
-   **Phase 1:** Ignore (play area < 4km).
-   **Phase 2:** Implement Origin Shifting (`get_tree().root.global_position -= offset`) when player moves beyond threshold.

### R5: Block ID Instability
**Description:** Adding blocks significantly later can shift IDs if using runtime auto-increment.
**Mitigation:**
-   Use a "Manifest" file or strict String-ID mapping in `BlockRegistry` to ensure "Dirt" is always ID 1.
