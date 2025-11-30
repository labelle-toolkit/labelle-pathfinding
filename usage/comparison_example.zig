//! Algorithm Comparison Example
//!
//! Compares Floyd-Warshall and A* algorithms side-by-side to help you
//! choose the right algorithm for your use case.
//!
//! Summary:
//! - Floyd-Warshall: O(n³) precomputation, O(1) queries - best for all-pairs
//! - A*: O(E log V) per query with heuristic - best for single-source

const std = @import("std");
const pathfinding = @import("pathfinding");

const Position = pathfinding.Position;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Algorithm Comparison Example ===\n\n", .{});

    // Create a test graph: 5x5 grid (25 nodes)
    const grid_size: u32 = 5;
    const num_nodes: u32 = grid_size * grid_size;

    print("Test Graph: {d}x{d} grid ({d} nodes)\n", .{ grid_size, grid_size, num_nodes });
    print("Finding path from (0,0) to ({d},{d})\n\n", .{ grid_size - 1, grid_size - 1 });

    // ===== Floyd-Warshall =====
    print("--- Floyd-Warshall Algorithm ---\n", .{});
    print("Characteristics:\n", .{});
    print("  - Precomputes ALL shortest paths\n", .{});
    print("  - Time: O(n^3) setup, O(1) queries\n", .{});
    print("  - Space: O(n^2)\n", .{});
    print("  - Best for: Dense graphs, many queries, static graphs\n\n", .{});

    var fw = pathfinding.FloydWarshall.init(allocator);
    defer fw.deinit();

    fw.resize(num_nodes);
    try fw.clean();

    // Build grid graph for Floyd-Warshall
    for (0..grid_size) |y| {
        for (0..grid_size) |x| {
            const id: u32 = @intCast(y * grid_size + x);

            if (x < grid_size - 1) {
                const right: u32 = @intCast(y * grid_size + x + 1);
                fw.addEdgeWithMapping(id, right, 1);
                fw.addEdgeWithMapping(right, id, 1);
            }

            if (y < grid_size - 1) {
                const down: u32 = @intCast((y + 1) * grid_size + x);
                fw.addEdgeWithMapping(id, down, 1);
                fw.addEdgeWithMapping(down, id, 1);
            }
        }
    }

    // Time the precomputation
    var timer = try std.time.Timer.start();
    fw.generate();
    const fw_setup_time = timer.read();

    // Time a query
    timer.reset();
    const start: u32 = 0;
    const goal: u32 = num_nodes - 1;
    const fw_distance = fw.valueWithMapping(start, goal);
    const fw_query_time = timer.read();

    var fw_path = std.array_list.Managed(u32).init(allocator);
    defer fw_path.deinit();
    try fw.setPathWithMapping(&fw_path, start, goal);

    print("Results:\n", .{});
    print("  Setup time: {d:.3}ms\n", .{@as(f64, @floatFromInt(fw_setup_time)) / 1_000_000.0});
    print("  Query time: {d:.3}us\n", .{@as(f64, @floatFromInt(fw_query_time)) / 1_000.0});
    print("  Distance: {d}\n", .{fw_distance});
    print("  Path length: {d} nodes\n\n", .{fw_path.items.len});

    // ===== A* Algorithm =====
    print("--- A* Algorithm (Euclidean heuristic) ---\n", .{});
    print("Characteristics:\n", .{});
    print("  - Computes paths on-demand\n", .{});
    print("  - Time: O(E log V) per query\n", .{});
    print("  - Space: O(V + E)\n", .{});
    print("  - Best for: Sparse graphs, few queries, dynamic graphs\n\n", .{});

    var astar = pathfinding.AStar.init(allocator);
    defer astar.deinit();

    astar.resize(num_nodes);
    try astar.clean();
    astar.setHeuristic(.euclidean);

    // Build grid graph for A*
    timer.reset();
    for (0..grid_size) |y| {
        for (0..grid_size) |x| {
            const id: u32 = @intCast(y * grid_size + x);
            const pos = Position{
                .x = @floatFromInt(x),
                .y = @floatFromInt(y),
            };
            try astar.setNodePositionWithMapping(id, pos);

            if (x < grid_size - 1) {
                const right: u32 = @intCast(y * grid_size + x + 1);
                astar.addEdgeWithMapping(id, right, 1);
                astar.addEdgeWithMapping(right, id, 1);
            }

            if (y < grid_size - 1) {
                const down: u32 = @intCast((y + 1) * grid_size + x);
                astar.addEdgeWithMapping(id, down, 1);
                astar.addEdgeWithMapping(down, id, 1);
            }
        }
    }
    const astar_setup_time = timer.read();

    // Time a query
    var astar_path = std.array_list.Managed(u32).init(allocator);
    defer astar_path.deinit();

    timer.reset();
    const astar_cost = try astar.findPathWithMapping(start, goal, &astar_path);
    const astar_query_time = timer.read();

    print("Results:\n", .{});
    print("  Setup time: {d:.3}ms\n", .{@as(f64, @floatFromInt(astar_setup_time)) / 1_000_000.0});
    print("  Query time: {d:.3}us\n", .{@as(f64, @floatFromInt(astar_query_time)) / 1_000.0});
    print("  Distance: {d}\n", .{astar_cost.?});
    print("  Path length: {d} nodes\n\n", .{astar_path.items.len});

    // ===== Comparison Summary =====
    print("--- Comparison Summary ---\n", .{});
    print("Both algorithms found the same distance: {d}\n\n", .{fw_distance});

    print("When to use Floyd-Warshall:\n", .{});
    print("  - You need paths between many different node pairs\n", .{});
    print("  - The graph is relatively small (< 1000 nodes)\n", .{});
    print("  - The graph structure doesn't change often\n", .{});
    print("  - Memory isn't a major constraint\n\n", .{});

    print("When to use A*:\n", .{});
    print("  - You only need paths from one source at a time\n", .{});
    print("  - The graph is large and sparse\n", .{});
    print("  - The graph changes frequently\n", .{});
    print("  - You have good spatial information for heuristics\n", .{});
    print("  - Memory efficiency is important\n\n", .{});

    // ===== Heuristic Comparison =====
    print("--- A* Heuristic Comparison ---\n", .{});

    const heuristics = [_]struct { h: pathfinding.Heuristic, name: []const u8 }{
        .{ .h = .euclidean, .name = "Euclidean" },
        .{ .h = .manhattan, .name = "Manhattan" },
        .{ .h = .chebyshev, .name = "Chebyshev" },
        .{ .h = .octile, .name = "Octile" },
        .{ .h = .zero, .name = "Zero (Dijkstra)" },
    };

    for (heuristics) |h| {
        astar.setHeuristic(h.h);
        astar_path.clearRetainingCapacity();

        timer.reset();
        _ = try astar.findPathWithMapping(start, goal, &astar_path);
        const query_time = timer.read();

        print("  {s}: {d:.3}us\n", .{ h.name, @as(f64, @floatFromInt(query_time)) / 1_000.0 });
    }

    print("\n=== Comparison Example Complete ===\n\n", .{});
}
