//! Optimized Floyd-Warshall Algorithm Implementation
//!
//! High-performance implementation with:
//! - Flat memory layout for cache efficiency
//! - SIMD vectorization for inner loop operations
//! - Multi-threaded parallelization across rows
//!
//! This module re-exports the zig-utils optimized Floyd-Warshall implementation.
//! For graphs that change infrequently but require many arbitrary
//! source-destination queries.

const std = @import("std");
const zig_utils = @import("zig_utils");

const INF: u32 = std.math.maxInt(u32);

/// Configuration for the optimized Floyd-Warshall algorithm
/// Re-exported from zig-utils for compatibility.
pub const Config = zig_utils.floyd_warshall_optimized.Config;

/// Optimized Floyd-Warshall all-pairs shortest path algorithm.
/// Re-exported from zig-utils. Uses flat memory layout, SIMD, and multi-threading for performance.
pub const FloydWarshallOptimized = zig_utils.floyd_warshall_optimized.FloydWarshallOptimized;

/// Parallel + SIMD optimized Floyd-Warshall (best for large graphs 256+ nodes)
/// Uses multi-threading with row decomposition and SIMD vectorization within each thread.
pub const FloydWarshallParallel = zig_utils.FloydWarshallParallel;

/// SIMD-only version (no threading overhead for smaller graphs)
pub const FloydWarshallSimd = zig_utils.FloydWarshallSimd;

/// Scalar version (for comparison/debugging)
pub const FloydWarshallScalar = zig_utils.FloydWarshallScalar;

// Unit tests to verify the re-exported types work correctly
test "FloydWarshallOptimized basic functionality" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    // Create graph: 0 -> 1 -> 2 -> 3
    fw.addEdge(0, 1, 1);
    fw.addEdge(1, 2, 1);
    fw.addEdge(2, 3, 1);

    fw.generate();

    // Check distances
    try std.testing.expectEqual(@as(u32, 0), fw.value(0, 0));
    try std.testing.expectEqual(@as(u32, 1), fw.value(0, 1));
    try std.testing.expectEqual(@as(u32, 2), fw.value(0, 2));
    try std.testing.expectEqual(@as(u32, 3), fw.value(0, 3));

    // Check next hops
    try std.testing.expectEqual(@as(u32, 1), fw.getNext(0, 3));
    try std.testing.expectEqual(@as(u32, 2), fw.getNext(1, 3));
}

test "FloydWarshallOptimized with entity mapping" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    // Use entity IDs: 100 -> 200 -> 300 -> 400
    try fw.addEdgeWithMapping(100, 200, 1);
    try fw.addEdgeWithMapping(200, 300, 1);
    try fw.addEdgeWithMapping(300, 400, 1);

    fw.generate();

    // Check paths exist
    try std.testing.expect(fw.hasPathWithMapping(100, 400));
    try std.testing.expect(fw.hasPathWithMapping(100, 200));

    // Check distances
    try std.testing.expectEqual(@as(u32, 1), fw.valueWithMapping(100, 200));
    try std.testing.expectEqual(@as(u32, 3), fw.valueWithMapping(100, 400));

    // Check next hops
    try std.testing.expectEqual(@as(u32, 200), fw.nextWithMapping(100, 400));
}

test "FloydWarshallOptimized weighted shortest path" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    // Graph with two paths to node 3:
    // 0 --5--> 1 --3--> 3  (total: 8)
    // 0 --2--> 2 --2--> 3  (total: 4) <- shorter
    fw.addEdge(0, 1, 5);
    fw.addEdge(1, 3, 3);
    fw.addEdge(0, 2, 2);
    fw.addEdge(2, 3, 2);

    fw.generate();

    // Should find shortest path
    try std.testing.expectEqual(@as(u32, 4), fw.value(0, 3));
    try std.testing.expectEqual(@as(u32, 2), fw.getNext(0, 3)); // Goes through node 2
}

test "FloydWarshallOptimized path reconstruction" {
    const allocator = std.testing.allocator;

    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(4);
    try fw.clean();

    try fw.addEdgeWithMapping(10, 20, 1);
    try fw.addEdgeWithMapping(20, 30, 1);
    try fw.addEdgeWithMapping(30, 40, 1);

    fw.generate();

    var path = std.ArrayListUnmanaged(u32){};
    defer path.deinit(allocator);

    try fw.setPathWithMappingUnmanaged(allocator, &path, 10, 40);

    try std.testing.expectEqual(@as(usize, 4), path.items.len);
    try std.testing.expectEqual(@as(u32, 10), path.items[0]);
    try std.testing.expectEqual(@as(u32, 20), path.items[1]);
    try std.testing.expectEqual(@as(u32, 30), path.items[2]);
    try std.testing.expectEqual(@as(u32, 40), path.items[3]);
}
