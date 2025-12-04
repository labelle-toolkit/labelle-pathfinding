//! Single Stair Mode Example
//!
//! Demonstrates the `.single` stair mode which enforces single-lane traffic
//! on staircases. Only one entity can use the stair at a time, and others
//! must wait at designated waiting areas.
//!
//! This example shows:
//! - Setting up stairs with `.single` mode
//! - Configuring waiting areas for entities queuing at stairs
//! - Multiple entities navigating through restricted stairs
//! - Stair occupancy state inspection
//!
//! Run with: zig build run-single-stair

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

const Config = struct {
    pub const Entity = u32;
    pub const Context = *GameState;
    pub const log_level: pathfinding.LogLevel = .info;
};

const Engine = pathfinding.PathfindingEngine(Config);

const GameState = struct {
    tick_count: u32 = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Single Stair Mode Example ===\n\n", .{});
    print("This example demonstrates `.single` stair mode which allows only\n", .{});
    print("one entity on the stair at a time. Other entities wait in queue.\n\n", .{});

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    var game_state = GameState{};

    // ===== Build a simple two-floor layout =====
    //
    //   FLOOR 2 (y = 100):
    //   [4]----------[5]----------[6]
    //    x=0        x=200        x=300
    //                 |
    //              stair (single mode)
    //                 |
    //   FLOOR 1 (y = 0):
    //   [0]----[1]----[2]----[3]
    //    x=0   x=100  x=200  x=300
    //          wait   stair
    //          area
    //
    // Node 2 and 5 are the stair nodes (single mode) - vertically connected
    // Node 1 is a waiting area for entities queuing to go up

    print("1. Building layout:\n\n", .{});
    print("   FLOOR 2:  [4]----------[5]----------[6]\n", .{});
    print("                          |\n", .{});
    print("                       (stair)\n", .{});
    print("                          |\n", .{});
    print("   FLOOR 1:  [0]----[1]----[2]----[3]\n", .{});
    print("                   wait   stair\n", .{});
    print("                   area\n\n", .{});

    // Floor 1 nodes
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 100, 0); // Waiting area
    try engine.addNodeWithStairMode(2, 200, 0, .single); // Single-mode stair (bottom)
    try engine.addNode(3, 300, 0);

    // Floor 2 nodes
    try engine.addNode(4, 0, 100);
    try engine.addNodeWithStairMode(5, 200, 100, .single); // Single-mode stair (top)
    try engine.addNode(6, 300, 100);

    // Set up waiting areas
    // When approaching stair 5 (going UP from floor 1), entities wait at nodes below
    try engine.setWaitingArea(5, &[_]pathfinding.NodeId{
        1, // Wait at node 1
        0, // Or node 0
    });
    // When approaching stair 2 (going DOWN from floor 2), entities wait at nodes above
    try engine.setWaitingArea(2, &[_]pathfinding.NodeId{
        4, // Wait at node 4 on floor 2
    });

    // Connect using building mode
    try engine.connectNodes(.{
        .building = .{
            .horizontal_range = 120,
            .floor_height = 120,
        },
    });
    try engine.rebuildPaths();

    print("   Stair mode at node 2: {s}\n", .{@tagName(engine.getStairMode(2))});
    print("   Stair mode at node 5: {s}\n", .{@tagName(engine.getStairMode(5))});
    print("   Waiting area for stair 5: nodes 1, 0 (for entities going UP)\n\n", .{});

    // ===== Register multiple entities =====
    print("2. Registering 3 entities on Floor 1:\n\n", .{});

    const entity_a: u32 = 1;
    const entity_b: u32 = 2;
    const entity_c: u32 = 3;

    try engine.registerEntity(entity_a, 0, 0, 60.0);
    try engine.registerEntity(entity_b, 100, 0, 60.0);
    try engine.registerEntity(entity_c, 300, 0, 60.0);

    print("   Entity A (id=1) at node 0, speed=60\n", .{});
    print("   Entity B (id=2) at node 1, speed=60\n", .{});
    print("   Entity C (id=3) at node 3, speed=60\n\n", .{});

    // ===== All entities want to go to Floor 2 =====
    print("3. All entities request path to node 6 (Floor 2, right side):\n\n", .{});

    try engine.requestPath(entity_a, 6);
    try engine.requestPath(entity_b, 6);
    try engine.requestPath(entity_c, 6);

    print("   All 3 entities must pass through the single-mode stair.\n", .{});
    print("   Only one can use it at a time - others will wait.\n\n", .{});

    // ===== Simulate movement =====
    print("4. Movement simulation:\n\n", .{});
    print("   {s:^6} | {s:^8} | {s:^8} | {s:^8} | {s:^12}\n", .{ "Tick", "Entity A", "Entity B", "Entity C", "Stair State" });
    print("   {s:-^6}-+-{s:-^8}-+-{s:-^8}-+-{s:-^8}-+-{s:-^12}\n", .{ "", "", "", "", "" });

    var tick: u32 = 0;
    var last_state: struct { a: u32, b: u32, c: u32 } = .{ .a = 0, .b = 0, .c = 0 };

    while ((engine.isMoving(entity_a) or engine.isMoving(entity_b) or engine.isMoving(entity_c)) and tick < 500) {
        engine.tick(&game_state, 0.1);
        tick += 1;

        const node_a = engine.getCurrentNode(entity_a) orelse 99;
        const node_b = engine.getCurrentNode(entity_b) orelse 99;
        const node_c = engine.getCurrentNode(entity_c) orelse 99;

        // Print when any entity changes node or every 20 ticks
        if (node_a != last_state.a or node_b != last_state.b or node_c != last_state.c or tick % 20 == 0) {
            // Get stair state (check both bottom and top stair nodes)
            const state_2 = engine.getStairState(2);
            const state_5 = engine.getStairState(5);
            const users_2: u32 = if (state_2) |s| s.users_count else 0;
            const users_5: u32 = if (state_5) |s| s.users_count else 0;

            var stair_buf: [24]u8 = undefined;
            const stair_str = std.fmt.bufPrint(&stair_buf, "s2:{d} s5:{d}", .{ users_2, users_5 }) catch "?";

            // Check for waiting entities (use getPositionFull to access waiting state)
            const pos_a = engine.getPositionFull(entity_a);
            const pos_b = engine.getPositionFull(entity_b);
            const pos_c = engine.getPositionFull(entity_c);

            const wait_a = if (pos_a) |p| p.waiting_for_stair != null else false;
            const wait_b = if (pos_b) |p| p.waiting_for_stair != null else false;
            const wait_c = if (pos_c) |p| p.waiting_for_stair != null else false;

            var buf_a: [16]u8 = undefined;
            var buf_b: [16]u8 = undefined;
            var buf_c: [16]u8 = undefined;

            const str_a = if (wait_a)
                std.fmt.bufPrint(&buf_a, "n{d} WAIT", .{node_a}) catch "?"
            else
                std.fmt.bufPrint(&buf_a, "node {d}", .{node_a}) catch "?";

            const str_b = if (wait_b)
                std.fmt.bufPrint(&buf_b, "n{d} WAIT", .{node_b}) catch "?"
            else
                std.fmt.bufPrint(&buf_b, "node {d}", .{node_b}) catch "?";

            const str_c = if (wait_c)
                std.fmt.bufPrint(&buf_c, "n{d} WAIT", .{node_c}) catch "?"
            else
                std.fmt.bufPrint(&buf_c, "node {d}", .{node_c}) catch "?";

            print("   {d:^6} | {s:^8} | {s:^8} | {s:^8} | {s:^12}\n", .{
                tick,
                str_a,
                str_b,
                str_c,
                stair_str,
            });

            last_state = .{ .a = node_a, .b = node_b, .c = node_c };
        }
    }

    // ===== Final state =====
    print("\n5. Final state:\n\n", .{});

    const final_a = engine.getCurrentNode(entity_a) orelse 99;
    const final_b = engine.getCurrentNode(entity_b) orelse 99;
    const final_c = engine.getCurrentNode(entity_c) orelse 99;

    print("   Entity A at node {d} (target was 6): {s}\n", .{
        final_a,
        if (final_a == 6) "SUCCESS" else "in progress",
    });
    print("   Entity B at node {d} (target was 6): {s}\n", .{
        final_b,
        if (final_b == 6) "SUCCESS" else "in progress",
    });
    print("   Entity C at node {d} (target was 6): {s}\n", .{
        final_c,
        if (final_c == 6) "SUCCESS" else "in progress",
    });
    print("   Total ticks: {d}\n\n", .{tick});

    // ===== Demonstrate stair mode comparison =====
    print("6. Stair Mode Comparison:\n\n", .{});
    print("   | Mode       | Concurrent Usage | Best For                    |\n", .{});
    print("   |------------|------------------|-----------------------------|\n", .{});
    print("   | .none      | N/A (not a stair)| Regular floor nodes         |\n", .{});
    print("   | .all       | Unlimited        | Wide staircases, escalators |\n", .{});
    print("   | .direction | Same direction   | Narrow two-way stairs       |\n", .{});
    print("   | .single    | One at a time    | Ladders, tight spaces       |\n", .{});

    print("\n=== Single Stair Example Complete ===\n\n", .{});
}
