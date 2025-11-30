//! Euclidean Distance Heuristic
//!
//! Calculates the straight-line (as-the-crow-flies) distance between two points.
//! This is the default heuristic for A* when movement is not restricted to a grid.
//!
//! ## Properties
//! - **Admissible**: Always (straight-line is the shortest possible distance)
//! - **Best for**: Any-angle movement, open spaces, flying units
//!
//! ## Formula
//! `sqrt((x2-x1)^2 + (y2-y1)^2)`

const std = @import("std");
const zig_utils = @import("zig_utils");

pub const Position = zig_utils.Vector2;

/// Calculate Euclidean (straight-line) distance between two positions.
pub fn calculate(a: Position, b: Position) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return @sqrt(dx * dx + dy * dy);
}

/// Calculate squared Euclidean distance (faster, avoids sqrt).
/// Useful for comparisons where actual distance value isn't needed.
pub fn calculateSquared(a: Position, b: Position) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return dx * dx + dy * dy;
}
