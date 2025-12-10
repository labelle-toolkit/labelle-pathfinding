//! Tests for PathfindingEngine

const std = @import("std");
const pathfinding = @import("pathfinding");
const PathfindingEngine = pathfinding.PathfindingEngine;
const LogLevel = pathfinding.LogLevel;

const TestConfig = struct {
    pub const Entity = u32;
    pub const Context = *u32;
};

const Engine = PathfindingEngine(TestConfig);

// Test the simplified config pattern
const SimpleEngine = pathfinding.PathfindingEngineSimple(u32, *u32);

// Config with explicit log level for testing
const DebugConfig = struct {
    pub const Entity = u32;
    pub const Context = *u32;
    pub const log_level: LogLevel = .debug;
};

const SilentConfig = struct {
    pub const Entity = u32;
    pub const Context = *u32;
    pub const log_level: LogLevel = .none;
};

const DebugEngine = PathfindingEngine(DebugConfig);
const SilentEngine = PathfindingEngine(SilentConfig);

test "engine: add and remove nodes" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNode(2, 200, 100);

    try std.testing.expectEqual(@as(usize, 3), engine.getNodeCount());

    engine.removeNode(1);
    try std.testing.expectEqual(@as(usize, 2), engine.getNodeCount());
}

test "engine: auto node id" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    const id1 = try engine.addNodeAuto(0, 0);
    const id2 = try engine.addNodeAuto(100, 0);
    const id3 = try engine.addNodeAuto(200, 0);

    try std.testing.expectEqual(@as(u32, 0), id1);
    try std.testing.expectEqual(@as(u32, 1), id2);
    try std.testing.expectEqual(@as(u32, 2), id3);
}

test "engine: omnidirectional connections" {
    var engine = try Engine.init(std.testing.allocator);
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
    var engine = try Engine.init(std.testing.allocator);
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

test "engine: connectAsGrid4 convenience" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    const cell_size: f32 = 100;

    // Create a 3x3 grid
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, cell_size, 0);
    try engine.addNode(2, cell_size * 2, 0);
    try engine.addNode(3, 0, cell_size);
    try engine.addNode(4, cell_size, cell_size); // center
    try engine.addNode(5, cell_size * 2, cell_size);
    try engine.addNode(6, 0, cell_size * 2);
    try engine.addNode(7, cell_size, cell_size * 2);
    try engine.addNode(8, cell_size * 2, cell_size * 2);

    try engine.connectAsGrid4(cell_size);

    // Center node (4) should have exactly 4 connections (no diagonals)
    const edges_4 = engine.getEdges(4);
    try std.testing.expect(edges_4 != null);
    try std.testing.expectEqual(@as(usize, 4), edges_4.?.len);

    // Corner node (0) should have 2 connections
    const edges_0 = engine.getEdges(0);
    try std.testing.expect(edges_0 != null);
    try std.testing.expectEqual(@as(usize, 2), edges_0.?.len);
}

test "engine: connectAsGrid8 convenience" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    const cell_size: f32 = 100;

    // Create a 3x3 grid
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, cell_size, 0);
    try engine.addNode(2, cell_size * 2, 0);
    try engine.addNode(3, 0, cell_size);
    try engine.addNode(4, cell_size, cell_size); // center
    try engine.addNode(5, cell_size * 2, cell_size);
    try engine.addNode(6, 0, cell_size * 2);
    try engine.addNode(7, cell_size, cell_size * 2);
    try engine.addNode(8, cell_size * 2, cell_size * 2);

    try engine.connectAsGrid8(cell_size);

    // Center node (4) should have 8 connections (including diagonals)
    const edges_4 = engine.getEdges(4);
    try std.testing.expect(edges_4 != null);
    try std.testing.expectEqual(@as(usize, 8), edges_4.?.len);

    // Corner node (0) should have 3 connections (right, down, diagonal)
    const edges_0 = engine.getEdges(0);
    try std.testing.expect(edges_0 != null);
    try std.testing.expectEqual(@as(usize, 3), edges_0.?.len);
}

test "engine: createGrid helper" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    const grid = try engine.createGrid(.{
        .rows = 3,
        .cols = 4,
        .cell_size = 50,
        .offset_x = 100,
        .offset_y = 200,
        .connection = .four_way,
    });

    // Should have created 12 nodes (3x4)
    try std.testing.expectEqual(@as(usize, 12), engine.getNodeCount());

    // Test grid coordinate conversion
    const pos = grid.toScreen(2, 1); // col 2, row 1
    try std.testing.expectEqual(@as(f32, 200), pos.x); // 2 * 50 + 100
    try std.testing.expectEqual(@as(f32, 250), pos.y); // 1 * 50 + 200

    // Test node ID conversion
    const node_id = grid.toNodeId(2, 1); // col 2, row 1
    try std.testing.expectEqual(@as(u32, 6), node_id); // 1 * 4 + 2 = 6

    // Test reverse conversion
    const coords = grid.fromNodeId(6);
    try std.testing.expectEqual(@as(u32, 2), coords.col);
    try std.testing.expectEqual(@as(u32, 1), coords.row);

    // Test node count
    try std.testing.expectEqual(@as(u32, 12), grid.nodeCount());

    // Test isValid
    try std.testing.expect(grid.isValid(3, 2)); // valid: col 3, row 2
    try std.testing.expect(!grid.isValid(4, 2)); // invalid: col 4 >= cols
    try std.testing.expect(!grid.isValid(3, 3)); // invalid: row 3 >= rows
}

test "engine: createGrid with eight_way connections" {
    var engine = try Engine.init(std.testing.allocator);
    defer engine.deinit();

    const grid = try engine.createGrid(.{
        .rows = 3,
        .cols = 3,
        .cell_size = 100,
        .connection = .eight_way,
    });

    // Center node (1,1) should have 8 connections
    const center_id = grid.toNodeId(1, 1);
    const edges = engine.getEdges(center_id);
    try std.testing.expect(edges != null);
    try std.testing.expectEqual(@as(usize, 8), edges.?.len);
}

test "engine: PathfindingEngineSimple convenience" {
    // Test that SimpleEngine works exactly like Engine
    var engine = try SimpleEngine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.connectAsGrid4(100);

    try std.testing.expectEqual(@as(usize, 2), engine.getNodeCount());
}

test "engine: entity registration" {
    var engine = try Engine.init(std.testing.allocator);
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
    var engine = try Engine.init(std.testing.allocator);
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
    var engine = try Engine.init(std.testing.allocator);
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
    var engine = try Engine.init(std.testing.allocator);
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

    var engine = try Engine.init(std.testing.allocator);
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

test "engine: log level configuration" {
    // Test that engines with different log levels can be instantiated
    var debug_engine = try DebugEngine.init(std.testing.allocator);
    defer debug_engine.deinit();

    var silent_engine = try SilentEngine.init(std.testing.allocator);
    defer silent_engine.deinit();

    // Both should work identically for basic operations
    try debug_engine.addNode(0, 0, 0);
    try debug_engine.addNode(1, 100, 0);

    try silent_engine.addNode(0, 0, 0);
    try silent_engine.addNode(1, 100, 0);

    try std.testing.expectEqual(@as(usize, 2), debug_engine.getNodeCount());
    try std.testing.expectEqual(@as(usize, 2), silent_engine.getNodeCount());
}

test "log level: allows function" {
    // Test the allows() function for log level filtering
    try std.testing.expect(LogLevel.debug.allows(.debug));
    try std.testing.expect(LogLevel.debug.allows(.info));
    try std.testing.expect(LogLevel.debug.allows(.warning));
    try std.testing.expect(LogLevel.debug.allows(.err));

    try std.testing.expect(LogLevel.info.allows(.info));
    try std.testing.expect(LogLevel.info.allows(.warning));
    try std.testing.expect(LogLevel.info.allows(.err));
    try std.testing.expect(!LogLevel.info.allows(.debug));

    try std.testing.expect(LogLevel.err.allows(.err));
    try std.testing.expect(!LogLevel.err.allows(.warning));
    try std.testing.expect(!LogLevel.err.allows(.info));
    try std.testing.expect(!LogLevel.err.allows(.debug));

    try std.testing.expect(!LogLevel.none.allows(.err));
    try std.testing.expect(!LogLevel.none.allows(.warning));
    try std.testing.expect(!LogLevel.none.allows(.info));
    try std.testing.expect(!LogLevel.none.allows(.debug));
}
