const zspec = @import("zspec");

// Import all spec modules
pub const floyd_warshall_spec = @import("floyd_warshall_spec.zig");
pub const components_spec = @import("components_spec.zig");
pub const position_spec = @import("position_spec.zig");
pub const heuristics_spec = @import("heuristics_spec.zig");
pub const controller_spec = @import("controller_spec.zig");

// Re-export specs for zspec to discover
pub const FloydWarshallSpec = floyd_warshall_spec.FloydWarshallSpec;
pub const WithPathSpec = components_spec.WithPathSpec;
pub const MovementNodeSpec = components_spec.MovementNodeSpec;
pub const ClosestMovementNodeSpec = components_spec.ClosestMovementNodeSpec;
pub const MovingTowardsSpec = components_spec.MovingTowardsSpec;
pub const PositionSpec = position_spec.PositionSpec;
pub const HeuristicsSpec = heuristics_spec.HeuristicsSpec;
pub const MovementNodeControllerSpec = controller_spec.MovementNodeControllerSpec;

test {
    zspec.runAll(@This());
}
