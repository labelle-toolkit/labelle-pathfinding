//! Floyd-Warshall Algorithm Usage Example
//!
//! Demonstrates the Floyd-Warshall all-pairs shortest path algorithm.
//! Best for: Dense graphs, when you need paths between many node pairs,
//! or when the graph doesn't change frequently.

const std = @import("std");
const pathfinding = @import("pathfinding");

const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Floyd-Warshall Algorithm Example ===\n\n", .{});

    // Initialize Floyd-Warshall
    var fw = pathfinding.FloydWarshall.init(allocator);
    defer fw.deinit();

    // Example: A small city road network
    // Nodes represent intersections, edges represent roads with travel times
    //
    //     [A:100] --5-- [B:200] --3-- [C:300]
    //        |            |            |
    //        2            4            2
    //        |            |            |
    //     [D:400] --6-- [E:500] --1-- [F:600]
    //
    print("City Road Network:\n", .{});
    print("  [A] --5-- [B] --3-- [C]\n", .{});
    print("   |         |         |\n", .{});
    print("   2         4         2\n", .{});
    print("   |         |         |\n", .{});
    print("  [D] --6-- [E] --1-- [F]\n\n", .{});

    // Resize and clean for 6 nodes
    fw.resize(6);
    try fw.clean();

    // Define entity IDs for each intersection
    const A: u32 = 100;
    const B: u32 = 200;
    const C: u32 = 300;
    const D: u32 = 400;
    const E: u32 = 500;
    const F: u32 = 600;

    // Add bidirectional roads (edges in both directions)
    // Row 1: A-B-C
    fw.addEdgeWithMapping(A, B, 5);
    fw.addEdgeWithMapping(B, A, 5);
    fw.addEdgeWithMapping(B, C, 3);
    fw.addEdgeWithMapping(C, B, 3);

    // Row 2: D-E-F
    fw.addEdgeWithMapping(D, E, 6);
    fw.addEdgeWithMapping(E, D, 6);
    fw.addEdgeWithMapping(E, F, 1);
    fw.addEdgeWithMapping(F, E, 1);

    // Vertical connections
    fw.addEdgeWithMapping(A, D, 2);
    fw.addEdgeWithMapping(D, A, 2);
    fw.addEdgeWithMapping(B, E, 4);
    fw.addEdgeWithMapping(E, B, 4);
    fw.addEdgeWithMapping(C, F, 2);
    fw.addEdgeWithMapping(F, C, 2);

    // Generate all shortest paths (O(n³) - done once)
    print("Computing all-pairs shortest paths...\n", .{});
    fw.generate();
    print("Done! All paths pre-computed.\n\n", .{});

    // Query paths (O(1) lookup after generation)
    print("Shortest distances:\n", .{});
    print("  A -> F: {d} (expected: 5, via A->D->E->F or A->B->C->F)\n", .{fw.valueWithMapping(A, F)});
    print("  A -> C: {d} (expected: 8, via A->B->C)\n", .{fw.valueWithMapping(A, C)});
    print("  D -> C: {d} (expected: 9, via D->E->F->C)\n", .{fw.valueWithMapping(D, C)});
    print("  A -> E: {d} (expected: 8, via A->D->E)\n", .{fw.valueWithMapping(A, E)});

    // Path reconstruction
    print("\nPath reconstruction (A -> F):\n", .{});
    var path = std.array_list.Managed(u32).init(allocator);
    defer path.deinit();

    try fw.setPathWithMapping(&path, A, F);

    print("  Path: ", .{});
    for (path.items, 0..) |node, i| {
        const name: []const u8 = switch (node) {
            100 => "A",
            200 => "B",
            300 => "C",
            400 => "D",
            500 => "E",
            600 => "F",
            else => "?",
        };
        if (i > 0) print(" -> ", .{});
        print("{s}", .{name});
    }
    print("\n", .{});

    // Check path existence
    print("\nPath existence checks:\n", .{});
    print("  A -> F exists: {}\n", .{fw.hasPathWithMapping(A, F)});
    print("  B -> D exists: {}\n", .{fw.hasPathWithMapping(B, D)});

    // Next hop queries (useful for step-by-step navigation)
    print("\nNext hop queries:\n", .{});
    const next_from_a = fw.nextWithMapping(A, F);
    const next_name: []const u8 = switch (next_from_a) {
        100 => "A",
        200 => "B",
        300 => "C",
        400 => "D",
        500 => "E",
        600 => "F",
        else => "?",
    };
    print("  From A to F, next hop: {s}\n", .{next_name});

    print("\n=== Floyd-Warshall Example Complete ===\n\n", .{});
}
