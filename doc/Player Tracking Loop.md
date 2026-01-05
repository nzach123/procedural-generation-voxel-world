### High-Level System Overview

The Infinite Scrolling system replaces the static `world_size` generation with a dynamic **Player Tracking Loop**. This loop constantly monitors the player's position, translating their global coordinates into a "Chunk Coordinate" (e.g., `(10, -5)`).

As the player moves, the system calculates a **Target Window**—a square or circular grid of chunks centered on the player.

- **Enter Window:** Chunks inside the window that don't exist are queued for **Loading**.
    
- **Exit Window:** Chunks outside the window (plus a safety buffer) are queued for **Unloading**.
    

We utilize Godot's `WorkerThreadPool` for generation to prevent frame stutters, and `ChunkSerializer` to persist changes (like broken blocks) so the world remains consistent when revisited.

---

### 1. Data Structures & State Management

We need three distinct collections to manage the lifecycle of a chunk safely without race conditions.

GDScript

```
# [Vector2i] -> Chunk Node (The active world)
var _chunks: Dictionary = {} 

# [Vector2i] -> bool (Prevents double-loading the same chunk)
var _pending_loads: Dictionary = {} 

# [Vector2i] -> bool (Prevents unloading a chunk that is currently generating)
var _chunks_to_unload: Array[Vector2i] = []
```

### 2. The Player Tracking Loop (Algorithm)

We do _not_ run this every frame. Running 60 times a second is wasteful. Instead, we check:

1. **Distance Check:** Has the player moved more than `chunk_width` since the last update?
    
2. **Timer:** Or run every 0.25 - 0.5 seconds.
    

**Pseudocode Logic:**

Plaintext

```
IF player_moved_significantly():
    current_center = world_to_chunk(player.position)
    
    # 1. IDENTIFY TARGETS
    FOR x in range(-view_dist, view_dist):
        FOR z in range(-view_dist, view_dist):
             target = current_center + Vector2i(x, z)
             IF target NOT IN _chunks AND target NOT IN _pending_loads:
                 trigger_async_load(target)

    # 2. IDENTIFY REMOVALS
    FOR chunk_coord IN _chunks:
         IF distance(chunk_coord, current_center) > view_dist + unload_buffer:
             trigger_unload(chunk_coord)
```

---

### 3. Technical Implementation Plan

#### Phase 1: Update ChunkManager

We need to modify `scripts/chunk_manager.gd` to remove the fixed generation and add the tracking loop.

Step A: Define New Variables

Add exports for view_distance (radius in chunks) and player (NodePath or reference).

Step B: The Heartbeat Function

Create _update_chunks() which implements the logic above. Use Vector2.distance_squared_to for fast comparisons (avoiding square roots).

**Step C: Async Loading Pipeline**

1. Check `ChunkSerializer.chunk_exists(key)`.
    
2. **If exists:** Load compressed data -> Generate Mesh -> Add to Scene.
    
3. If new: Generate Noise Data -> Save to Disk -> Generate Mesh -> Add to Scene.
    
    Why save immediately? It ensures that if the player quits immediately after generation, the world is consistent.
    

#### Phase 2: Signal Architecture

- **Signal:** `chunk_loaded(key)` - Emitted when a chunk is fully added to the scene.
    
- **Signal:** `chunk_unloaded(key)` - Emitted just before `queue_free`.
    
- **Usage:** Use these to trigger "Decoration Spawners" (trees, enemies) or update the Minimap.
    

---

### 4. Implementation Steps (Code)

Here is the exact code to upgrade your `ChunkManager`.

**Modify `scripts/chunk_manager.gd`:**

GDScript

```
extends Node
class_name ChunkManager

# ... (Keep existing signals/constants) ...

# --- NEW EXPORTS ---
@export_group("Infinite Scrolling")
@export var player: Node3D             # Assign your player node here
@export var view_distance: int = 8     # Radius of active chunks
@export var unload_buffer: int = 2     # Extra chunks before unloading (hysteresis)
@export var tick_rate: float = 0.5     # How often to check for chunks (seconds)

# --- STATE ---
var _last_player_chunk: Vector2i = Vector2i(999999, 999999)
var _update_timer: Timer

func _ready() -> void:
    # ... (Keep existing setup) ...
    
    # Initialize Heartbeat Timer
    _update_timer = Timer.new()
    _update_timer.wait_time = tick_rate
    _update_timer.autostart = true
    _update_timer.one_shot = false
    _update_timer.timeout.connect(_on_heartbeat)
    add_child(_update_timer)
    
    # REMOVE _generate_initial_world() call
    # _generate_initial_world() <-- DELETE OR COMMENT OUT

func _on_heartbeat() -> void:
    if not is_instance_valid(player):
        return

    var center_chunk := world_to_chunk_coord(player.global_position)
    
    # Only update if player moved to a new chunk
    if center_chunk != _last_player_chunk:
        _last_player_chunk = center_chunk
        _update_chunk_visibility(center_chunk)
        update_collision_radius(player.global_position)

func _update_chunk_visibility(center: Vector2i) -> void:
    var load_sq = view_distance * view_distance
    var unload_sq = (view_distance + unload_buffer) * (view_distance + unload_buffer)
    
    # 1. LOAD LOOP
    # Spiral or simple nested loop around center
    for x in range(-view_distance, view_distance + 1):
        for z in range(-view_distance, view_distance + 1):
            var offset = Vector2i(x, z)
            if offset.length_squared() > load_sq:
                continue # Circular clipping
            
            var coord = center + offset
            
            if not _chunks.has(coord) and not _pending_chunks.has(coord):
                _spawn_chunk_threaded(coord)

    # 2. UNLOAD LOOP
    # Iterate copy of keys to avoid modification issues
    var existing_coords = _chunks.keys()
    for coord in existing_coords:
        var dist = Vector2(coord.x - center.x, coord.y - center.y).length_squared()
        if dist > unload_sq:
            _save_and_unload(coord)

func _save_and_unload(key: Vector2i) -> void:
    if not _chunks.has(key): 
        return
        
    var chunk = _chunks[key]
    
    # CRITICAL: Save changes before destroying
    # We use a thread for saving to prevent stutter
    WorkerThreadPool.add_task(
        func(): ChunkSerializer.save_chunk(chunk)
    )
    
    _unload_chunk(key)
```

### 5. Senior Developer "Gotchas" & Fixes

**1. The "Void Edge" Problem**

- **Issue:** Threaded mesh generation calculates normals/occlusion based on neighbors. If neighbor chunks haven't loaded yet, the edges of the chunk will look wrong (holes or visible faces).
    
- **Fix:** Implement a **2-Pass System**.
    
    - _Pass 1:_ Load Data Only (Voxel Array).
        
    - _Pass 2:_ Once a 3x3 grid of Data exists, Trigger Mesh Generation for the center chunk.
        
    - _Simple Fix:_ In `Chunk.gd`, check bounds. If a block is on the edge `x=0`, returns "Solid" by default instead of "Air" to hide the void, or wait to mesh until neighbors exist.
        

**2. Floating Point Errors**

- **Issue:** In an infinite world, if the player walks 1,000,000 units away, floating point precision degrades (jittery movement).
    
- **Fix:** **Origin Shifting**. Every ~5000 units, teleport the `World` node (or the Player and all Chunks) back to `(0,0,0)` and offset the internal coordinate tracker. Godot 4 supports large coordinates better (using doubles for Node3D position), but physics engines still prefer being near zero.
    

**3. Memory Leaks in ThreadPool**

- **Issue:** Queuing 1000 chunk loads instantly (e.g., teleporting) can flood the thread pool.
    
- **Fix:** Add a `max_concurrent_tasks` limit variable. If `_pending_chunks.size() > 16`, stop requesting new chunks until the queue drains.
    

