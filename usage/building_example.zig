//! Building Pathfinding Example with Stairs
//!
//! Demonstrates a two-floor building with two staircases using the
//! building connection mode and stair traffic management.

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

const Config = struct {
    pub const Entity = u32;
    pub const Context = *anyopaque;
    pub const log_level: pathfinding.LogLevel = .info;
};

const Engine = pathfinding.PathfindingEngine(Config);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Building Pathfinding Example (Two Floors, Two Stairs) ===\n\n", .{});

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    // ===== Build a two-floor building =====
    print("1. Building layout...\n\n", .{});

    // Building layout:
    //
    //   FLOOR 1 (y = 0):
    //   [0]----[1]----[2]----[3]----[4]
    //           |                    |
    //         stair               stair
    //           |                    |
    //   FLOOR 2 (y = 100):
    //   [5]----[6]----[7]----[8]----[9]
    //
    // Node 1 and 6 are connected via left stair (multi-lane)
    // Node 4 and 9 are connected via right stair (multi-lane)

    // Floor 1 (y = 0)
    try engine.addNode(0, 0, 0);
    try engine.addNodeWithStairMode(1, 100, 0, .all); // Left stair (multi-lane, no restrictions)
    try engine.addNode(2, 200, 0);
    try engine.addNode(3, 300, 0);
    try engine.addNodeWithStairMode(4, 400, 0, .all); // Right stair (multi-lane)

    // Floor 2 (y = 100)
    try engine.addNode(5, 0, 100);
    try engine.addNodeWithStairMode(6, 100, 100, .all); // Left stair bottom
    try engine.addNode(7, 200, 100);
    try engine.addNode(8, 300, 100);
    try engine.addNodeWithStairMode(9, 400, 100, .all); // Right stair bottom

    print("   Floor 1: nodes 0-4 (y=0)\n", .{});
    print("   Floor 2: nodes 5-9 (y=100)\n", .{});
    print("   Left stair: nodes 1 <-> 6 (multi-lane mode)\n", .{});
    print("   Right stair: nodes 4 <-> 9 (multi-lane mode)\n\n", .{});

    // Connect using building mode
    try engine.connectNodes(.{
        .building = .{
            .horizontal_range = 120, // Connect adjacent nodes on same floor
            .floor_height = 120, // Connect stairs between floors
        },
    });
    try engine.rebuildPaths();

    print("   Connected with building mode\n\n", .{});

    // ===== Show connections =====
    print("2. Node connections:\n\n", .{});

    for (0..10) |i| {
        const node_id: pathfinding.NodeId = @intCast(i);
        const pos = engine.getNodePosition(node_id).?;
        const stair_mode = engine.getStairMode(node_id);

        const floor: u8 = if (pos.y < 50) 1 else 2;
        const stair_str: []const u8 = switch (stair_mode) {
            .none => "",
            .single => " [STAIR:single]",
            .direction => " [STAIR:direction]",
            .all => " [STAIR:multi-lane]",
        };

        print("   Node {d} - Floor {d}, x={d:.0}{s}\n", .{ node_id, floor, pos.x, stair_str });

        if (engine.getDirectionalEdges(node_id)) |edges| {
            if (edges.left) |l| print("     <- Left: node {d}\n", .{l});
            if (edges.right) |r| print("     -> Right: node {d}\n", .{r});
            if (edges.up) |u| print("     ^ Up: node {d}\n", .{u});
            if (edges.down) |d| print("     v Down: node {d}\n", .{d});
        }
    }

    // ===== Entity movement between floors =====
    print("\n3. Entity movement from Floor 1 to Floor 2...\n\n", .{});

    const worker: u32 = 1;

    // Start at node 0 (floor 1, left side)
    try engine.registerEntity(worker, 0, 0, 80.0);
    print("   Worker registered at node 0 (Floor 1, left side)\n", .{});

    // Request path to node 8 (floor 2, right side) - must use a stair
    try engine.requestPath(worker, 8);
    print("   Requested path to node 8 (Floor 2, right side)\n", .{});
    print("   Worker must traverse a staircase to reach Floor 2\n\n", .{});

    // Simulate movement
    print("   Movement trace:\n", .{});
    print("   {s:^6} | {s:^12} | {s:^6} | {s:^8}\n", .{ "Tick", "Position", "Node", "Floor" });
    print("   {s:-^6}-+-{s:-^12}-+-{s:-^6}-+-{s:-^8}\n", .{ "", "", "", "" });

    var tick: u32 = 0;
    var dummy: u32 = 0;
    var last_node: pathfinding.NodeId = 0;

    while (engine.isMoving(worker) and tick < 200) {
        engine.tick(&dummy, 0.1);
        tick += 1;

        const current_node = engine.getCurrentNode(worker).?;

        // Print when node changes or every 10 ticks
        if (current_node != last_node or tick % 20 == 0) {
            const pos = engine.getPosition(worker).?;
            const floor: u8 = if (pos.y < 50) 1 else 2;

            print("   {d:^6} | ({d:5.1}, {d:5.1}) | {d:^6} | {d:^8}\n", .{
                tick,
                pos.x,
                pos.y,
                current_node,
                floor,
            });

            if (current_node != last_node) {
                const stair_mode = engine.getStairMode(current_node);
                if (stair_mode != .none) {
                    print("          ^ Passing through stair node!\n", .{});
                }
            }

            last_node = current_node;
        }
    }

    const final_pos = engine.getPosition(worker).?;
    const final_node = engine.getCurrentNode(worker).?;
    const final_floor: u8 = if (final_pos.y < 50) 1 else 2;

    print("\n   Journey complete!\n", .{});
    print("   Final: node {d}, Floor {d}, position ({d:.0}, {d:.0})\n", .{
        final_node,
        final_floor,
        final_pos.x,
        final_pos.y,
    });
    print("   Total ticks: {d}\n", .{tick});

    print("\n=== Building Example Complete ===\n\n", .{});
}
