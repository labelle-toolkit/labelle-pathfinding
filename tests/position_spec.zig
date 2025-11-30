const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");
const zig_utils = @import("zig_utils");

const expect = zspec.expect;
const Position = zig_utils.Vector2;

pub const PositionSpec = struct {
    pub const @"distance calculation" = struct {
        test "calculates euclidean distance" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(pathfinding.distance(a, b), 5.0);
        }

        test "calculates squared distance" {
            const a = Position{ .x = 0, .y = 0 };
            const b = Position{ .x = 3, .y = 4 };
            try expect.equal(pathfinding.distanceSqr(a, b), 25.0);
        }

        test "distance to self is zero" {
            const a = Position{ .x = 10, .y = 20 };
            try expect.equal(pathfinding.distance(a, a), 0.0);
        }

        test "distance is symmetric" {
            const a = Position{ .x = 1, .y = 2 };
            const b = Position{ .x = 4, .y = 6 };
            try expect.equal(pathfinding.distance(a, b), pathfinding.distance(b, a));
        }
    };

    pub const @"default values" = struct {
        test "defaults to origin" {
            const pos = Position{};
            try expect.equal(pos.x, 0);
            try expect.equal(pos.y, 0);
        }
    };
};
