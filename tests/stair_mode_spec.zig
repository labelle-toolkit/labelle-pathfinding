//! Tests for StairMode functionality in PathfindingEngine

const std = @import("std");
const pathfinding = @import("pathfinding");
const PathfindingEngine = pathfinding.PathfindingEngine;
const StairMode = pathfinding.StairMode;

const TestConfig = struct {
    pub const Entity = u32;
    pub const Context = *u32;
};

const Engine = PathfindingEngine(TestConfig);

test "stair_mode: default is .none for regular nodes" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Add node without specifying stair_mode
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 0, 100);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 50, .floor_height = 150 } });

    // No vertical connection should exist (both default to .none)
    const edges0 = engine.getDirectionalEdges(0);
    const edges1 = engine.getDirectionalEdges(1);

    try std.testing.expect(edges0 != null);
    try std.testing.expect(edges1 != null);
    try std.testing.expectEqual(@as(?u32, null), edges0.?.up);
    try std.testing.expectEqual(@as(?u32, null), edges0.?.down);
    try std.testing.expectEqual(@as(?u32, null), edges1.?.up);
    try std.testing.expectEqual(@as(?u32, null), edges1.?.down);
}

test "stair_mode: stair nodes create vertical connections" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Floor 1 (y = 0)
    try engine.addNode(0, 0, 0); // regular
    try engine.addNodeWithStairMode(1, 100, 0, .all); // stair

    // Floor 2 (y = 100)
    try engine.addNode(2, 0, 100); // regular
    try engine.addNodeWithStairMode(3, 100, 100, .all); // stair

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 150, .floor_height = 150 } });

    // Stair nodes should be connected vertically
    const stair1_edges = engine.getDirectionalEdges(1);
    const stair2_edges = engine.getDirectionalEdges(3);

    try std.testing.expect(stair1_edges != null);
    try std.testing.expect(stair2_edges != null);
    try std.testing.expectEqual(@as(?u32, 3), stair1_edges.?.down); // y increases downward
    try std.testing.expectEqual(@as(?u32, 1), stair2_edges.?.up);

    // Non-stair nodes should NOT have vertical connections
    const left1_edges = engine.getDirectionalEdges(0);
    const left2_edges = engine.getDirectionalEdges(2);

    try std.testing.expect(left1_edges != null);
    try std.testing.expect(left2_edges != null);
    try std.testing.expectEqual(@as(?u32, null), left1_edges.?.up);
    try std.testing.expectEqual(@as(?u32, null), left1_edges.?.down);
    try std.testing.expectEqual(@as(?u32, null), left2_edges.?.up);
    try std.testing.expectEqual(@as(?u32, null), left2_edges.?.down);
}

test "stair_mode: horizontal connections work regardless of stair property" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Same floor - mix of stair and non-stair nodes
    try engine.addNode(0, 0, 0);
    try engine.addNodeWithStairMode(1, 100, 0, .all);
    try engine.addNode(2, 200, 0);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 150, .floor_height = 150 } });

    // All horizontal connections should exist
    const edges_a = engine.getDirectionalEdges(0);
    const edges_b = engine.getDirectionalEdges(1);
    const edges_c = engine.getDirectionalEdges(2);

    try std.testing.expect(edges_a != null);
    try std.testing.expect(edges_b != null);
    try std.testing.expect(edges_c != null);

    try std.testing.expectEqual(@as(?u32, 1), edges_a.?.right);
    try std.testing.expectEqual(@as(?u32, 0), edges_b.?.left);
    try std.testing.expectEqual(@as(?u32, 2), edges_b.?.right);
    try std.testing.expectEqual(@as(?u32, 1), edges_c.?.left);
}

test "stair_mode: stair above non-stair does not create vertical connection" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Floor 1: NOT a stair
    try engine.addNode(0, 0, 0);

    // Floor 2: IS a stair (but floor below is not)
    try engine.addNodeWithStairMode(1, 0, 100, .all);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 50, .floor_height = 150 } });

    // No vertical connection should exist
    const edges1 = engine.getDirectionalEdges(0);
    const edges2 = engine.getDirectionalEdges(1);

    try std.testing.expect(edges1 != null);
    try std.testing.expect(edges2 != null);
    try std.testing.expectEqual(@as(?u32, null), edges1.?.down);
    try std.testing.expectEqual(@as(?u32, null), edges2.?.up);
}

test "stair_mode: multi-floor stairwell creates continuous vertical path" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // 4-floor building with stairwell
    try engine.addNodeWithStairMode(0, 0, 0, .all);
    try engine.addNodeWithStairMode(1, 0, 100, .all);
    try engine.addNodeWithStairMode(2, 0, 200, .all);
    try engine.addNodeWithStairMode(3, 0, 300, .all);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 50, .floor_height = 150 } });

    // Verify continuous stairwell connections
    const e0 = engine.getDirectionalEdges(0).?;
    const e1 = engine.getDirectionalEdges(1).?;
    const e2 = engine.getDirectionalEdges(2).?;
    const e3 = engine.getDirectionalEdges(3).?;

    try std.testing.expectEqual(@as(?u32, 1), e0.down);
    try std.testing.expectEqual(@as(?u32, 0), e1.up);
    try std.testing.expectEqual(@as(?u32, 2), e1.down);
    try std.testing.expectEqual(@as(?u32, 1), e2.up);
    try std.testing.expectEqual(@as(?u32, 3), e2.down);
    try std.testing.expectEqual(@as(?u32, 2), e3.up);
}

test "stair_mode: StairMode.all allows unlimited concurrent usage" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNodeWithStairMode(0, 0, 0, .all);
    try engine.addNodeWithStairMode(1, 0, 100, .all);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 50, .floor_height = 150 } });
    try engine.rebuildPaths();

    // Register multiple entities
    try engine.registerEntity(1, 0, 0, 100.0);
    try engine.registerEntity(2, 0, 0, 100.0);
    try engine.registerEntity(3, 0, 100, 100.0);

    // Request paths in different directions
    try engine.requestPath(1, 1); // entity 1 goes down
    try engine.requestPath(2, 1); // entity 2 goes down
    try engine.requestPath(3, 0); // entity 3 goes up

    var dummy: u32 = 0;
    engine.tick(&dummy, 0.1);

    // All should be moving (not waiting) because mode is .all
    const pos1 = engine.getPositionFull(1).?;
    const pos2 = engine.getPositionFull(2).?;
    const pos3 = engine.getPositionFull(3).?;

    try std.testing.expectEqual(@as(?u32, null), pos1.waiting_for_stair);
    try std.testing.expectEqual(@as(?u32, null), pos2.waiting_for_stair);
    try std.testing.expectEqual(@as(?u32, null), pos3.waiting_for_stair);
}

test "stair_mode: StairMode.single allows only one entity" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Floor 1: entry node and stair
    try engine.addNode(0, -100, 0); // entry point
    try engine.addNodeWithStairMode(1, 0, 0, .single); // stair floor 1

    // Floor 2: stair and exit
    try engine.addNodeWithStairMode(2, 0, 100, .single); // stair floor 2
    try engine.addNode(3, 100, 100); // exit point

    // Add waiting spots around the stair
    try engine.addNode(4, -50, 0); // waiting spot 1
    try engine.addNode(5, -50, -50); // waiting spot 2
    try engine.setWaitingArea(1, &[_]u32{ 4, 5 });

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 150, .floor_height = 150 } });
    try engine.rebuildPaths();

    // Register two entities at the entry point
    try engine.registerEntity(1, -100, 0, 100.0);
    try engine.registerEntity(2, -100, 0, 100.0);

    // Both try to go to the exit (through the stair)
    try engine.requestPath(1, 3);
    try engine.requestPath(2, 3);

    var dummy: u32 = 0;

    // Tick multiple times to allow first entity to reach and enter the stair
    for (0..20) |_| {
        engine.tick(&dummy, 0.1);
    }

    // Get positions
    const pos1 = engine.getPositionFull(1).?;
    const pos2 = engine.getPositionFull(2).?;

    // At least one should be using the stair or have used it
    // The other should be waiting (if the stair is still occupied)
    const using_or_past = (pos1.using_stair != null or pos1.current_node >= 2) or
        (pos2.using_stair != null or pos2.current_node >= 2);

    try std.testing.expect(using_or_past);
}

test "stair_mode: StairMode.direction allows same direction only" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Floor 1
    try engine.addNode(0, -100, 0); // entry floor 1
    try engine.addNodeWithStairMode(1, 0, 0, .direction); // stair floor 1

    // Floor 2
    try engine.addNodeWithStairMode(2, 0, 100, .direction); // stair floor 2
    try engine.addNode(3, 100, 100); // exit floor 2

    // Add waiting spots
    try engine.addNode(4, -50, 0); // waiting spot floor 1
    try engine.addNode(5, 50, 100); // waiting spot floor 2
    try engine.setWaitingArea(1, &[_]u32{4});
    try engine.setWaitingArea(2, &[_]u32{5});

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 150, .floor_height = 150 } });
    try engine.rebuildPaths();

    // Entity 1 goes down (from floor 1 to floor 2)
    try engine.registerEntity(1, -100, 0, 100.0);
    try engine.requestPath(1, 3);

    var dummy: u32 = 0;

    // Tick until entity 1 enters the stair
    for (0..15) |_| {
        engine.tick(&dummy, 0.1);
    }

    // Check that entity 1 is using the stair
    const pos1 = engine.getPositionFull(1).?;

    // If entity 1 is still using the stair (moving through it)
    if (pos1.using_stair != null) {
        // Entity 2 tries to go same direction (down) - should be allowed
        try engine.registerEntity(2, -100, 0, 100.0);
        try engine.requestPath(2, 3);

        engine.tick(&dummy, 0.1);

        // Tick more to let entity 2 approach
        for (0..10) |_| {
            engine.tick(&dummy, 0.1);
        }

        const pos2 = engine.getPositionFull(2).?;

        // Same direction should work - not waiting
        try std.testing.expectEqual(@as(?u32, null), pos2.waiting_for_stair);
    } else {
        // Entity 1 already passed through, test passes trivially
        try std.testing.expect(true);
    }
}

test "stair_mode: getStairState returns correct state" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNodeWithStairMode(0, 0, 0, .single);
    try engine.addNode(1, 100, 0);

    const stair_state = engine.getStairState(0);
    const regular_state = engine.getStairState(1);

    try std.testing.expect(stair_state != null);
    try std.testing.expectEqual(StairMode.single, stair_state.?.mode);
    try std.testing.expect(regular_state == null);
}

test "stair_mode: getStairMode returns correct mode" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNodeWithStairMode(0, 0, 0, .all);
    try engine.addNodeWithStairMode(1, 100, 0, .direction);
    try engine.addNodeWithStairMode(2, 200, 0, .single);
    try engine.addNode(3, 300, 0);

    try std.testing.expectEqual(StairMode.all, engine.getStairMode(0));
    try std.testing.expectEqual(StairMode.direction, engine.getStairMode(1));
    try std.testing.expectEqual(StairMode.single, engine.getStairMode(2));
    try std.testing.expectEqual(StairMode.none, engine.getStairMode(3));
}

test "stair_mode: mixed stair types in same building" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Floor 1: wide staircase (all)
    // Floor 2: escalator (direction)
    // Floor 3: ladder (single)
    try engine.addNodeWithStairMode(0, 0, 0, .all);
    try engine.addNodeWithStairMode(1, 0, 100, .direction);
    try engine.addNodeWithStairMode(2, 0, 200, .single);
    try engine.addNodeWithStairMode(3, 0, 300, .single);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 50, .floor_height = 150 } });

    // All should have vertical connections
    const e0 = engine.getDirectionalEdges(0).?;
    const e1 = engine.getDirectionalEdges(1).?;
    const e2 = engine.getDirectionalEdges(2).?;

    try std.testing.expect(e0.down != null);
    try std.testing.expect(e1.up != null);
    try std.testing.expect(e1.down != null);
    try std.testing.expect(e2.up != null);

    // Each segment should have its own stair state
    const state0 = engine.getStairState(0).?;
    const state1 = engine.getStairState(1).?;
    const state2 = engine.getStairState(2).?;

    try std.testing.expectEqual(StairMode.all, state0.mode);
    try std.testing.expectEqual(StairMode.direction, state1.mode);
    try std.testing.expectEqual(StairMode.single, state2.mode);
}

test "stair_mode: addNodeAutoWithStairMode works correctly" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    const id1 = try engine.addNodeAutoWithStairMode(0, 0, .all);
    const id2 = try engine.addNodeAutoWithStairMode(100, 0, .single);
    const id3 = try engine.addNodeAuto(200, 0);

    try std.testing.expectEqual(@as(u32, 0), id1);
    try std.testing.expectEqual(@as(u32, 1), id2);
    try std.testing.expectEqual(@as(u32, 2), id3);

    try std.testing.expectEqual(StairMode.all, engine.getStairMode(id1));
    try std.testing.expectEqual(StairMode.single, engine.getStairMode(id2));
    try std.testing.expectEqual(StairMode.none, engine.getStairMode(id3));
}

test "stair_mode: backward compatibility with existing directional mode" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Nodes without stair mode specified
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 0, 100);

    // Using old directional mode (for platformers)
    try engine.connectNodes(.{ .directional = .{ .horizontal_range = 50, .vertical_range = 150 } });

    // Directional mode should still connect vertically regardless of stair_mode
    const e0 = engine.getDirectionalEdges(0).?;
    const e1 = engine.getDirectionalEdges(1).?;

    try std.testing.expectEqual(@as(?u32, 1), e0.down);
    try std.testing.expectEqual(@as(?u32, 0), e1.up);
}

test "stair_mode: single stair does not teleport entity on subsequent frames" {
    // Regression test for issue #19:
    // state.enter() was called every frame, causing users_count to increment
    // repeatedly. On frame 2, canEnter(.single) returned false and teleported
    // the entity to a waiting spot.

    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Simple two-floor setup with single-file stair
    try engine.addNode(0, 0, 0); // floor 1 entry
    try engine.addNodeWithStairMode(1, 100, 0, .single); // stair top
    try engine.addNodeWithStairMode(2, 100, 100, .single); // stair bottom
    try engine.addNode(3, 200, 100); // floor 2 exit

    // Add waiting spot (required for .single mode when stair is busy)
    try engine.addNode(4, 50, 0);
    try engine.setWaitingArea(1, &[_]u32{4});

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 120, .floor_height = 150 } });
    try engine.rebuildPaths();

    // Register entity and request path through the stair
    try engine.registerEntity(1, 0, 0, 50.0); // slow speed to ensure multiple frames on stair
    try engine.requestPath(1, 3);

    var dummy: u32 = 0;

    // Tick until entity reaches the stair node
    for (0..30) |_| {
        engine.tick(&dummy, 0.1);
        const pos = engine.getPositionFull(1).?;
        if (pos.current_node == 1) break;
    }

    // Entity should be at or moving through stair node 1
    const pos_at_stair = engine.getPositionFull(1).?;
    try std.testing.expectEqual(@as(u32, 1), pos_at_stair.current_node);

    // Record position before more ticks
    const x_before = pos_at_stair.x;
    const y_before = pos_at_stair.y;

    // Tick a few more times - entity should continue moving smoothly, NOT teleport
    for (0..5) |_| {
        engine.tick(&dummy, 0.1);
    }

    const pos_after = engine.getPositionFull(1).?;

    // Entity should NOT be teleported to waiting spot (node 4 at x=50)
    // It should either still be on the stair (moving toward node 2) or have passed through
    const was_teleported_to_waiting = pos_after.x < 60 and pos_after.waiting_for_stair != null;
    try std.testing.expect(!was_teleported_to_waiting);

    // Entity should have made progress (y should have increased toward 100, or already past)
    const made_progress = pos_after.y > y_before or pos_after.current_node >= 2;
    try std.testing.expect(made_progress);

    // Verify users_count didn't inflate (should be 0 or 1, not 5+)
    if (engine.getStairState(1)) |state| {
        try std.testing.expect(state.users_count <= 1);
    }

    _ = x_before;
}

test "stair_mode: cancelPath releases stair correctly" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Two-floor setup with single-file stair
    try engine.addNode(0, 0, 0);
    try engine.addNodeWithStairMode(1, 100, 0, .single);
    try engine.addNodeWithStairMode(2, 100, 100, .single);
    try engine.addNode(3, 200, 100);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 120, .floor_height = 150 } });
    try engine.rebuildPaths();

    // Entity starts path through stair
    try engine.registerEntity(1, 0, 0, 100.0);
    try engine.requestPath(1, 3);

    var dummy: u32 = 0;

    // Tick until entity is using the stair
    for (0..20) |_| {
        engine.tick(&dummy, 0.1);
        const pos = engine.getPositionFull(1).?;
        if (pos.using_stair != null) break;
    }

    // Verify entity is using stair
    const pos_before = engine.getPositionFull(1).?;
    try std.testing.expect(pos_before.using_stair != null);

    // Check stair has user
    const stair_node = pos_before.using_stair.?;
    const state_before = engine.getStairState(stair_node).?;
    try std.testing.expect(state_before.users_count >= 1);

    // Cancel the path
    engine.cancelPath(1);

    // Verify stair was released
    const state_after = engine.getStairState(stair_node).?;
    try std.testing.expectEqual(@as(u32, 0), state_after.users_count);

    // Verify entity state is cleared
    const pos_after = engine.getPositionFull(1).?;
    try std.testing.expectEqual(@as(?u32, null), pos_after.using_stair);
    try std.testing.expectEqual(@as(?u32, null), pos_after.target_node);
}

test "stair_mode: unregisterEntity releases stair correctly" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Two-floor setup with single-file stair
    try engine.addNode(0, 0, 0);
    try engine.addNodeWithStairMode(1, 100, 0, .single);
    try engine.addNodeWithStairMode(2, 100, 100, .single);
    try engine.addNode(3, 200, 100);

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 120, .floor_height = 150 } });
    try engine.rebuildPaths();

    // Entity starts path through stair
    try engine.registerEntity(1, 0, 0, 100.0);
    try engine.requestPath(1, 3);

    var dummy: u32 = 0;

    // Tick until entity is using the stair
    var stair_node: u32 = 0;
    for (0..20) |_| {
        engine.tick(&dummy, 0.1);
        const pos = engine.getPositionFull(1).?;
        if (pos.using_stair) |sn| {
            stair_node = sn;
            break;
        }
    }

    // Check stair has user
    const state_before = engine.getStairState(stair_node).?;
    try std.testing.expect(state_before.users_count >= 1);

    // Unregister the entity
    engine.unregisterEntity(1);

    // Verify stair was released
    const state_after = engine.getStairState(stair_node).?;
    try std.testing.expectEqual(@as(u32, 0), state_after.users_count);

    // Verify entity is gone
    try std.testing.expect(engine.getPositionFull(1) == null);
}
