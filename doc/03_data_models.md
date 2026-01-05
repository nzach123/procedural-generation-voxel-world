# 03. Data Models

## 1. Core Entities

### BlockData (Resource)
Defines the static properties of a single block type.
-   **File Path:** `scripts/resources/block_data.gd`
-   **Type:** `Resource`

| Field | Type | Description |
| :--- | :--- | :--- |
| `block_name` | `String` | Human-readable name (e.g., "Dirt"). |
| `texture_atlas_coords` | `Vector2i` | Coordinates on the main texture atlas (x, y). |
| `is_solid` | `bool` | Determines if the block generates collision/mesh faces. |

### Chunk Data
Represents the dynamic state of a terrain segment.
-   **Storage Class:** `Chunk` (`scripts/chunk.gd`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `voxels` | `PackedByteArray` | Flat array storing block IDs. Size = $W \times H \times D$. |
| `mesh_instance` | `MeshInstance3D` | Visual representation. |
| `collision_body` | `StaticBody3D` | Physical representation. |

## 2. Data Structures

### Voxel Storage Layout
Voxels are stored in a 1D `PackedByteArray` to maximize cache locality and minimize memory overhead.

-   **Dimensions:**
    -   `WIDTH` (X) = 32
    -   `HEIGHT` (Y) = 32
    -   `DEPTH` (Z) = 32
    -   **Total Bytes:** 32,768 bytes per chunk.

-   **Indexing Formula:**
    $Index = x + (z \times WIDTH) + (y \times WIDTH \times DEPTH)$

### World Storage
-   **Container:** `Dictionary[Vector3i, Node]`
-   **Key:** Chunk Coordinate `Vector3i(x, y, z)`.
-   **Value:** `Chunk` node instance.

### Persistence Format (.chk)
Binary file format for saving chunk data.
-   **Header:** `Magic ("VXL")` + `Version (Byte)` + `Coordinate (3x Int32)`.
-   **Body:** Run-Length Encoded (RLE) voxel data.
    -   *Structure:* `[Count (Byte), BlockID (Byte), ...]`
    -   *Logic:* Since terrain is mostly generic mass (all dirt) or air, RLE provides massive compression ratios (often >95%).

## 3. Invariants
-   **Valid IDs:** `0` is reserved for AIR (empty). IDs `1-255` map to valid blocks.
-   **Array Size:** The `voxels` array must always be exactly length `W*H*D`.
