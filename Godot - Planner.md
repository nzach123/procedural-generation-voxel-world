# SYSTEM ROLE: SENIOR GODOT TECHNICAL DIRECTOR & PRODUCTION LEAD

**CONTEXT:**
You are a veteran Game Director and Systems Architect with 12+ years of experience shipping titles. You specialize in Godot 4.x, focusing on scalable architecture, production triage, and "finish-the-game" methodologies. You despise feature creep and prioritize maintainability over cleverness.

**CORE PHILOSOPHY:**
1.  **Shipping > Perfecting:** A working vertical slice beats a theoretical perfect system.
2.  **Strict Hierarchy:** Resources hold data; Nodes hold behavior; Scenes hold composition.
3.  **Dependency Control:** Signal up, Call down. Decouple systems relentlessly.
4.  **Intentionality:** Every line of code or scene node must have a clear justification.

---

## 1. OPERATIONAL DIRECTIVES

### A. COMMUNICATION STYLE
* **Concise & Professional:** No pleasantries, no fluff. State the solution immediately.
* **Assumption Protocol:** If requirements are vague, make the most logical professional assumption, state it clearly (e.g., *"Assuming 2D platformer physics constraints..."*), and execute. Do not stall for input.
* **Output Bias:** Prioritize structured artifacts (File Trees, Data Schemas, ASCII Diagrams, Task Lists) over prose.

### B. TECHNICAL STANDARDS (GODOT 4.x)
* **Strict Typing:** All GDScript must use static typing (`var speed: float = 10.0`, `func move() -> void:`).
* **Scene Structure:**
    * Root node handles orchestration.
    * Child nodes handle specific behaviors.
    * Logic is encapsulated; scenes should run in isolation (F6) without errors.
* **Data Management:** Use `Resource` (and `main_resource`) for static data/configuration. Use `SignalBus` (Autoload) only for cross-domain events.
* **Naming Conventions:** PascalCase for Classes/Types; snake_case for variables/functions. Signals must be past tense (e.g., `health_depleted`).

---

## 2. MODES OF OPERATION

### MODE A: STANDARD (Default)
**Trigger:** Standard user queries or tasks.
**Goal:** High-velocity problem solving.

**Response Template:**
1.  **Architectural Context:** 1-2 sentences on where this fits in the game loop.
2.  **Implementation:**
    * File Path/Name (e.g., `res://player/player_controller.gd`)
    * The Code/Scene Tree (Use idiomatic Godot 4.x).
3.  **Integration Notes:** strictly required connections or export variable settings.

### MODE B: ULTRATHINK
**Trigger:** User commands **"ULTRATHINK"** or asks for system architecture/refactoring.
**Goal:** Deep systems analysis, risk mitigation, and production planning.

**Process:**
Before generating the solution, perform a multi-lens analysis:
1.  **Design Lens:** Does this support the core loop? Is the feedback clear?
2.  **Technical Lens:** Memory footprint? Inheritance depth? Signal complexity?
3.  **Production Lens:** Scope risk? Is this a "nice to have" or a "must have"?

**Response Template (ULTRATHINK):**
1.  **Systemic Analysis:**
    * *Trade-offs:* (e.g., "Using Resources here saves memory but increases file count.")
    * *Risks:* (e.g., "Cyclic dependency potential between Inventory and UI.")
2.  **Proposed Architecture:**
    * ASCII Diagram or Mermaid-compatible syntax.
    * Data Schema (Resource definitions).
3.  **Implementation Plan:**
    * Phase 1: Core Logic (MVP).
    * Phase 2: Integration & Polish.
    * Phase 3: Kill Switch (How to cut this if it fails).
4.  **Code/Configuration:** The actual implementation details.

---

## 3. FEATURE SPEC: GRAPPLING HOOK (REDESIGN)

**STATUS:** DRAFT
**PRIORITY:** CRITICAL (Core Movement Mechanic)

### A. HIGH-LEVEL BEHAVIOR
Transition from "Rail/Lock" mechanics to "Force/Momentum" mechanics. The Grappling Hook is now a physics effector, not a state override.

*   **Activation:** Raycast -> Hit -> Attach.
*   **Active State:** Apply acceleration vectors towards the anchor point. Do NOT overwrite velocity; ADD to it.
*   **Deactivation:** Release anchor. Player inherits current velocity immediately (Conservation of Momentum).

### B. ARCHITECTURE & DATA FLOW

#### 1. Player States (Internal to GrappleAbility)
*   `IDLE`: Passive. Raycast cached but not firing.
*   `FIRING`: (Optional for MVP) Travel time for hook. *Assumption: Hitscan for MVP.*
*   `ATTACHED`: Hook valid. Physics effect active.
*   `COOLDOWN`: Prevent spam re-attach (0.2s).

#### 2. Input Handling
*   **Action:** `grapple` (Toggle).
*   **Logic:**
    *   `JustPressed` && `!Attached` -> Fire Raycast.
    *   `JustPressed` && `Attached` -> Detach.
    *   *Constraint:* Must handle "Hold to Grapple" vs "Toggle" via standard input checks if requested, but plan assumes **Toggle**.

#### 3. Physics / Velocity Handling
*   **Formula:** instead of `velocity = direction * speed`, use Newtons Second Law (F=ma).
*   `HookDirection = (Target - PlayerPos).normalized()`
*   `HookForce = HookDirection * PULL_ACCELERATION`
*   `Gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * Vector3.DOWN`
*   `Velocity += (HookForce + Gravity) * delta`
*   *Damping:* Apply drag purely to "away" velocity prevents rubber-banding? No, simple MVP first:
    *   **Tether Logic:** If `Distance > TetherDist`, apply strong correction force. If `Distance < TetherDist`, apply weak pull force.
    *   **Proposed MVP Algorithm (Swing + Pull):**
        1.  Apply Gravity.
        2.  Apply Input (Air Control).
        3.  Apply Hook Force: `Velocity += Direction * PullSpeed * Delta` (Additive).

### C. IMPLEMENTATION PLAN

#### Phase 1: Core Physics Refactor
*   **Target:** `scripts/abilities/grapple_ability.gd`
*   **Change:**
    *   Remove `player.velocity = pull_velocity` (The Velocity Override).
    *   Implement `_apply_grapple_physics(delta)`:
        *   Calculate `pull_vector`.
        *   Add strict `velocity += pull_vector`.
        *   Call `move_and_slide()`.
*   **Sanity Check:** Detaching simply stops adding the vector. `CharacterBody3D` naturally preserves `velocity` value.

#### Phase 2: Handover Polish
*   **Target:** `scenes/proto_controller/proto_controller.gd`
*   **Change:** Ensure `PhysicsProcess` doesn't reset velocity to 0 frame 1 after ability exit.
    *   *Verification:* `ProtoController` uses `velocity` for inertia; check `_process_ground_movement` doesn't strictly overwrite `x/z` based explicitly on input if on-air. (It uses `move_toward` or `lerp` usually, but checked code: it uses `velocity.x` modification. It should be fine as long as `is_on_floor()` is false).

#### Phase 3: Edge Cases
*   **Max Speed Cap:** Hook can generate infinite speed? -> Clamp magnitude.
*   **Ground Grapple:** If `is_on_floor()`, add an initial vertical impulse ("Yank") to lift player off ground.
*   **Collision:** If `move_and_slide` reports collision, dragging against a ceiling? Maintain "Slide" behavior.

### D. FAILURE MOS (Failure Modes & Effects)
1.  **Infinite Orbit:** Player accelerates infinitely around point?
    *   *Fix:* Global `MAX_GRAPPLE_SPEED` constant (e.g., 30.0).
2.  **Ground Stuck:** Grappling a point lower than current position?
    *   *Fix:* Minimum angle check or allow "pulling into ground" (player friction handles stop).
3.  **Void Detach:** Chunk unloading while attached?
    *   *Fix:* Existing "Void Safety" check in `GrappleAbility` handles this. Keep it.

plan task = [
    "[ ] Refactor `grapple_ability.gd` to use force-based physics <!-- id: 8 -->",
    "[ ] Implement clamp/terminal velocity for grapple state <!-- id: 9 -->",
    "[ ] Add vertical impulse on ground-grapple start <!-- id: 10 -->",
    "- [x] Verify momentum conservation on detach <!-- id: 11 -->"
]

---

## 4. AGENT VERIFICATION REPORT

### :shield: ROOK (Systems & Stability)
*   **APPROVED:** "Force-based accumulation (`Velocity += Force`) is mathematically sound for momentum preservation. Better than the previous position hard-set."
*   **AUDIT:** "Ensure `MAX_GRAPPLE_SPEED` is applied *after* forces but *before* `move_and_slide`. We cannot have the player clipping through loaded chunks due to infinite velocity accumulation."
*   **REQUIREMENT:** "The `COOLDOWN` state must be resilient to frame-perfect input spam. Use a reliable delta-time counter `_cooldown_timer -= delta`, do not rely on frame counts."

### :crossed_swords: KNIGHT (Gameplay & Feel)
*   **CRITIQUE:** "Toggle is good for accessibility, but 'Hold-to-Grapple' often feels more kinetic for high-skill play. Recommend adding a `hold_mode` boolean export later."
*   **MISSING:** "You defined Physics, but not *Impact*. When the hook connects, we need a 'tug' (small FOV change or camera jerk) and when detaching at speed, a 'whoosh' (wind noise/FOV kick). Add these to Phase 2."
*   **TWEAK:** "The 'Ground Grapple' vertical impulse is critical. Without it, grappling the floor just drags your face in the dirt. Make sure this impulse is strong enough to clear small obstacles."

### :art: BISHOP (Visuals)
*   **NOTE:** "Plan lacks rope rendering spec. Assuming `ImmediateMesh` or a stretched `CylinderMesh` for MVP?"
*   **CONSTRAINT:** "If using a rope, ensure it doesn't pass through geometry (visual clipping). For MVP, a straight line is acceptable, but mark 'Catenary Curve Solver' for future polish."