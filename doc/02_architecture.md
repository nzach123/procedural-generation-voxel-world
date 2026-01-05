# 02. System Architecture

## 1. Component Breakdown

The system is organized into four distinct layers, separating data definition, storage, management, and interaction.

### Layer 1: Data Definition (Global)
*   **Component:** `BlockRegistry` (Singleton/Autoload)
*   **Responsibility:** Central source of truth for block properties. Loads `BlockData` resources and maps integer IDs (byte) to texture coordinates and physics properties.

### Layer 2: The Unit (Chunk)
*   **Component:** `Chunk` (Node3D)
*   **Responsibility:** Represents a single unit of terrain. Stores raw voxel data for its region and handles the rendering of its specific mesh. Manages its own collision body.

### Layer 3: Management (World)
*   **Component:** `ChunkManager` (Node)
*   **Responsibility:** Orchestrates the infinite grid. Manages the lifecycle of chunks (spawn, despawn), handles coordinate conversions, and dispatches generation tasks to threads.
*   **Component:** `ChunkSerializer` (RefCounted/Helper)
*   **Responsibility:** Handles I/O operations. Saves/Loads chunk `PackedByteArray` to disk using RLE compression to ensure persistence.

### Layer 4: Interaction (Player)
*   **Component:** `VoxelInteraction` (Component/Script)
*   **Responsibility:** Handles user input for terrain modification. Performs raycasting and coordinate mapping.
*   **Component:** `InteractionContext` (Resource/State)
*   **Responsibility:** Maintains state for `selected_block_id`, `brush_size`, and build constraints (range, permission).

## 2. Interaction Data Flow

The following describes the flow of data between components:

1.  **Initialization:**
    *   `BlockRegistry` loads all `BlockData` resources at startup.
    *   `ChunkManager` calculates visible chunks based on player position.

2.  **Generation Pipeline:**
    *   `ChunkManager` requests a new chunk at coordinate local `(x, z)`.
    *   `ChunkManager` creates a `Chunk` instance.
    *   **THREAD:** `WorkerThreadPool` generates raw voxel data (via Noise).
    *   **THREAD:** `WorkerThreadPool` generates mesh arrays (Vertices, Indices, UVs).
    *   **MAIN:** `Chunk` applies the generated arrays to its `MeshInstance3D`.

3.  **Modification:**
    *   `VoxelInteraction` detects a hit and calculates the target global coordinate.
    *   `ChunkManager` routes the modification to the specific `Chunk`.
    *   `Chunk` updates its `PackedByteArray`.
    *   `Chunk` triggers a mesh regeneration (threaded).

## 3. Relationships forms
-   `ChunkManager` **owns** multiple `Chunk` nodes (stored in a Dictionary).
-   `Chunk` **references** `BlockRegistry` (to look up texture UVs).
-   `Player` **uses** `VoxelInteraction` to send commands to `ChunkManager`.
