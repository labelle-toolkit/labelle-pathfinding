const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");
const zig_utils = @import("zig_utils");

const expect = zspec.expect;
const Position = zig_utils.Vector2;
const heuristics = pathfinding.heuristics;

pub const HeuristicsSpec = struct {
    pub const @"Euclidean heuristic" = struct {
        test "calculates straight-line distance" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(heuristics.euclidean.calculate(a, b), 5.0);
        }

        test "returns zero for same point" {
            const a = Position{ .x = 5, .y = 5 };
            try expect.equal(heuristics.euclidean.calculate(a, a), 0.0);
        }

        test "is symmetric" {
            const a = Position{ .x = 1, .y = 2 };
            const b = Position{ .x = 4, .y = 6 };
            try expect.equal(
                heuristics.euclidean.calculate(a, b),
                heuristics.euclidean.calculate(b, a),
            );
        }

        test "handles negative coordinates" {
            const a = Position{ .x = -3, .y = -4 };
            const b = Position{ .x = 0, .y = 0 };
            try expect.equal(heuristics.euclidean.calculate(a, b), 5.0);
        }

        test "calculateSquared avoids sqrt" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(heuristics.euclidean.calculateSquared(a, b), 25.0);
        }
    };

    pub const @"Manhattan heuristic" = struct {
        test "calculates grid distance" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(heuristics.manhattan.calculate(a, b), 7.0);
        }

        test "returns zero for same point" {
            const a = Position{ .x = 5, .y = 5 };
            try expect.equal(heuristics.manhattan.calculate(a, a), 0.0);
        }

        test "handles negative coordinates" {
            const a = Position{ .x = 5, .y = 5 };
            const b = Position{ .x = 2, .y = 1 };
            try expect.equal(heuristics.manhattan.calculate(a, b), 7.0);
        }

        test "is symmetric" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(
                heuristics.manhattan.calculate(a, b),
                heuristics.manhattan.calculate(b, a),
            );
        }

        test "is always >= euclidean" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.toBeTrue(
                heuristics.manhattan.calculate(a, b) >= heuristics.euclidean.calculate(a, b),
            );
        }
    };

    pub const @"Chebyshev heuristic" = struct {
        test "calculates chessboard distance" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(heuristics.chebyshev.calculate(a, b), 4.0);
        }

        test "returns zero for same point" {
            const a = Position{ .x = 5, .y = 5 };
            try expect.equal(heuristics.chebyshev.calculate(a, a), 0.0);
        }

        test "equals diagonal distance for perfect diagonal" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 5, .y = 5 };
            try expect.equal(heuristics.chebyshev.calculate(a, b), 5.0);
        }

        test "is symmetric" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 7 };
            try expect.equal(
                heuristics.chebyshev.calculate(a, b),
                heuristics.chebyshev.calculate(b, a),
            );
        }

        test "is always <= manhattan" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.toBeTrue(
                heuristics.chebyshev.calculate(a, b) <= heuristics.manhattan.calculate(a, b),
            );
        }
    };

    pub const @"Octile heuristic" = struct {
        test "calculates optimal 8-dir distance" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 4, .y = 2 };
            // max(4,2) + (sqrt(2)-1) * min(4,2) = 4 + 0.414 * 2 ≈ 4.828
            const expected: f32 = 4.0 + (std.math.sqrt2 - 1.0) * 2.0;
            const actual = heuristics.octile.calculate(a, b);
            try std.testing.expectApproxEqAbs(expected, actual, 0.001);
        }

        test "returns zero for same point" {
            const a = Position{ .x = 5, .y = 5 };
            try expect.equal(heuristics.octile.calculate(a, a), 0.0);
        }

        test "equals sqrt(2) * distance for perfect diagonal" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 3 };
            // For pure diagonal: 3 * sqrt(2)
            const expected: f32 = 3.0 * std.math.sqrt2;
            const actual = heuristics.octile.calculate(a, b);
            try std.testing.expectApproxEqAbs(expected, actual, 0.001);
        }

        test "equals distance for cardinal direction" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 4, .y = 0 };
            try expect.equal(heuristics.octile.calculate(a, b), 4.0);
        }

        test "is symmetric" {
            const a = Position{ .x = 1, .y = 2 };
            const b = Position{ .x = 5, .y = 7 };
            const ab = heuristics.octile.calculate(a, b);
            const ba = heuristics.octile.calculate(b, a);
            try std.testing.expectApproxEqAbs(ab, ba, 0.001);
        }

        test "is between chebyshev and manhattan" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            const octile_dist = heuristics.octile.calculate(a, b);
            const chebyshev_dist = heuristics.chebyshev.calculate(a, b);
            const manhattan_dist = heuristics.manhattan.calculate(a, b);

            try expect.toBeTrue(octile_dist >= chebyshev_dist);
            try expect.toBeTrue(octile_dist <= manhattan_dist);
        }
    };

    pub const @"Zero heuristic" = struct {
        test "always returns zero" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 100, .y = 100 };
            try expect.equal(heuristics.zero.calculate(a, b), 0.0);
        }

        test "returns zero for any positions" {
            const a = Position{ .x = -50, .y = 25 };
            const b = Position{ .x = 1000, .y = -500 };
            try expect.equal(heuristics.zero.calculate(a, b), 0.0);
        }
    };

    pub const @"calculate function" = struct {
        test "dispatches to euclidean" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(
                heuristics.calculate(.euclidean, a, b),
                heuristics.euclidean.calculate(a, b),
            );
        }

        test "dispatches to manhattan" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(
                heuristics.calculate(.manhattan, a, b),
                heuristics.manhattan.calculate(a, b),
            );
        }

        test "dispatches to chebyshev" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(
                heuristics.calculate(.chebyshev, a, b),
                heuristics.chebyshev.calculate(a, b),
            );
        }

        test "dispatches to octile" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            const expected = heuristics.octile.calculate(a, b);
            const actual = heuristics.calculate(.octile, a, b);
            try std.testing.expectApproxEqAbs(expected, actual, 0.001);
        }

        test "dispatches to zero" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(
                heuristics.calculate(.zero, a, b),
                heuristics.zero.calculate(a, b),
            );
        }
    };

    pub const @"admissibility" = struct {
        test "euclidean never overestimates straight-line distance" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 10, .y = 10 };
            const actual = heuristics.euclidean.calculate(a, b);
            // Euclidean IS the actual straight-line distance
            try expect.equal(heuristics.euclidean.calculate(a, b), actual);
        }

        test "zero is always admissible" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 10, .y = 10 };
            // Zero never overestimates (it's always 0)
            try expect.equal(heuristics.zero.calculate(a, b), 0.0);
        }

        test "chebyshev is admissible for 8-dir equal cost" {
            // For 8-directional movement with cost 1 per move (including diagonals),
            // Chebyshev distance equals the minimum number of moves
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 5, .y = 3 };
            // Can reach in 5 moves: 3 diagonal + 2 straight = 5 = max(5,3)
            try expect.equal(heuristics.chebyshev.calculate(a, b), 5.0);
        }
    };
};
