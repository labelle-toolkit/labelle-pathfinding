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

pub const Position = zig_utils.Vector2;

// Individual heuristic modules
pub const euclidean = @import("heuristics/euclidean.zig");
pub const manhattan = @import("heuristics/manhattan.zig");
pub const chebyshev = @import("heuristics/chebyshev.zig");
pub const octile = @import("heuristics/octile.zig");
pub const zero = @import("heuristics/zero.zig");

/// Built-in heuristic types for A* pathfinding
pub const Heuristic = enum {
    /// Straight-line distance: sqrt((x2-x1)^2 + (y2-y1)^2)
    /// Best for: Any-angle movement, open spaces
    /// Admissible: Always
    euclidean,

    /// Grid distance: |x2-x1| + |y2-y1|
    /// Best for: 4-directional grid movement
    /// Admissible: For 4-directional movement only
    manhattan,

    /// Chessboard distance: max(|x2-x1|, |y2-y1|)
    /// Best for: 8-directional movement with equal diagonal cost
    /// Admissible: For 8-directional with uniform cost
    chebyshev,

    /// Optimal 8-directional: max(dx,dy) + (sqrt(2)-1) * min(dx,dy)
    /// Best for: 8-directional movement where diagonal costs sqrt(2)
    /// Admissible: For 8-directional with sqrt(2) diagonal cost
    octile,

    /// No heuristic (always returns 0)
    /// Effect: Degrades A* to Dijkstra's algorithm
    /// Use when: You need guaranteed shortest path without heuristic assumptions
    zero,
};

/// Custom heuristic function type for user-defined heuristics.
/// Must return an estimated cost from position `a` to position `b`.
/// For admissibility, the estimate must never exceed the actual cost.
pub const HeuristicFn = *const fn (a: Position, b: Position) f32;

/// Calculate heuristic distance between two positions using the specified heuristic type.
pub fn calculate(heuristic: Heuristic, a: Position, b: Position) f32 {
    return switch (heuristic) {
        .euclidean => euclidean.calculate(a, b),
        .manhattan => manhattan.calculate(a, b),
        .chebyshev => chebyshev.calculate(a, b),
        .octile => octile.calculate(a, b),
        .zero => zero.calculate(a, b),
    };
}
