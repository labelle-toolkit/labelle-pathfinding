//! Heuristic Functions for Pathfinding
//!
//! Provides multiple distance heuristics for A* algorithm optimization.
//! All heuristics use Position (Vector2) for coordinates.
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

const std = @import("std");
const vector = @import("vector.zig");

pub const Position = vector.Position;

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

/// sqrt(2) - 1, precomputed for octile heuristic
pub const SQRT2_MINUS_1: f32 = std.math.sqrt2 - 1.0;

/// Calculate heuristic distance between two positions using the specified heuristic type.
pub fn calculate(heuristic: Heuristic, a: Position, b: Position) f32 {
    return switch (heuristic) {
        .euclidean => euclidean(a, b),
        .manhattan => manhattan(a, b),
        .chebyshev => chebyshev(a, b),
        .octile => octile(a, b),
        .zero => 0,
    };
}

/// Euclidean (straight-line) distance
pub fn euclidean(a: Position, b: Position) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return @sqrt(dx * dx + dy * dy);
}

/// Squared Euclidean distance (faster, avoids sqrt)
pub fn euclideanSquared(a: Position, b: Position) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return dx * dx + dy * dy;
}

/// Manhattan (taxicab) distance
pub fn manhattan(a: Position, b: Position) f32 {
    return @abs(b.x - a.x) + @abs(b.y - a.y);
}

/// Chebyshev (chessboard) distance
pub fn chebyshev(a: Position, b: Position) f32 {
    return @max(@abs(b.x - a.x), @abs(b.y - a.y));
}

/// Octile distance for 8-directional movement
pub fn octile(a: Position, b: Position) f32 {
    const dx = @abs(b.x - a.x);
    const dy = @abs(b.y - a.y);
    return @max(dx, dy) + SQRT2_MINUS_1 * @min(dx, dy);
}
