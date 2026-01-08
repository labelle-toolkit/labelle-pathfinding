//! Heuristic Functions for A* Pathfinding
//!
//! Provides multiple distance heuristics for A* algorithm optimization.
//! All heuristics use Position (Vector2) from zig-utils for coordinates.
//!
//! ## Available Heuristics
//! - **Euclidean**: Straight-line distance, best for any-angle movement
//! - **Manhattan**: Grid distance, best for 4-directional movement
//! - **Chebyshev**: Chessboard distance, best for 8-dir with equal diagonal cost
//! - **Octile**: Optimal 8-directional with sqrt(2) diagonal cost
//! - **Zero**: No heuristic (Dijkstra's algorithm)
//!
//! ## Heuristic Selection Guide
//! | Movement Type | Recommended Heuristic |
//! |---------------|----------------------|
//! | Free/any-angle | Euclidean |
//! | 4-directional grid | Manhattan |
//! | 8-dir, equal diagonal cost | Chebyshev |
//! | 8-dir, realistic diagonal | Octile |
//! | Unknown/mixed | Zero (safest) |

const zig_utils = @import("zig_utils");

/// Position type from zig-utils for ecosystem compatibility
pub const Position = zig_utils.Vector2;

// Individual heuristic modules (for backwards compatibility with module.calculate() API)
pub const euclidean = @import("heuristics/euclidean.zig");
pub const manhattan = @import("heuristics/manhattan.zig");
pub const chebyshev = @import("heuristics/chebyshev.zig");
pub const octile = @import("heuristics/octile.zig");
pub const zero = @import("heuristics/zero.zig");

/// Built-in heuristic types for A* pathfinding
/// Re-exported from zig-utils for consistency
pub const Heuristic = zig_utils.heuristics.Heuristic;

/// Custom heuristic function type for user-defined heuristics.
/// Must return an estimated cost from position `a` to position `b`.
/// For admissibility, the estimate must never exceed the actual cost.
pub const HeuristicFn = zig_utils.heuristics.HeuristicFn;

/// sqrt(2) - 1, precomputed for octile heuristic
pub const SQRT2_MINUS_1 = zig_utils.heuristics.SQRT2_MINUS_1;

/// Calculate heuristic distance between two positions using the specified heuristic type.
/// Delegates to zig-utils heuristics implementation.
pub const calculate = zig_utils.heuristics.calculate;
