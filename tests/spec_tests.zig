const zspec = @import("zspec");

// Import all spec modules
pub const floyd_warshall_spec = @import("floyd_warshall_spec.zig");
pub const floyd_warshall_optimized_spec = @import("floyd_warshall_optimized_spec.zig");
pub const a_star_spec = @import("a_star_spec.zig");
pub const heuristics_spec = @import("heuristics_spec.zig");
pub const engine_spec = @import("engine_spec.zig");
pub const stair_mode_spec = @import("stair_mode_spec.zig");

// Re-export specs for zspec to discover
pub const FloydWarshallSpec = floyd_warshall_spec.FloydWarshallSpec;
pub const FloydWarshallOptimizedSpec = floyd_warshall_optimized_spec.FloydWarshallOptimizedSpec;
pub const EngineOptimizedSpec = floyd_warshall_optimized_spec.EngineOptimizedSpec;
pub const AStarSpec = a_star_spec.AStarSpec;
pub const HeuristicsSpec = heuristics_spec.HeuristicsSpec;

test {
    zspec.runAll(@This());
}
