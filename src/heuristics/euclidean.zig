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

const zig_utils = @import("zig_utils");

pub const Position = zig_utils.Vector2;

/// Calculate Euclidean (straight-line) distance between two positions.
/// Delegates to zig-utils heuristics implementation.
pub const calculate = zig_utils.heuristics.euclidean;

/// Calculate squared Euclidean distance (faster, avoids sqrt).
/// Useful for comparisons where actual distance value isn't needed.
pub const calculateSquared = zig_utils.heuristics.euclideanSquared;
