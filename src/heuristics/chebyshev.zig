//! Chebyshev Distance Heuristic
//!
//! Calculates the chessboard/king's move distance - the maximum of absolute
//! differences in x and y coordinates. A king in chess can reach any square
//! in this many moves.
//!
//! ## Properties
//! - **Admissible**: For 8-directional movement with uniform cost
//! - **Best for**: Games where diagonal movement costs the same as cardinal
//!
//! ## Formula
//! `max(|x2-x1|, |y2-y1|)`

const zig_utils = @import("zig_utils");

pub const Position = zig_utils.Vector2;

/// Calculate Chebyshev (chessboard) distance between two positions.
pub fn calculate(a: Position, b: Position) f32 {
    return @max(@abs(b.x - a.x), @abs(b.y - a.y));
}
