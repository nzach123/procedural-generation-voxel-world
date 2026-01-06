# Implementation Plan - Voxel Safety Expansion

This plan addresses scalability and safety concerns raised in the expert review. The goal is to transition from a naive Node-based architecture to a more robust, memory-safe, and performant system.

## Goal Description

Refactor the Voxel Engine to use:
1. **Object Pooling** for interaction data (reduces GC pressure).
2. **Component-based Ability System** for the player (enables modular features).
3. **Server-based Chunk Architecture** to eliminate Node overhead (Phase 3).

We start with "Architectural First Aid" and then implement the Grappling Hook as a proof-of-concept.

## User Review Required

> [!IMPORTANT]
> **Server-Based Chunks (Phase 3)**: This is a fundamental change to how the world is rendered and simulated. It replaces `Chunk.tscn` scenes with raw `RenderingServer` and `PhysicsServer3D` calls. This offers significant performance gains but reduces editor visibility for individual chunks.

## Proposed Changes

### Phase 1: Architectural First Aid

#### [MODIFY] [interaction_context.gd](file:///c:/00_Repos/Godot_Projects/procedural-generation-voxel-world/scripts/resources/interaction_context.gd)
- Add static `_pool` array.
- Implement static `rent()` and `release()` methods.
- **Review Note**: `release()` must call `_reset()` to clear stale state before returning to pool.
- Prevent `new()` allocation spam during raycasts.

#### [NEW] [ability.gd](file:///c:/00_Repos/Godot_Projects/procedural-generation-voxel-world/scripts/abilities/ability.gd)
- Define `PlayerAbility` class (extends `Resource`).
- Virtual methods: `enter()`, `exit()`, `physics_update()`, `input()`.
- **Constraint**: Ensure state isolation. Abilities must be `duplicated()` on player init OR use a stateless design with a context object to prevent data sharing between sessions.
- **Review Note**: Use `duplicate(true)` for deep copy if ability holds nested Resource references; otherwise document stateless constraint.

#### [MODIFY] [proto_controller.gd](file:///c:/00_Repos/Godot_Projects/procedural-generation-voxel-world/scenes/proto_controller/proto_controller.gd)
- Add `ability_templates` export array.
- Initialize abilities using `ability.create_instance()` to ensure unique state per player.
- Add `_active_ability` property.
- Delegate `_physics_process` and `_unhandled_input` to the active ability.

---

### Phase 2: Feature Implementation (Grappling Hook)

#### [NEW] [grapple_ability.gd](file:///c:/00_Repos/Godot_Projects/procedural-generation-voxel-world/scripts/abilities/grapple_ability.gd)
- Extends `PlayerAbility`.
- **Optimization**: Cache a reusable `PhysicsRayQueryParameters3D` instance; do not allocate via `new()` every frame.
- **Review Note**: Reset `collision_mask` and `exclude` array before each query to avoid stale exclusion lists.
- Use `InteractionContext.rent()` to obtain hit results without allocation.
- **Safety**: Verify that the hit chunk has `is_physics_ready == true` to avoid "The Void Problem" (grappling through loading ghosts).

---

### Phase 3: Core Refactor (Server-Based Chunks)

> [!WARNING]
> This is a hard refactor. We will **not** maintain a toggle for Node-based vs Server-based rendering. The existing staging logic will be replaced entirely.

#### [NEW] [chunk_server.gd](file:///c:/00_Repos/Godot_Projects/procedural-generation-voxel-world/scripts/chunk_server.gd)
- `RefCounted` class replacing the `Chunk` node.
- Manages `RID`s for Mesh Instance and Physics Body directly.
- **Requirement**: Explicitly calculate and set `custom_aabb` for the Mesh Instance RID (prevents incorrect culling).
- **Review Note**: Add 0.1-unit margin to AABB bounds to prevent frustum-edge culling artifacts.
- **Requirement**: Explicitly link RIDs to the `World3D` scenario via `get_world_3d().scenario`.
- **Review Note**: If ChunkManager survives scene changes, re-link RIDs to new scenario in scene-change callback.
- **Cleanup**: Free all RIDs in `NOTIFICATION_PREDELETE` to prevent VRAM leaks.
- **Review Note**: ChunkServer must be freed on main thread only; add `assert(OS.get_thread_caller_id() == OS.get_main_thread_id())` in cleanup.

#### [MODIFY] [chunk_manager.gd](file:///c:/00_Repos/Godot_Projects/procedural-generation-voxel-world/scripts/chunk_manager.gd)
- Remove `Chunk.tscn` instantiation logic.
- Replace with `ChunkServer.new()`.
- Update visibility and loading logic to work with the new `RefCounted` container.

---

## Verification Plan

### Automated Tests

1. **InteractionContext Pooling** (`test/unit/resources/test_interaction_context.gd`)
   - Add tests verifying `rent()` returns recycled objects and `release()` returns them to the pool.
   - **Run**: `godot --headless --script addons/gut/gut_cmdln.gd -gdir=test/unit/resources -gtest=test_interaction_context.gd`

2. **PlayerAbility System** (new: `test/unit/abilities/test_player_ability.gd`)
   - Verify `duplicate()` creates isolated state.
   - Verify lifecycle methods (`enter`, `exit`, `physics_update`, `input`) are callable.

### Manual Verification

1. **Pooling Stability**
   - Run the game and monitor memory usage via Godot's Debugger > Monitors.
   - Perform heavy grappling for 60 seconds; confirm no allocation spikes.

2. **Grappling Hook Functionality**
   - Verify aim indicator displays correctly.
   - Verify fire/reel mechanics function as expected.
   - **Stress Test**: Grapple rapidly (10+ times in 5 seconds) and check for frame drops.

3. **Server-Based Chunks (Phase 3)**
   - Fly to chunk borders; verify no "pop-in" gaps from missing AABBs.
   - Verify collisions are solid immediately upon chunk visibility.
   - **Leak Check**: Repeatedly fly away and back to force unload/reload cycles; monitor VRAM.
