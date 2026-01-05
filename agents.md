# Project Agents

## 1. Core Systems Agent
*   **Goal:** Implement the low-level data and management layer.
*   **Responsibility:**
    *   `ChunkManager` (Life-cycle)
    *   `Chunk` (Data Container)
    *   `JobSystem` (Threading)
*   **Tools:** Standard Grid Map, FastNoiseLite.
*   **Constraints:** Must ensure thread safety. No direct SceneTree manipulation from worker threads.

## 2. Rendering Specialist Agent
*   **Goal:** Convert voxel data into visual meshes efficiently.
*   **Responsibility:**
    *   `Meshing Algorithm` (Greedy / Culled)
    *   `ArrayMesh` Generation
    *   `Material` Management (Texture Arrays)
*   **Tools:** `RenderingServer`, `SurfaceTool` (Prototyping only, moving to Arrays).
*   **Constraints:** Latency < 16ms per chunk generation.

## 3. Persistence Agent
*   **Goal:** Ensure data consistency and saving/loading.
*   **Responsibility:**
    *   `ChunkSerializer` (Input/Output)
    *   `RLE Compression` implementation.
    *   `WorldOrigin` shifting logic.
*   **Tools:** `FileAccess`, `WorkerThreadPool`.
*   **Constraints:** Save files must be versioned.

## 4. Interaction & Gameplay Agent
*   **Goal:** Provide user-facing tools to manipulate the generic data.
*   **Responsibility:**
    *   `VoxelInteraction` (Raycasting)
    *   `BlockRegistry` (Definitions)
    *   `PlayerController` (Movement/Input)
*   **Tools:** Physics Raycasts, Resource System.
*   **Constraints:** UX focus (responsiveness).
