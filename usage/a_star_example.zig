//! A* Algorithm Usage Example
//!
//! Demonstrates the A* single-source shortest path algorithm with
//! all available heuristics: Euclidean, Manhattan, Chebyshev, Octile, and Zero.
//! Best for: Real-time games, large sparse graphs, single-source queries.

const std = @import("std");
const pathfinding = @import("pathfinding");

const Position = pathfinding.Position;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== A* Algorithm Example ===\n\n", .{});

    // Example: A grid-based game map
    // Positions represent coordinates, edges represent walkable paths
    //
    //   (0,0)----(1,0)----(2,0)----(3,0)
    //     |        |        |        |
    //   (0,1)----(1,1)----(2,1)----(3,1)
    //     |        |        |        |
    //   (0,2)----(1,2)----(2,2)----(3,2)
    //     |        |        |        |
    //   (0,3)----(1,3)----(2,3)----(3,3)
    //
    print("4x4 Grid Map:\n", .{});
    print("  (0,0)----(1,0)----(2,0)----(3,0)\n", .{});
    print("    |        |        |        |\n", .{});
    print("  (0,1)----(1,1)----(2,1)----(3,1)\n", .{});
    print("    |        |        |        |\n", .{});
    print("  (0,2)----(1,2)----(2,2)----(3,2)\n", .{});
    print("    |        |        |        |\n", .{});
    print("  (0,3)----(1,3)----(2,3)----(3,3)\n\n", .{});

    // Test each heuristic
    try testHeuristic(allocator, .euclidean, "Euclidean (any-angle movement)");
    try testHeuristic(allocator, .manhattan, "Manhattan (4-directional grid)");
    try testHeuristic(allocator, .chebyshev, "Chebyshev (8-dir, equal diagonal cost)");
    try testHeuristic(allocator, .octile, "Octile (8-dir, sqrt(2) diagonal cost)");
    try testHeuristic(allocator, .zero, "Zero (Dijkstra's algorithm)");

    print("=== A* Example Complete ===\n\n", .{});
}

fn testHeuristic(
    allocator: std.mem.Allocator,
    heuristic: pathfinding.Heuristic,
    name: []const u8,
) !void {
    print("--- Heuristic: {s} ---\n", .{name});

    var astar = pathfinding.AStar.init(allocator);
    defer astar.deinit();

    // Set the heuristic
    astar.setHeuristic(heuristic);

    // Create a 4x4 grid (16 nodes)
    astar.resize(16);
    try astar.clean();

    // Entity IDs based on grid position: id = y * 4 + x
    // Set node positions for heuristic calculation
    for (0..4) |y| {
        for (0..4) |x| {
            const id: u32 = @intCast(y * 4 + x);
            const pos = Position{
                .x = @floatFromInt(x),
                .y = @floatFromInt(y),
            };
            try astar.setNodePositionWithMapping(id, pos);
        }
    }

    // Add 4-directional edges (cost = 1 for cardinal moves)
    for (0..4) |y| {
        for (0..4) |x| {
            const id: u32 = @intCast(y * 4 + x);

            // Right neighbor
            if (x < 3) {
                const right: u32 = @intCast(y * 4 + x + 1);
                astar.addEdgeWithMapping(id, right, 1);
                astar.addEdgeWithMapping(right, id, 1);
            }

            // Down neighbor
            if (y < 3) {
                const down: u32 = @intCast((y + 1) * 4 + x);
                astar.addEdgeWithMapping(id, down, 1);
                astar.addEdgeWithMapping(down, id, 1);
            }
        }
    }

    // Find path from (0,0) to (3,3)
    const start: u32 = 0; // (0,0)
    const goal: u32 = 15; // (3,3)

    var path = std.array_list.Managed(u32).init(allocator);
    defer path.deinit();

    const cost = try astar.findPathWithMapping(start, goal, &path);

    if (cost) |c| {
        print("  Path from (0,0) to (3,3): cost = {d}\n", .{c});
        print("  Path: ", .{});
        for (path.items, 0..) |node, i| {
            const x = node % 4;
            const y = node / 4;
            if (i > 0) print(" -> ", .{});
            print("({d},{d})", .{ x, y });
        }
        print("\n", .{});
    } else {
        print("  No path found!\n", .{});
    }

    // Also test a shorter path
    const mid_goal: u32 = 5; // (1,1)
    path.clearRetainingCapacity();
    const mid_cost = try astar.findPathWithMapping(start, mid_goal, &path);

    if (mid_cost) |c| {
        print("  Path from (0,0) to (1,1): cost = {d}\n", .{c});
    }

    print("\n", .{});
}
