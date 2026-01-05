# Technical Review: Voxel Safety Expansion

## Introduction
Use this document to capture feedback from the simulated technical review board.
**Reviewers:**
1.  **Dev 1 (Systems Architect)**: Specialist in engine architecture and data streaming.
2.  **Dev 2 (ProcGen & Physics)**: Specialist in voxel math and collision.
3.  **Dev 3 (Optimization Lead)**: Specialist in renderer pipelines and memory.

---

## 1. Plan Verification & Critique

### Phase 1: Architectural First Aid (Object Pooling & Ability System)

**Dev 1 (Architect):**
> "The move to `PlayerAbility` resources involves a hidden risk: **Resource State Safety**. If `PlayerAbility` is a Resource, it is shared across all instances by default in Godot. If you store state (like `current_cooldown` or `velocity_bias`) directly on the script variables of the Resource, *all players* (or effective sessions if managing multiple) will share that state.
> **Recommendation**: Either `duplicate()` abilities on initialization or ensure the Resource is purely functional (stateless) and passes a `context` object for state."

**Dev 3 (Optimization):**
> "On `InteractionContext` pooling: You mention `pre-computing spiral load offsets` in your previous context, which is good. For the pool itself, `pop_back()` is fast, but GDScript implementation of pools can sometimes be slower than `new()` for very lightweight objects due to the overhead of GDScript function calls.
> **Verification**: Verify that the `InteractionContext` is actually causing GC pressure. If the class is tiny, the engine might handle widespread allocation fine. However, avoiding the allocation does help predict memory flux. Proceed, but verify with a Monitor."

**Dev 2 (ProcGen):**
> "No major complaints on Phase 1, but extending `Resource` for abilities is standard. Just make sure `enter()` and `exit()` references are cleaned up to avoid circular ref leaks if the ability holds a reference back to the Player."

### Phase 2: Feature Implementation (Grappling Hook)

**Dev 2 (ProcGen):**
> "You're using `PhysicsServer` for the raycast, which is great. However, `PhysicsRayQueryParameters3D` is *also* an object. If you're creating `new()` parameters every frame in `physics_update`, you're defeating the purpose of the optimization.
> **Action Item**: Cache a reusable `PhysicsRayQueryParameters3D` instance within the `GrappleAbility` or the pool, and just update its `from` and `to` properties."

**Dev 1 (Architect):**
> "The plan ignores the 'Void Problem' for grappling. In a streaming world, chunks load async. If I grapple towards a chunk that is mesh-ready but not physics-ready (or vice versa), what happens?
> **Risk**: Raycast passes through visual terrain.
> **Mitigation**: Ensure the chunk generation logic commits Physics implementations *before* or *simultaneously* with Visuals, or accept that players might grapple through loading walls."

### Phase 3: Core Refactor (Server-Based Chunks)

**Dev 1 (Architect):**
> "**CRITICAL**: The plan proposes implementing a `use_server_rendering` boolean toggle to switch between Node-based and Server-based.
> This is a **Complexity Trap**. Node-based and Server-based paths diverge significantly. Maintaining two parallel rendering pipelines in `ChunkManager` will lead to regression bugs where features work in one but not the other.
> **Strong Recommendation**: Do not make it a toggle for the long term. Make Phase 3 a hard cut-over. If you need a fallback, keep the old generic class in git history, but do not clutter the active codebase with `if use_server_rendering:` checks everywhere."

**Dev 3 (Optimization):**
> "`RenderingServer` API usage requires manual handling of **Visibility Requirments (AABB)**. Nodes calculate their AABB automatically. When you push a mesh to the `RenderingServer`, you *must* set the generic custom AABB or the engine might try to draw it when it's behind the camera, or cull it incorrectly.
> **Missing Item**: The plan needs a step to 'Calculate and Set Custom AABB' for the server-instance."

**Dev 2 (ProcGen):**
> "Also, `RenderingServer` instances need to be explicitly added to a `Scenario` (World3D). Nodes do this when they enter the tree. You will need to access `get_world_3d().scenario` from the parent manager to link these RIDs effectively. Don't forget to clean them up manually in `NOTIFICATION_PREDELETE`, or you *will* leak VRAM."

---

## 2. Risk Assessment Summary

| Severity | Category | Issue | Proposed Mitigation |
| :--- | :--- | :--- | :--- |
| **High** | Architecture | Keeping both Node/Server paths active (Toggle Tax) | Commit to Server-based once proven useful. Remove legacy Node path immediately after verification. |
| **Medium** | Memory | `PlayerAbility` resources sharing state | Use `duplicate()` on init or pass State Dictionaries. |
| **Medium** | Perf | `PhysicsRayQueryParameters3D` allocation spam | Cache/Pool power parameters object. |
| **Medium** | Rendering | Incorrect Culling on Server Instances | Explicitly calculate and set AABB on RIDs. |

## 3. Revised Recommendations

1.  **Refine Phase 1**: Add "Ability Instancing Strategy" to ensuring state isolation.
2.  **Refine Phase 2**: Add "Parameter Reuse" to the Grappling Hook implementation tasks.
3.  **Refine Phase 3**:
    *   Remove "Toggle" requirement. Replace with "Branching Implementation" or "Hard Refactor".
    *   Add task: "Implement explicit AABB calculation for Chunk Meshes".
    *   Add task: "Link RIDs to World3D Scenario".

---
*End of Review*
