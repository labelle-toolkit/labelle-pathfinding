//! Platformer Pathfinding Example
//!
//! Demonstrates directional connections for platformer-style games
//! where movement is constrained to left/right/up/down directions.

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

const Config = struct {
    pub const Entity = u32;
    pub const Context = *anyopaque;
};

const Engine = pathfinding.PathfindingEngine(Config);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Platformer Pathfinding Example ===\n\n", .{});

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // ===== Build a platformer level =====
    print("1. Building platformer level...\n\n", .{});

    // Level layout with platforms:
    //
    //   [0]----[1]----[2]     <- Top platform
    //           |
    //   [3]----[4]----[5]     <- Middle platform (connected by ladder at 1-4)
    //           |
    //          [6]----[7]     <- Bottom platform (connected by ladder at 4-6)
    //
    // Horizontal range = 60 (connects adjacent nodes on same platform)
    // Vertical range = 60 (connects nodes on different platforms via ladder)

    // Top platform (y = 0)
    try engine.addNode(0, 0, 0);
    try engine.addNode(1, 50, 0);
    try engine.addNode(2, 100, 0);

    // Middle platform (y = 50)
    try engine.addNode(3, 0, 50);
    try engine.addNode(4, 50, 50);
    try engine.addNode(5, 100, 50);

    // Bottom platform (y = 100)
    try engine.addNode(6, 50, 100);
    try engine.addNode(7, 100, 100);

    print("   Created 8 waypoints across 3 platforms\n", .{});

    // Connect using directional mode (platformer-style)
    try engine.connectNodes(.{
        .directional = .{
            .horizontal_range = 60, // Connect nodes within 60 units horizontally
            .vertical_range = 60, // Connect nodes within 60 units vertically (ladders)
        },
    });
    try engine.rebuildPaths();

    print("   Connected with directional mode\n\n", .{});

    // ===== Show directional connections =====
    print("2. Directional connections per node:\n\n", .{});

    for (0..8) |i| {
        const node_id: pathfinding.NodeId = @intCast(i);
        if (engine.getDirectionalEdges(node_id)) |edges| {
            const pos = engine.getNodePosition(node_id).?;
            print("   Node {d} at ({d:.0}, {d:.0}):\n", .{ node_id, pos.x, pos.y });

            if (edges.left) |l| print("     Left -> {d}\n", .{l});
            if (edges.right) |r| print("     Right -> {d}\n", .{r});
            if (edges.up) |u| print("     Up -> {d}\n", .{u});
            if (edges.down) |d| print("     Down -> {d}\n", .{d});

            if (edges.left == null and edges.right == null and edges.up == null and edges.down == null) {
                print("     (no connections)\n", .{});
            }
        }
    }

    // ===== Add one-way drop-down =====
    print("\n3. Adding one-way drop-down from node 2 to 5...\n\n", .{});

    try engine.addEdge(2, 5, false); // One-way: can drop down but not climb up
    try engine.rebuildPaths();

    print("   Added one-way edge (2 -> 5)\n", .{});

    // ===== Entity movement =====
    print("\n4. Entity movement test...\n\n", .{});

    const player: u32 = 1;
    try engine.registerEntity(player, 0, 0, 100.0); // Start at top-left

    print("   Player starting at node 0 (top-left)\n", .{});

    // Move to bottom-right
    try engine.requestPath(player, 7);
    print("   Requested path to node 7 (bottom-right)\n", .{});

    // Simulate movement
    var tick: u32 = 0;
    var dummy: u32 = 0;

    print("\n   Movement trace:\n", .{});
    while (engine.isMoving(player) and tick < 100) {
        engine.tick(&dummy, 0.1);
        tick += 1;

        if (tick % 5 == 0) {
            const pos = engine.getPosition(player).?;
            const node = engine.getCurrentNode(player).?;
            print("   Tick {d:2}: pos=({d:5.1}, {d:5.1}), node={d}\n", .{ tick, pos.x, pos.y, node });
        }
    }

    const final_pos = engine.getPosition(player).?;
    print("\n   Final position: ({d:.0}, {d:.0})\n", .{ final_pos.x, final_pos.y });

    print("\n=== Platformer Example Complete ===\n\n", .{});
}
