Based on the simulated expert review, the definition of "Safe Extension" has shifted. We are moving from a **Node-based architecture** (easy to code, hard to scale) to a **Server-based architecture** (harder to code, massive performance/safety gains).

Here is your updated engineering roadmap to extend the codebase safely.

### Phase 1: Architectural "First Aid"

_Before adding new features, patch the identified scalability leaks._

#### 1. Implement Object Pooling for `InteractionContext`

Why: The review identified new() on every raycast as a Garbage Collection risk.

The Fix: Modify InteractionContext to handle its own recycling.

GDScript

```
# scripts/resources/interaction_context.gd
class_name InteractionContext extends Resource

# Global pool
static var _pool: Array[InteractionContext] = []

var hit_position: Vector3
var hit_normal: Vector3
var chunk_position: Vector3i

# "Constructor" replacement
static function rent() -> InteractionContext:
    if _pool.is_empty():
        return InteractionContext.new()
    return _pool.pop_back()

# "Destructor" replacement
func release() -> void:
    hit_position = Vector3.ZERO
    hit_normal = Vector3.ZERO
    _pool.append(self)
```

#### 2. Componentize the `ProtoController`

Why: The review flagged the Player script as a potential "God Class."

The Fix: Create an Ability system. The Controller manages movement; Abilities manage actions.

**Create `scripts/abilities/ability.gd`:**

GDScript

```
class_name PlayerAbility extends Resource

func enter(controller: CharacterBody3D) -> void: pass
func exit(controller: CharacterBody3D) -> void: pass
func physics_update(controller: CharacterBody3D, delta: float) -> void: pass
func input(controller: CharacterBody3D, event: InputEvent) -> void: pass
```

**Update `ProtoController`:**

GDScript

```
# In proto_controller.gd
@export var abilities: Array[PlayerAbility]
var active_ability: PlayerAbility

func _physics_process(delta):
    # ... existing movement logic ...
    
    # Delegate to ability
    if active_ability:
        active_ability.physics_update(self, delta)
```

---

### Phase 2: The Core Refactor (The "Server" Pattern)

_This addresses the critical "Node3D overhead" warning._

**The Concept:** Stop using `Chunk.tscn`. The `Chunk` class should no longer inherit from `Node3D`. It should be a `RefCounted` object that holds **RIDs** (Resource IDs) for the Physics and Rendering servers.

**The Safe Extension Path:**

1. **Do not delete** `Chunk.gd` yet.
    
2. **Create** `ChunkVisualizer.gd`.
    
3. Modify `ChunkManager` to swap between them via a flag.
    

**New `scripts/chunk_server_based.gd` (Draft):**

GDScript

```
class_name ChunkServerBased extends RefCounted

var mesh_rid: RID
var body_rid: RID
var position: Vector3

func _init(p_pos: Vector3, material: Material):
    position = p_pos
    # 1. Create Instance directly in RenderingServer
    mesh_rid = RenderingServer.instance_create()
    RenderingServer.instance_set_scenario(mesh_rid, get_world_3d().scenario)
    RenderingServer.instance_set_transform(mesh_rid, Transform3D(Basis(), position))

func set_mesh(mesh: ArrayMesh):
    RenderingServer.instance_set_base(mesh_rid, mesh.get_rid())

func destroy():
    RenderingServer.free_rid(mesh_rid)
    if body_rid.is_valid():
        PhysicsServer3D.free_rid(body_rid)
```

---

### Phase 3: The Feature Implementation (Revised)

_How to implement the Grappling Hook respecting the new constraints._

Feature: Grappling Hook

We are using the Grappling Hook as a stress-test example: How do we let the player interact with the world without breaking the movement code?

Constraint: Must use PhysicsDirectSpaceState (not RayCast nodes) and the new Ability system.

**File:** `scripts/abilities/grapple_ability.gd`

GDScript

```
class_name GrappleAbility extends PlayerAbility

var hook_point: Vector3
var is_grappling: bool = false
const PULL_SPEED = 25.0

func input(controller: CharacterBody3D, event: InputEvent):
    if event.is_action_pressed("fire"):
        attempt_grapple(controller)
    elif event.is_action_released("fire"):
        is_grappling = false

func attempt_grapple(controller: CharacterBody3D):
    # SAFETY: Use PhysicsServer queries instead of RayCast3D nodes
    var space_state = controller.get_world_3d().direct_space_state
    var cam = controller.get_viewport().get_camera_3d()
    
    var from = cam.global_position
    var to = from - cam.global_transform.basis.z * 50.0
    
    var query = PhysicsRayQueryParameters3D.create(from, to)
    var result = space_state.intersect_ray(query)
    
    if result:
        # SAFETY: Use the Pool
        var context = InteractionContext.rent()
        context.hit_position = result.position
        hook_point = context.hit_position
        is_grappling = true
        
        # Logic done, return to pool
        context.release()

func physics_update(controller: CharacterBody3D, delta: float):
    if is_grappling:
        var dir = (hook_point - controller.global_position).normalized()
        controller.velocity = dir * PULL_SPEED
        # Note: We rely on the controller's own move_and_slide call
```

### Summary of Corrective Actions

|**Feature**|**Old Plan (Risky)**|**Updated Plan (Safe)**|
|---|---|---|
|**Input**|`RayCast3D` Nodes|`PhysicsDirectSpaceState.intersect_ray`|
|**Data**|`new InteractionContext()`|`InteractionContext.rent()` (Pooling)|
|**Logic**|Add to `ProtoController.gd`|Create `GrappleAbility.gd` (Component)|
|**World**|`Chunk` extends `Node3D`|`Chunk` holds `RID`s (Server API)|

**Recommendation:** Start with **Phase 1 (Pooling & Components)**. It requires the least refactoring but immediately protects your memory and architecture logic. Phase 2 (RenderingServer) is a dedicated optimization sprint.