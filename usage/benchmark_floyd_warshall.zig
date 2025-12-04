//! Floyd-Warshall Benchmark
//!
//! Compares performance of legacy vs optimized Floyd-Warshall implementations.
//! Run with: zig build run-benchmark
//!
//! Results will vary based on:
//! - CPU architecture (SIMD support)
//! - Number of cores (parallel implementation)
//! - Graph size and density
//! - Cache sizes

const std = @import("std");
const pathfinding = @import("pathfinding");

const FloydWarshall = pathfinding.FloydWarshall;
const FloydWarshallSimd = pathfinding.FloydWarshallSimd;
const FloydWarshallFast = pathfinding.FloydWarshallFast;

const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== Floyd-Warshall Benchmark ===\n\n", .{});
    print("Comparing implementations:\n", .{});
    print("  - Legacy: ArrayList-based (original)\n", .{});
    print("  - SIMD: Flat memory + SIMD vectorization\n", .{});
    print("  - Parallel: SIMD + multi-threading\n\n", .{});

    // Test different graph sizes
    const sizes = [_]u32{ 32, 64, 128, 256 };

    for (sizes) |size| {
        print("Graph size: {} nodes ({}x{} = {} edges max)\n", .{
            size,
            size,
            size,
            @as(u64, size) * @as(u64, size),
        });
        print("--------------------------------------------------\n", .{});

        // Benchmark legacy implementation
        const legacy_time = try benchmarkLegacy(allocator, size);
        print("  Legacy:   {d:>8.2} ms\n", .{legacy_time});

        // Benchmark SIMD implementation
        const simd_time = try benchmarkSimd(allocator, size);
        print("  SIMD:     {d:>8.2} ms", .{simd_time});
        if (legacy_time > 0) {
            const speedup = legacy_time / simd_time;
            print(" ({d:.1}x speedup)", .{speedup});
        }
        print("\n", .{});

        // Benchmark parallel implementation (only for larger sizes)
        if (size >= 64) {
            const parallel_time = try benchmarkParallel(allocator, size);
            print("  Parallel: {d:>8.2} ms", .{parallel_time});
            if (legacy_time > 0) {
                const speedup = legacy_time / parallel_time;
                print(" ({d:.1}x speedup)", .{speedup});
            }
            print("\n", .{});
        }

        print("\n", .{});
    }

    print("Note: Smaller times are better. Speedup is relative to legacy.\n", .{});
    print("Parallel benefits are most visible with larger graphs (256+ nodes).\n\n", .{});
}

fn benchmarkLegacy(allocator: std.mem.Allocator, size: u32) !f64 {
    var fw = FloydWarshall.init(allocator);
    defer fw.deinit();

    fw.resize(size);
    try fw.clean();

    // Create a dense graph (grid-like connections)
    createDenseGraph(&fw, size);

    // Measure generation time
    var timer = try std.time.Timer.start();

    fw.generate();

    const elapsed = timer.read();
    return @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
}

fn benchmarkSimd(allocator: std.mem.Allocator, size: u32) !f64 {
    var fw = FloydWarshallSimd.init(allocator);
    defer fw.deinit();

    fw.resize(size);
    try fw.clean();

    // Create a dense graph (grid-like connections)
    createDenseGraphOptimized(&fw, size);

    // Measure generation time
    var timer = try std.time.Timer.start();

    fw.generate();

    const elapsed = timer.read();
    return @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
}

fn benchmarkParallel(allocator: std.mem.Allocator, size: u32) !f64 {
    var fw = FloydWarshallFast.init(allocator);
    defer fw.deinit();

    fw.resize(size);
    try fw.clean();

    // Create a dense graph (grid-like connections)
    createDenseGraphOptimized(&fw, size);

    // Measure generation time
    var timer = try std.time.Timer.start();

    fw.generate();

    const elapsed = timer.read();
    return @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_ms;
}

fn createDenseGraph(fw: *FloydWarshall, size: u32) void {
    // Create grid-like connections
    // Each node connects to neighbors within distance 2
    var i: u32 = 0;
    while (i < size) : (i += 1) {
        var j: u32 = 0;
        while (j < size) : (j += 1) {
            if (i != j) {
                const diff = if (i > j) i - j else j - i;
                if (diff <= 2) {
                    fw.addEdge(i, j, diff);
                }
            }
        }
    }
}

fn createDenseGraphOptimized(fw: anytype, size: u32) void {
    // Create grid-like connections
    // Each node connects to neighbors within distance 2
    var i: u32 = 0;
    while (i < size) : (i += 1) {
        var j: u32 = 0;
        while (j < size) : (j += 1) {
            if (i != j) {
                const diff = if (i > j) i - j else j - i;
                if (diff <= 2) {
                    fw.addEdge(i, j, diff);
                }
            }
        }
    }
}
