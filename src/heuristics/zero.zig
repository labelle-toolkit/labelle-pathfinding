//! Zero Heuristic
//!
//! Always returns zero, effectively disabling the heuristic and turning A*
//! into Dijkstra's algorithm. Use when you need guaranteed shortest paths
//! without any heuristic assumptions.
//!
//! ## Properties
//! - **Admissible**: Always (0 never overestimates)
//! - **Effect**: A* degrades to Dijkstra's algorithm
//! - **Best for**: When heuristic assumptions don't apply
//!
//! ## Trade-offs
//! - Guarantees optimal path in all cases
//! - Explores more nodes than informed heuristics
//! - Slower but more thorough

const zig_utils = @import("zig_utils");

pub const Position = zig_utils.Vector2;

/// Always returns zero (Dijkstra's algorithm behavior).
pub fn calculate(a: Position, b: Position) f32 {
    _ = a;
    _ = b;
    return 0;
}
