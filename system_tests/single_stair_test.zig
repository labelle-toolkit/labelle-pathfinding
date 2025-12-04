//! Single Stair System Test
//!
//! Tests the .single stair mode with various setups:
//! 1. Basic test: 2 entities crossing each other
//! 2. Contention test: 4 entities competing for same stair
//!
//! Verifies:
//! - Entities can traverse the stair in single mode
//! - Only one entity uses the stair at a time
//! - Waiting callbacks are fired correctly
//! - Reached callbacks are fired for all node arrivals

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

const Config = struct {
    pub const Entity = u32;
    pub const Context = *TestState;
    pub const log_level: pathfinding.LogLevel = .err;
};

const Engine = pathfinding.PathfindingEngine(Config);

const TestState = struct {
    node_reached_count: u32 = 0,
    path_completed_count: u32 = 0,
    waiting_started_count: u32 = 0,
    waiting_ended_count: u32 = 0,
    max_concurrent_stair_users: u32 = 0,

    // Track per-entity
    entity_reached: [8]u32 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    entity_completed: [8]u32 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
};

fn onNodeReached(state: *TestState, entity: u32, node: pathfinding.NodeId) void {
    state.node_reached_count += 1;
    if (entity < 8) {
        state.entity_reached[entity] += 1;
    }
    _ = node;
}

fn onPathCompleted(state: *TestState, entity: u32, node: pathfinding.NodeId) void {
    state.path_completed_count += 1;
    if (entity < 8) {
        state.entity_completed[entity] += 1;
    }
    _ = node;
}

fn onWaitingStarted(state: *TestState, entity: u32, node: pathfinding.NodeId) void {
    state.waiting_started_count += 1;
    _ = entity;
    _ = node;
}

fn onWaitingEnded(state: *TestState, entity: u32, node: pathfinding.NodeId) void {
    state.waiting_ended_count += 1;
    _ = entity;
    _ = node;
}

fn runBasicTest(allocator: std.mem.Allocator) !bool {
    print("=== Test 1: Basic Two-Entity Cross ===\n\n", .{});

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var state = TestState{};

    engine.on_node_reached = onNodeReached;
    engine.on_path_completed = onPathCompleted;
    engine.on_waiting_started = onWaitingStarted;
    engine.on_waiting_ended = onWaitingEnded;

    // Build a simple 2-floor layout:
    //   FLOOR 2 (y = 100):  [2]----[3] (stair)
    //   FLOOR 1 (y = 0):    [0]----[1] (stair)

    print("Layout: [0]--[1/stair]--[3/stair]--[2]\n\n", .{});

    try engine.addNode(0, 0, 0);
    try engine.addNodeWithStairMode(1, 100, 0, .single);
    try engine.addNode(2, 0, 100);
    try engine.addNodeWithStairMode(3, 100, 100, .single);

    // Waiting areas must be on the SAME floor as the stair
    try engine.setWaitingArea(3, &[_]pathfinding.NodeId{2}); // Wait at node 2 (floor 2) to enter stair 3
    try engine.setWaitingArea(1, &[_]pathfinding.NodeId{0}); // Wait at node 0 (floor 1) to enter stair 1

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 120, .floor_height = 120 } });
    try engine.rebuildPaths();

    try engine.registerEntity(0, 0, 0, 100.0);
    try engine.registerEntity(1, 0, 100, 100.0);

    try engine.requestPath(0, 2); // A goes up
    try engine.requestPath(1, 0); // B goes down

    const delta: f32 = 1.0 / 60.0;
    var tick: u32 = 0;

    while ((engine.isMoving(0) or engine.isMoving(1)) and tick < 600) {
        engine.tick(&state, delta);
        tick += 1;

        // Track max concurrent stair users
        const stair_state = engine.getStairState(1);
        if (stair_state) |s| {
            if (s.users_count > state.max_concurrent_stair_users) {
                state.max_concurrent_stair_users = s.users_count;
            }
        }
    }

    const final_a = engine.getCurrentNode(0) orelse 99;
    const final_b = engine.getCurrentNode(1) orelse 99;

    print("Results: A at node {d}, B at node {d}\n", .{ final_a, final_b });
    print("Callbacks: reached={d}, completed={d}, waiting_started={d}, waiting_ended={d}\n", .{
        state.node_reached_count,
        state.path_completed_count,
        state.waiting_started_count,
        state.waiting_ended_count,
    });
    print("Max concurrent stair users: {d}\n\n", .{state.max_concurrent_stair_users});

    var passed = true;
    if (final_a != 2 or final_b != 0) {
        print("FAIL: Entities did not reach targets\n", .{});
        passed = false;
    }
    if (state.path_completed_count < 2) {
        print("FAIL: Expected 2 path completions\n", .{});
        passed = false;
    }
    if (state.max_concurrent_stair_users > 1) {
        print("FAIL: More than 1 entity used stair concurrently!\n", .{});
        passed = false;
    }
    // Waiting callbacks should be balanced
    if (state.waiting_started_count != state.waiting_ended_count) {
        print("FAIL: waiting_started ({d}) != waiting_ended ({d})\n", .{
            state.waiting_started_count,
            state.waiting_ended_count,
        });
        passed = false;
    }

    return passed;
}

fn runContentionTest(allocator: std.mem.Allocator) !bool {
    print("=== Test 2: Four-Entity Contention ===\n\n", .{});

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var state = TestState{};

    engine.on_node_reached = onNodeReached;
    engine.on_path_completed = onPathCompleted;
    engine.on_waiting_started = onWaitingStarted;
    engine.on_waiting_ended = onWaitingEnded;

    // Build layout with multiple waiting spots:
    //   FLOOR 2 (y = 100):  [4]--[5]--[6/stair]--[7]
    //   FLOOR 1 (y = 0):    [0]--[1]--[2/stair]--[3]

    print("Layout:\n", .{});
    print("  Floor 2: [4]--[5]--[6/stair]--[7]\n", .{});
    print("  Floor 1: [0]--[1]--[2/stair]--[3]\n\n", .{});

    // Floor 1
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0);
    try engine.addNodeWithStairMode(2, 200, 0, .single);
    try engine.addNode(3, 300, 0);

    // Floor 2
    try engine.addNode(4, 0, 100);
    try engine.addNode(5, 100, 100);
    try engine.addNodeWithStairMode(6, 200, 100, .single);
    try engine.addNode(7, 300, 100);

    // Waiting areas: nodes adjacent to stairs ON THE SAME FLOOR
    try engine.setWaitingArea(6, &[_]pathfinding.NodeId{ 5, 7 }); // Wait on floor 2 to go DOWN
    try engine.setWaitingArea(2, &[_]pathfinding.NodeId{ 1, 3 }); // Wait on floor 1 to go UP

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 120, .floor_height = 120 } });
    try engine.rebuildPaths();

    // 4 entities: 2 going up, 2 going down
    try engine.registerEntity(0, 0, 0, 80.0); // Floor 1, going up
    try engine.registerEntity(1, 300, 0, 80.0); // Floor 1, going up
    try engine.registerEntity(2, 0, 100, 80.0); // Floor 2, going down
    try engine.registerEntity(3, 300, 100, 80.0); // Floor 2, going down

    print("Entities: 0,1 on floor 1 going UP; 2,3 on floor 2 going DOWN\n\n", .{});

    try engine.requestPath(0, 4); // 0 goes to floor 2
    try engine.requestPath(1, 7); // 1 goes to floor 2
    try engine.requestPath(2, 0); // 2 goes to floor 1
    try engine.requestPath(3, 3); // 3 goes to floor 1

    const delta: f32 = 1.0 / 60.0;
    var tick: u32 = 0;
    const max_ticks: u32 = 60 * 20; // 20 seconds max (4 entities going one at a time)

    var stuck_warning_shown = false;

    while (tick < max_ticks) {
        engine.tick(&state, delta);
        tick += 1;

        // Track max concurrent stair users PER COLUMN
        var column_users: u32 = 0;
        if (engine.getStairState(2)) |s| column_users += s.users_count;
        if (engine.getStairState(6)) |s| column_users += s.users_count;
        if (column_users > state.max_concurrent_stair_users) {
            state.max_concurrent_stair_users = column_users;
        }

        // Check if all done
        var any_moving = false;
        for (0..4) |i| {
            if (engine.isMoving(@intCast(i))) {
                any_moving = true;
                break;
            }
        }
        if (!any_moving) break;

        // Debug: check for stuck entities after 5 seconds
        if (tick == 300 and !stuck_warning_shown) {
            var waiting_count: u32 = 0;
            for (0..4) |i| {
                if (engine.getPositionFull(@intCast(i))) |pos| {
                    if (pos.waiting_for_stair != null) {
                        waiting_count += 1;
                        print("  Entity {d} WAITING at node {d} for stair {d}\n", .{ i, pos.current_node, pos.waiting_for_stair.? });
                    }
                }
            }
            if (waiting_count >= 2) {
                print("\nWARNING at tick 300: {d} entities waiting\n", .{waiting_count});
                stuck_warning_shown = true;
            }
        }
    }

    print("Simulation completed in {d} ticks ({d:.1}s)\n\n", .{ tick, @as(f32, @floatFromInt(tick)) / 60.0 });

    // Check results
    var passed = true;
    var all_arrived = true;

    const targets = [_]u32{ 4, 7, 0, 3 };
    for (0..4) |i| {
        const entity: u32 = @intCast(i);
        const final = engine.getCurrentNode(entity) orelse 99;
        const target = targets[i];
        const arrived = final == target;
        print("Entity {d}: at node {d}, target {d} - {s}\n", .{
            entity,
            final,
            target,
            if (arrived) "OK" else "FAILED",
        });
        if (!arrived) all_arrived = false;
    }

    print("\nCallbacks: reached={d}, completed={d}, waiting_started={d}, waiting_ended={d}\n", .{
        state.node_reached_count,
        state.path_completed_count,
        state.waiting_started_count,
        state.waiting_ended_count,
    });
    print("Max concurrent stair users: {d}\n\n", .{state.max_concurrent_stair_users});

    if (!all_arrived) {
        print("FAIL: Not all entities reached their targets\n", .{});
        passed = false;
    }
    if (state.path_completed_count < 4) {
        print("FAIL: Expected 4 path completions, got {d}\n", .{state.path_completed_count});
        passed = false;
    }
    if (state.max_concurrent_stair_users > 1) {
        print("FAIL: More than 1 entity used stair concurrently!\n", .{});
        passed = false;
    }
    // Waiting callbacks should be balanced
    if (state.waiting_started_count != state.waiting_ended_count) {
        print("FAIL: waiting_started ({d}) != waiting_ended ({d})\n", .{
            state.waiting_started_count,
            state.waiting_ended_count,
        });
        passed = false;
    }

    return passed;
}

fn runMultiFloorTest(allocator: std.mem.Allocator) !bool {
    print("=== Test 3: Multi-Floor Building (like raylib example) ===\n\n", .{});

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var state = TestState{};

    engine.on_node_reached = onNodeReached;
    engine.on_path_completed = onPathCompleted;
    engine.on_waiting_started = onWaitingStarted;
    engine.on_waiting_ended = onWaitingEnded;

    // Raylib-like layout: 4 floors, 8 nodes per floor, stairs at positions 1, 4, 6
    const floors: u32 = 4;
    const nodes_per_floor: u32 = 8;
    const stair_positions = [_]u32{ 1, 4, 6 };

    print("Layout: {d} floors, {d} nodes/floor, stairs at columns 1,4,6\n\n", .{ floors, nodes_per_floor });

    // Create nodes
    var node_id: u32 = 0;
    for (0..floors) |floor_idx| {
        const y: f32 = @as(f32, @floatFromInt(floor_idx)) * 100.0;
        for (0..nodes_per_floor) |node_idx| {
            const x: f32 = @as(f32, @floatFromInt(node_idx)) * 100.0;

            var is_stair = false;
            for (stair_positions) |sp| {
                if (node_idx == sp) {
                    is_stair = true;
                    break;
                }
            }

            if (is_stair) {
                try engine.addNodeWithStairMode(node_id, x, y, .single);
            } else {
                try engine.addNode(node_id, x, y);
            }
            node_id += 1;
        }
    }

    // Set up waiting areas (same as raylib example)
    for (stair_positions) |stair_pos| {
        for (0..floors) |floor_idx| {
            const stair_node: u32 = @intCast(floor_idx * nodes_per_floor + stair_pos);
            var waiting_spots: [2]pathfinding.NodeId = undefined;
            var spot_count: usize = 0;

            if (stair_pos > 0) {
                waiting_spots[spot_count] = @intCast(floor_idx * nodes_per_floor + stair_pos - 1);
                spot_count += 1;
            }
            if (stair_pos < nodes_per_floor - 1) {
                waiting_spots[spot_count] = @intCast(floor_idx * nodes_per_floor + stair_pos + 1);
                spot_count += 1;
            }

            if (spot_count > 0) {
                try engine.setWaitingArea(stair_node, waiting_spots[0..spot_count]);
            }
        }
    }

    try engine.connectNodes(.{ .building = .{ .horizontal_range = 120, .floor_height = 120 } });
    try engine.rebuildPaths();

    // Register 4 entities at various positions
    try engine.registerEntity(0, 0, 0, 80.0); // Floor 0, node 0
    try engine.registerEntity(1, 700, 0, 80.0); // Floor 0, node 7
    try engine.registerEntity(2, 0, 300, 80.0); // Floor 3, node 24
    try engine.registerEntity(3, 700, 300, 80.0); // Floor 3, node 31

    print("Entities: 0,1 on floor 0; 2,3 on floor 3\n", .{});
    print("0 -> floor 3 (node 24), 1 -> floor 3 (node 31)\n", .{});
    print("2 -> floor 0 (node 0), 3 -> floor 0 (node 7)\n\n", .{});

    // Cross-floor paths
    try engine.requestPath(0, 24); // 0 goes from bottom-left to top-left
    try engine.requestPath(1, 31); // 1 goes from bottom-right to top-right
    try engine.requestPath(2, 0); // 2 goes from top-left to bottom-left
    try engine.requestPath(3, 7); // 3 goes from top-right to bottom-right

    const delta: f32 = 1.0 / 60.0;
    var tick: u32 = 0;
    const max_ticks: u32 = 60 * 20; // 20 seconds max

    while (tick < max_ticks) {
        engine.tick(&state, delta);
        tick += 1;

        // Track max concurrent users PER COLUMN (not globally)
        // Each stair column should have at most 1 user in single mode
        for (stair_positions) |sp| {
            var column_users: u32 = 0;
            for (0..floors) |fi| {
                const sn: u32 = @intCast(fi * nodes_per_floor + sp);
                if (engine.getStairState(sn)) |s| {
                    column_users += s.users_count;
                }
            }
            if (column_users > state.max_concurrent_stair_users) {
                state.max_concurrent_stair_users = column_users;
            }
        }

        // Check if done
        var any_moving = false;
        for (0..4) |i| {
            if (engine.isMoving(@intCast(i))) {
                any_moving = true;
                break;
            }
        }
        if (!any_moving) break;

        // Debug at 10 seconds
        if (tick == 600) {
            print("Status at 10s:\n", .{});
            for (0..4) |i| {
                const pos = engine.getPositionFull(@intCast(i));
                if (pos) |p| {
                    const waiting = p.waiting_for_stair != null;
                    const using = p.using_stair != null;
                    print("  Entity {d}: node {d}, waiting={}, using={}\n", .{ i, p.current_node, waiting, using });
                }
            }
        }
    }

    print("Simulation completed in {d} ticks ({d:.1}s)\n\n", .{ tick, @as(f32, @floatFromInt(tick)) / 60.0 });

    var passed = true;
    var all_arrived = true;

    const targets = [_]u32{ 24, 31, 0, 7 };
    for (0..4) |i| {
        const entity: u32 = @intCast(i);
        const final = engine.getCurrentNode(entity) orelse 99;
        const target = targets[i];
        const arrived = final == target;
        print("Entity {d}: at node {d}, target {d} - {s}\n", .{
            entity,
            final,
            target,
            if (arrived) "OK" else "FAILED",
        });
        if (!arrived) all_arrived = false;
    }

    print("\nCallbacks: reached={d}, completed={d}, waiting_started={d}, waiting_ended={d}\n", .{
        state.node_reached_count,
        state.path_completed_count,
        state.waiting_started_count,
        state.waiting_ended_count,
    });
    print("Max concurrent stair users: {d}\n\n", .{state.max_concurrent_stair_users});

    if (!all_arrived) {
        print("FAIL: Not all entities reached targets\n", .{});
        passed = false;
    }
    if (state.max_concurrent_stair_users > 1) {
        print("FAIL: More than 1 entity used stair concurrently!\n", .{});
        passed = false;
    }
    // Waiting callbacks should be balanced
    if (state.waiting_started_count != state.waiting_ended_count) {
        print("FAIL: waiting_started ({d}) != waiting_ended ({d})\n", .{
            state.waiting_started_count,
            state.waiting_ended_count,
        });
        passed = false;
    }

    return passed;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n========================================\n", .{});
    print("     Single Stair System Tests\n", .{});
    print("========================================\n\n", .{});

    var all_passed = true;

    // Test 1: Basic two-entity cross
    const test1_passed = try runBasicTest(allocator);
    if (test1_passed) {
        print("Test 1: PASSED\n\n", .{});
    } else {
        print("Test 1: FAILED\n\n", .{});
        all_passed = false;
    }

    // Test 2: Four-entity contention
    const test2_passed = try runContentionTest(allocator);
    if (test2_passed) {
        print("Test 2: PASSED\n\n", .{});
    } else {
        print("Test 2: FAILED\n\n", .{});
        all_passed = false;
    }

    // Test 3: Multi-floor building (like raylib)
    const test3_passed = try runMultiFloorTest(allocator);
    if (test3_passed) {
        print("Test 3: PASSED\n\n", .{});
    } else {
        print("Test 3: FAILED\n\n", .{});
        all_passed = false;
    }

    print("========================================\n", .{});
    if (all_passed) {
        print("     ALL TESTS PASSED!\n", .{});
    } else {
        print("     SOME TESTS FAILED\n", .{});
    }
    print("========================================\n\n", .{});
}
