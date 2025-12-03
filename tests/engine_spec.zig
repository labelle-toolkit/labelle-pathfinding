//! Tests for PathfindingEngine

const std = @import("std");
const pathfinding = @import("pathfinding");
const PathfindingEngine = pathfinding.PathfindingEngine;

const TestConfig = struct {
    pub const Entity = u32;
    pub const Context = *u32;
};

const Engine = PathfindingEngine(TestConfig);

test "engine: add and remove nodes" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 100);

    try std.testing.expectEqual(@as(usize, 3), engine.getNodeCount());

    engine.removeNode(1);
    try std.testing.expectEqual(@as(usize, 2), engine.getNodeCount());
}

test "engine: auto node id" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    const id1 = try engine.addNodeAuto(0, 0);
    const id2 = try engine.addNodeAuto(100, 0);
    const id3 = try engine.addNodeAuto(200, 0);

    try std.testing.expectEqual(@as(u32, 0), id1);
    try std.testing.expectEqual(@as(u32, 1), id2);
    try std.testing.expectEqual(@as(u32, 2), id3);
}

test "engine: omnidirectional connections" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Create a grid of nodes
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 0);
    try engine.addNode(3, 0, 100);
    try engine.addNode(4, 100, 100);

    try engine.connectNodes(.{ .omnidirectional = .{ .max_distance = 150, .max_connections = 4 } });

    // Node 0 should connect to node 1 and 3 (within distance)
    const edges_0 = engine.getEdges(0);
    try std.testing.expect(edges_0 != null);
    try std.testing.expect(edges_0.?.len >= 2);
}

test "engine: directional connections" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Create nodes in a cross pattern
    try engine.addNode(0, 100, 100); // center
    try engine.addNode(1, 200, 100); // right
    try engine.addNode(2, 0, 100); // left
    try engine.addNode(3, 100, 0); // up
    try engine.addNode(4, 100, 200); // down

    try engine.connectNodes(.{ .directional = .{ .horizontal_range = 120, .vertical_range = 120 } });

    const dir_edges = engine.getDirectionalEdges(0);
    try std.testing.expect(dir_edges != null);
    try std.testing.expectEqual(@as(?u32, 1), dir_edges.?.right);
    try std.testing.expectEqual(@as(?u32, 2), dir_edges.?.left);
    try std.testing.expectEqual(@as(?u32, 3), dir_edges.?.up);
    try std.testing.expectEqual(@as(?u32, 4), dir_edges.?.down);
}

test "engine: entity registration" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);

    try engine.registerEntity(1, 10, 10, 50.0);
    try std.testing.expectEqual(@as(usize, 1), engine.getEntityCount());

    const pos = engine.getPosition(1);
    try std.testing.expect(pos != null);
    try std.testing.expectEqual(@as(f32, 10), pos.?.x);
    try std.testing.expectEqual(@as(f32, 10), pos.?.y);

    try std.testing.expectEqual(@as(?f32, 50.0), engine.getSpeed(1));

    engine.setSpeed(1, 100.0);
    try std.testing.expectEqual(@as(?f32, 100.0), engine.getSpeed(1));

    engine.unregisterEntity(1);
    try std.testing.expectEqual(@as(usize, 0), engine.getEntityCount());
}

test "engine: pathfinding" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    // Create a line of nodes
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 0);

    try engine.connectNodes(.{ .omnidirectional = .{ .max_distance = 150, .max_connections = 4 } });
    try engine.rebuildPaths();

    // Register entity at first node
    try engine.registerEntity(1, 0, 0, 100.0);

    // Request path to last node
    try engine.requestPath(1, 2);
    try std.testing.expect(engine.isMoving(1));

    // Tick until arrival
    var dummy: u32 = 0;
    var ticks: u32 = 0;
    while (engine.isMoving(1) and ticks < 100) {
        engine.tick(&dummy, 0.1);
        ticks += 1;
    }

    // Should have arrived
    try std.testing.expect(!engine.isMoving(1));

    const final_pos = engine.getPosition(1);
    try std.testing.expect(final_pos != null);
    // Should be at or near node 2 (200, 0)
    try std.testing.expect(final_pos.?.x > 150);
}

test "engine: spatial queries" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 0);

    // Register multiple entities
    try engine.registerEntity(1, 10, 10, 50.0);
    try engine.registerEntity(2, 20, 20, 50.0);
    try engine.registerEntity(3, 500, 500, 50.0);

    // Query radius - should find first two
    var buffer: [10]u32 = undefined;
    const found = engine.getEntitiesInRadius(15, 15, 50, &buffer);
    try std.testing.expectEqual(@as(usize, 2), found.len);

    // Query rect
    const found_rect = engine.getEntitiesInRect(0, 0, 100, 100, &buffer);
    try std.testing.expectEqual(@as(usize, 2), found_rect.len);
}

test "engine: cancel path" {
    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 1000, 0);

    try engine.connectNodes(.{ .omnidirectional = .{ .max_distance = 1500, .max_connections = 4 } });
    try engine.rebuildPaths();

    try engine.registerEntity(1, 0, 0, 100.0);
    try engine.requestPath(1, 1);

    try std.testing.expect(engine.isMoving(1));

    engine.cancelPath(1);
    try std.testing.expect(!engine.isMoving(1));
}

test "engine: callbacks" {
    const CallbackState = struct {
        var completed_count: u32 = 0;
        var node_reached_count: u32 = 0;

        fn onCompleted(_: *u32, _: u32, _: u32) void {
            completed_count += 1;
        }

        fn onNodeReached(_: *u32, _: u32, _: u32) void {
            node_reached_count += 1;
        }
    };

    var engine = Engine.init(std.testing.allocator);
    defer engine.deinit();

    engine.on_path_completed = CallbackState.onCompleted;
    engine.on_node_reached = CallbackState.onNodeReached;

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 50, 0);
    try engine.addNode(2, 100, 0);

    try engine.connectNodes(.{ .omnidirectional = .{ .max_distance = 60, .max_connections = 4 } });
    try engine.rebuildPaths();

    try engine.registerEntity(1, 0, 0, 1000.0);
    try engine.requestPath(1, 2);

    // Tick until complete
    var dummy: u32 = 0;
    var ticks: u32 = 0;
    while (engine.isMoving(1) and ticks < 100) {
        engine.tick(&dummy, 0.1);
        ticks += 1;
    }

    // Should have reached nodes and completed
    try std.testing.expect(CallbackState.node_reached_count >= 1);
    try std.testing.expectEqual(@as(u32, 1), CallbackState.completed_count);
}
