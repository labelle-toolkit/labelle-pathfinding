const zspec = @import("zspec");

// Import all spec modules
pub const floyd_warshall_spec = @import("floyd_warshall_spec.zig");
pub const floyd_warshall_optimized_spec = @import("floyd_warshall_optimized_spec.zig");
pub const a_star_spec = @import("a_star_spec.zig");
pub const heuristics_spec = @import("heuristics_spec.zig");
pub const engine_spec = @import("engine_spec.zig");
pub const stair_mode_spec = @import("stair_mode_spec.zig");
pub const hooks_spec = @import("hooks_spec.zig");
pub const quad_tree_spec = @import("quad_tree_spec.zig");

// Re-export specs for zspec to discover
pub const FloydWarshallSpec = floyd_warshall_spec.FloydWarshallSpec;
pub const FloydWarshallWithHooksSpec = floyd_warshall_spec.FloydWarshallWithHooksSpec;
pub const FloydWarshallOptimizedSpec = floyd_warshall_optimized_spec.FloydWarshallOptimizedSpec;
pub const EngineOptimizedSpec = floyd_warshall_optimized_spec.EngineOptimizedSpec;
pub const AStarSpec = a_star_spec.AStarSpec;
pub const AStarWithHooksSpec = a_star_spec.AStarWithHooksSpec;
pub const HeuristicsSpec = heuristics_spec.HeuristicsSpec;
pub const HooksSpec = hooks_spec.HooksSpec;
pub const QuadTreeSpec = quad_tree_spec.QuadTreeSpec;

test {
    zspec.runAll(@This());
}
