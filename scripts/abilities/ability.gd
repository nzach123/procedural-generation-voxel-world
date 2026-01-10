## PlayerAbility
## Base class for player abilities using a component-based architecture.
## Abilities are Resources that encapsulate discrete player behaviors (grapple, dash, etc.).
## Each ability manages its own state and lifecycle independently.
##
## THREADING: Abilities run on the main thread only.
## STATE ISOLATION: Always use duplicate(true) when assigning to a player to prevent shared state.
class_name PlayerAbility
extends Resource

# -------------------------------------------------------------------
# Signals
# -------------------------------------------------------------------

## Emitted when the ability completes or is interrupted.
signal ability_finished

# -------------------------------------------------------------------
# Exports
# -------------------------------------------------------------------

## Display name for UI/debugging.
@export var display_name: String = "Ability"

## Icon for UI display (optional).
@export var icon: Texture2D

## Cooldown duration in seconds (0 = no cooldown).
@export var cooldown: float = 0.0

## Whether this ability can be interrupted by other abilities.
@export var interruptible: bool = true

# -------------------------------------------------------------------
# State (Instance-specific)
# -------------------------------------------------------------------

## Reference to the owning player (set by player on init).
var player: CharacterBody3D = null

## Time remaining on cooldown (managed by ability system).
var cooldown_remaining: float = 0.0

## Whether the ability is currently active.
var is_active: bool = false

# -------------------------------------------------------------------
# Lifecycle Methods (Override in subclasses)
# -------------------------------------------------------------------


## Called when this ability becomes the active ability.
## @param owner: The CharacterBody3D that owns this ability.
func enter(owner: CharacterBody3D) -> void:
	player = owner
	is_active = true


## Called when this ability is deactivated (switched away or interrupted).
func exit() -> void:
	is_active = false
	ability_finished.emit()


## Called every physics frame while this ability is active.
## @param delta: Physics frame delta time.
func physics_update(delta: float) -> void:
	# Update cooldown if applicable
	if cooldown_remaining > 0.0:
		cooldown_remaining -= delta
		if cooldown_remaining < 0.0:
			cooldown_remaining = 0.0


## Called for unhandled input events while this ability is active.
## @param event: The input event.
## @return bool: True if the event was handled.
func input(event: InputEvent) -> bool:
	return false


# -------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------


## Returns true if the ability is ready to use (not on cooldown).
func is_ready() -> bool:
	return cooldown_remaining <= 0.0


## Starts the cooldown timer.
func start_cooldown() -> void:
	cooldown_remaining = cooldown


## Resets all instance state to defaults (for pooling or reuse).
func clear_state() -> void:
	player = null
	cooldown_remaining = 0.0
	is_active = false


## Creates a deep duplicate suitable for per-player instantiation.
## This ensures nested Resources are not shared between players.
func create_instance() -> PlayerAbility:
	return duplicate(true) as PlayerAbility
