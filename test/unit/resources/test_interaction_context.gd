## Test: InteractionContext
## GUT unit tests for interaction_context.gd resource.
extends GutTest


# -------------------------------------------------------------------
# Default Values Tests
# -------------------------------------------------------------------

func test_default_selected_block_id() -> void:
	var ctx := InteractionContext.new()
	assert_eq(ctx.selected_block_id, 2, "Default should be DIRT (2)")


func test_default_brush_radius() -> void:
	var ctx := InteractionContext.new()
	assert_eq(ctx.brush_radius, 1, "Default brush radius should be 1")


func test_default_reach_distance() -> void:
	var ctx := InteractionContext.new()
	assert_eq(ctx.reach_distance, 5.0, "Default reach should be 5.0")


func test_default_can_modify() -> void:
	var ctx := InteractionContext.new()
	assert_true(ctx.can_modify, "Default should allow modification")


# -------------------------------------------------------------------
# get_place_block Tests
# -------------------------------------------------------------------

func test_get_place_block_returns_selected_id() -> void:
	var ctx := InteractionContext.new()
	ctx.selected_block_id = 3
	assert_eq(ctx.get_place_block(), 3)


# -------------------------------------------------------------------
# set_selected_block Tests
# -------------------------------------------------------------------

func test_set_selected_block_changes_id() -> void:
	var ctx := InteractionContext.new()
	ctx.set_selected_block(1)
	assert_eq(ctx.selected_block_id, 1)


func test_set_selected_block_to_zero() -> void:
	var ctx := InteractionContext.new()
	ctx.set_selected_block(0)
	assert_eq(ctx.selected_block_id, 0, "Should allow setting to AIR")


# -------------------------------------------------------------------
# cycle_block Tests
# -------------------------------------------------------------------

func test_cycle_block_from_dirt() -> void:
	var ctx := InteractionContext.new()
	ctx.selected_block_id = 2  # DIRT
	ctx.cycle_block()
	assert_eq(ctx.selected_block_id, 3, "DIRT (2) should cycle to STONE (3)")


func test_cycle_block_from_stone_wraps() -> void:
	var ctx := InteractionContext.new()
	ctx.selected_block_id = 3  # STONE
	ctx.cycle_block()
	assert_eq(ctx.selected_block_id, 1, "STONE (3) should wrap to GRASS (1)")


func test_cycle_block_from_grass() -> void:
	var ctx := InteractionContext.new()
	ctx.selected_block_id = 1  # GRASS
	ctx.cycle_block()
	assert_eq(ctx.selected_block_id, 2, "GRASS (1) should cycle to DIRT (2)")


func test_cycle_block_multiple_times() -> void:
	var ctx := InteractionContext.new()
	ctx.selected_block_id = 1
	
	ctx.cycle_block()  # 1 -> 2
	ctx.cycle_block()  # 2 -> 3
	ctx.cycle_block()  # 3 -> 1
	
	assert_eq(ctx.selected_block_id, 1, "Full cycle should return to start")


# -------------------------------------------------------------------
# Resource Behavior Tests
# -------------------------------------------------------------------

func test_context_is_resource() -> void:
	var ctx := InteractionContext.new()
	assert_true(ctx is Resource, "InteractionContext should be a Resource")


func test_multiple_contexts_are_independent() -> void:
	var ctx1 := InteractionContext.new()
	var ctx2 := InteractionContext.new()
	
	ctx1.selected_block_id = 99
	
	assert_eq(ctx2.selected_block_id, 2, "Contexts should be independent")


# -------------------------------------------------------------------
# Object Pooling Tests
# -------------------------------------------------------------------

func before_each() -> void:
	# Clear pool before each test to ensure isolation
	InteractionContext.clear_pool()


func test_rent_returns_new_when_pool_empty() -> void:
	var ctx := InteractionContext.rent()
	assert_not_null(ctx, "rent() should return a valid context")
	assert_true(ctx is InteractionContext)
	InteractionContext.release(ctx)


func test_rent_returns_recycled_when_pool_has_items() -> void:
	var ctx1 := InteractionContext.rent()
	InteractionContext.release(ctx1)
	
	var ctx2 := InteractionContext.rent()
	assert_eq(ctx1, ctx2, "rent() should return the same recycled instance")
	InteractionContext.release(ctx2)


func test_release_adds_to_pool() -> void:
	assert_eq(InteractionContext.get_pool_size(), 0, "Pool should start empty")
	
	var ctx := InteractionContext.rent()
	InteractionContext.release(ctx)
	
	assert_eq(InteractionContext.get_pool_size(), 1, "Pool should have 1 item after release")


func test_rent_resets_state() -> void:
	var ctx := InteractionContext.rent()
	ctx.selected_block_id = 99
	ctx.brush_radius = 5
	ctx.reach_distance = 100.0
	ctx.can_modify = false
	InteractionContext.release(ctx)
	
	var ctx2 := InteractionContext.rent()
	assert_eq(ctx2.selected_block_id, 2, "Should reset to default block ID")
	assert_eq(ctx2.brush_radius, 1, "Should reset to default brush radius")
	assert_eq(ctx2.reach_distance, 5.0, "Should reset to default reach")
	assert_true(ctx2.can_modify, "Should reset to default can_modify")
	InteractionContext.release(ctx2)


func test_pool_respects_max_size() -> void:
	var contexts: Array[InteractionContext] = []
	
	# Rent more than MAX_POOL_SIZE
	for _ in range(40):
		contexts.append(InteractionContext.rent())
	
	# Release all
	for ctx in contexts:
		InteractionContext.release(ctx)
	
	# Pool should cap at MAX_POOL_SIZE (32)
	assert_true(InteractionContext.get_pool_size() <= 32, "Pool should not exceed MAX_POOL_SIZE")


func test_release_null_is_safe() -> void:
	# Should not crash
	InteractionContext.release(null)
	assert_eq(InteractionContext.get_pool_size(), 0, "null release should not add to pool")


func test_clear_pool_empties_pool() -> void:
	var ctx := InteractionContext.rent()
	InteractionContext.release(ctx)
	assert_eq(InteractionContext.get_pool_size(), 1)
	
	InteractionContext.clear_pool()
	assert_eq(InteractionContext.get_pool_size(), 0, "clear_pool should empty the pool")
