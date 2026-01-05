# 01. System Overview

## 1. System Purpose
The **Voxel Terrain System v2.0** is a high-performance, modifiable voxel engine designed for Godot 4.4+. Its primary purpose is to support infinite procedural terrain generation with runtime modification capabilities, addressing the performance bottlenecks of previous array-based iterations.

## 2. High-Level Architecture
The system moves away from nested arrays and `SurfaceTool` in favor of flat memory structures and direct server-based or low-level mesh manipulation.
- **Data:** Uses `PackedByteArray` for contiguous memory access.
- **Rendering:** Uses direct `ArrayMesh` generation for speed.
- **Concurrency:** Heavily relies on `WorkerThreadPool` to offload generation from the main thread.

## 3. Key Goals
1.  **Performance:** Achieve >60 FPS with aggressive geometry generation by minimizing memory fragmentation and CPU overhead.
2.  **Scalability:** Support infinite terrain generation on the X and Z axes (Y-axis limited by chunk height).
3.  **Extensibility:** Allow non-programmers to define block types via `Resource` files rather than hardcoded enums.
4.  **Responsiveness:** Ensure no frame freezes during chunk loading or modification.

## 4. Non-Goals
-   **LOD (Level of Detail):** Not included in this iteration (v2.0 focuses on the localized high-res voxel interactions).
-   **Advanced Lighting:** Standard Godot lighting is assumed; no custom voxel GI in this scope.
-   **Complex Physics:** Basic collision only; no rigid body physics for individual loose voxels.

## 5. Assumptions and Constraints
-   **Engine Version:** Godot 4.4 or higher.
-   **Target Hardware:** Desktop-class GPU/CPU.
-   **Chunk Dimensions:** Fixed at 32 (Width) x 32 (Height) x 32 (Depth) to support verticality and uniform rendering logic.
-   **Thread Safety:** The "Thread Model" in project settings is assumed to be safe for `WorkerThreadPool` usage.
