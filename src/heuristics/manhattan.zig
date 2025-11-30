//! Manhattan Distance Heuristic
//!
//! Calculates the taxicab/grid distance - the sum of absolute differences
//! in x and y coordinates. Named after the grid-like street layout of Manhattan.
//!
//! ## Properties
//! - **Admissible**: For 4-directional movement only
//! - **Best for**: Roguelikes, puzzle games, strict grid movement
//!
//! ## Formula
//! `|x2-x1| + |y2-y1|`

const zig_utils = @import("zig_utils");

pub const Position = zig_utils.Vector2;

/// Calculate Manhattan (taxicab) distance between two positions.
pub fn calculate(a: Position, b: Position) f32 {
    return @abs(b.x - a.x) + @abs(b.y - a.y);
}
