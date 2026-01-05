# Task: Voxel Safety Expansion

- [x] **Phase 1: Architectural First Aid** <!-- id: 0 -->
    - [x] Add static `rent()` and `release()` pooling methods to `InteractionContext` <!-- id: 1 -->
    - [x] Create `PlayerAbility` base class (`scripts/abilities/ability.gd`) <!-- id: 2 -->
    - [x] Refactor `player.gd` to delegate input/physics to active ability (with `.duplicate()` for state isolation) <!-- id: 3 -->
- [x] **Phase 2: Feature Implementation (Grappling Hook)** <!-- id: 4 -->
    - [x] Create `GrappleAbility` resource (`scripts/abilities/grapple_ability.gd`) <!-- id: 5 -->
    - [x] Implement grapple logic with cached `PhysicsRayQueryParameters3D` and `InteractionContext.rent()` <!-- id: 6 -->
    - [x] Register `GrappleAbility` in Player's `abilities` export array <!-- id: 7 -->
- [ ] **Phase 3: Core Refactor (Server-Based Architecture)** <!-- id: 8 -->
    - [ ] Create `ChunkServer` class (`RefCounted`) with direct RID management <!-- id: 9 -->
    - [ ] Implement explicit `custom_aabb` calculation and `World3D.scenario` linking <!-- id: 10 -->
    - [ ] Implement `NOTIFICATION_PREDELETE` handler to free all RIDs <!-- id: 16 -->
    - [ ] Replace `ChunkManager` instantiation logic (hard cut-over, no toggle) <!-- id: 11 -->
- [ ] **Phase 4: Verification** <!-- id: 12 -->
    - [ ] Run pooling unit tests; verify `rent()` reuses released objects <!-- id: 13 -->
    - [ ] Manual test: Verify grapple aim, fire, and reel mechanics <!-- id: 14 -->
    - [ ] Performance comparison: measure frame time with Server-based vs Node-based chunks <!-- id: 15 -->
