//! Octile Distance Heuristic
//!
//! Calculates the optimal distance for 8-directional movement where diagonal
//! moves cost sqrt(2) times cardinal moves. This is the most accurate heuristic
//! for realistic grid-based movement.
//!
//! ## Properties
//! - **Admissible**: For 8-directional movement with sqrt(2) diagonal cost
//! - **Best for**: Most grid-based games with diagonal movement
//!
//! ## Formula
//! `max(dx, dy) + (sqrt(2) - 1) * min(dx, dy)`
//!
//! This is equivalent to: `diagonal_moves * sqrt(2) + straight_moves * 1`

const zig_utils = @import("zig_utils");

pub const Position = zig_utils.Vector2;

/// sqrt(2) - 1, precomputed for efficiency
pub const SQRT2_MINUS_1 = zig_utils.heuristics.SQRT2_MINUS_1;

/// Calculate Octile distance between two positions.
/// Delegates to zig-utils heuristics implementation.
pub const calculate = zig_utils.heuristics.octile;
