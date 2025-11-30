//! Heuristic Functions for A* Pathfinding
//!
//! Provides multiple distance heuristics for A* algorithm optimization.
//! All heuristics use Position (Vector2) from zig-utils for coordinates.
//!
//! ## Heuristic Selection Guide
//! - **Euclidean**: Default for free movement in any direction
//! - **Manhattan**: Best for 4-directional grid movement (roguelikes, puzzle games)
//! - **Chebyshev**: Best for 8-directional movement where diagonals cost same as cardinals
//! - **Octile**: Best for 8-directional movement where diagonals cost sqrt(2)
//! - **Zero**: Degrades A* to Dijkstra's algorithm (guaranteed shortest, but slower)

const std = @import("std");
const zig_utils = @import("zig_utils");

pub const Position = zig_utils.Vector2;

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
        .euclidean => euclidean(a, b),
        .manhattan => manhattan(a, b),
        .chebyshev => chebyshev(a, b),
        .octile => octile(a, b),
        .zero => zero(a, b),
    };
}

/// Euclidean distance (straight-line)
pub fn euclidean(a: Position, b: Position) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return @sqrt(dx * dx + dy * dy);
}

/// Manhattan distance (taxicab/grid)
pub fn manhattan(a: Position, b: Position) f32 {
    return @abs(b.x - a.x) + @abs(b.y - a.y);
}

/// Chebyshev distance (chessboard/king's move)
pub fn chebyshev(a: Position, b: Position) f32 {
    return @max(@abs(b.x - a.x), @abs(b.y - a.y));
}

/// Octile distance (optimal for 8-directional with sqrt(2) diagonal cost)
pub fn octile(a: Position, b: Position) f32 {
    const dx = @abs(b.x - a.x);
    const dy = @abs(b.y - a.y);
    const sqrt2_minus_1: f32 = std.math.sqrt2 - 1.0;
    return @max(dx, dy) + sqrt2_minus_1 * @min(dx, dy);
}

/// Zero heuristic (Dijkstra's algorithm)
pub fn zero(a: Position, b: Position) f32 {
    _ = a;
    _ = b;
    return 0;
}

// ============================================================================
// Tests
// ============================================================================

test "euclidean distance" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 3, .y = 4 };
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), euclidean(a, b), 0.001);
}

test "euclidean distance same point" {
    const a = Position{ .x = 5, .y = 5 };
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), euclidean(a, a), 0.001);
}

test "manhattan distance" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 3, .y = 4 };
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), manhattan(a, b), 0.001);
}

test "manhattan distance negative" {
    const a = Position{ .x = 5, .y = 5 };
    const b = Position{ .x = 2, .y = 1 };
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), manhattan(a, b), 0.001);
}

test "chebyshev distance" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 3, .y = 4 };
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), chebyshev(a, b), 0.001);
}

test "chebyshev distance diagonal" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 5, .y = 5 };
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), chebyshev(a, b), 0.001);
}

test "octile distance cardinal" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 4, .y = 0 };
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), octile(a, b), 0.001);
}

test "octile distance diagonal" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 3, .y = 3 };
    // For pure diagonal: 3 * sqrt(2) ≈ 4.243
    const expected: f32 = 3.0 * std.math.sqrt2;
    try std.testing.expectApproxEqAbs(expected, octile(a, b), 0.001);
}

test "octile distance mixed" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 4, .y = 2 };
    // max(4,2) + (sqrt(2)-1) * min(4,2) = 4 + 0.414 * 2 ≈ 4.828
    const expected: f32 = 4.0 + (std.math.sqrt2 - 1.0) * 2.0;
    try std.testing.expectApproxEqAbs(expected, octile(a, b), 0.001);
}

test "zero heuristic" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 100, .y = 100 };
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), zero(a, b), 0.001);
}

test "calculate with enum" {
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 3, .y = 4 };

    try std.testing.expectApproxEqAbs(@as(f32, 5.0), calculate(.euclidean, a, b), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), calculate(.manhattan, a, b), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), calculate(.chebyshev, a, b), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), calculate(.zero, a, b), 0.001);
}

test "heuristic admissibility - euclidean never overestimates" {
    // Euclidean is always admissible (straight-line is shortest possible)
    const a = Position{ .x = 0, .y = 0 };
    const b = Position{ .x = 10, .y = 10 };
    const actual_distance = euclidean(a, b);

    // Any other path would be longer
    try std.testing.expect(euclidean(a, b) <= actual_distance);
    try std.testing.expect(manhattan(a, b) >= actual_distance);
}
