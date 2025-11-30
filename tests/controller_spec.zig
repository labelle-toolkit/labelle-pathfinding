const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");
const zig_utils = @import("zig_utils");

const expect = zspec.expect;
const Position = zig_utils.Vector2;

pub const MovementNodeControllerSpec = struct {
    const MockQuadTree = struct {
        items: []const pathfinding.EntityPosition,

        pub fn queryOnBuffer(
            self: *MockQuadTree,
            rect: pathfinding.Rectangle,
            buffer: *std.array_list.Managed(pathfinding.EntityPosition),
        ) !void {
            _ = rect;
            for (self.items) |item| {
                try buffer.append(item);
            }
        }
    };

    const Controller = pathfinding.MovementNodeController(MockQuadTree);

    pub const @"finding closest node" = struct {
        test "returns the closest node to position" {
            const items = [_]pathfinding.EntityPosition{
                .{ .entity = 1, .x = 10, .y = 10 },
                .{ .entity = 2, .x = 100, .y = 100 },
                .{ .entity = 3, .x = 5, .y = 5 },
            };

            var mock = MockQuadTree{ .items = &items };
            const pos = Position{ .x = 0, .y = 0 };

            const result = try Controller.getClosestMovementNode(
                &mock,
                pos,
                std.testing.allocator,
            );

            try expect.equal(result.entity, 3);
        }

        test "handles single node" {
            const items = [_]pathfinding.EntityPosition{
                .{ .entity = 42, .x = 50, .y = 50 },
            };

            var mock = MockQuadTree{ .items = &items };
            const pos = Position{ .x = 0, .y = 0 };

            const result = try Controller.getClosestMovementNode(
                &mock,
                pos,
                std.testing.allocator,
            );

            try expect.equal(result.entity, 42);
        }
    };

    pub const @"error handling" = struct {
        test "returns error when quad tree is empty" {
            var mock = MockQuadTree{ .items = &.{} };
            const pos = Position{ .x = 0, .y = 0 };

            const result = Controller.getClosestMovementNode(
                &mock,
                pos,
                std.testing.allocator,
            );

            try std.testing.expectError(error.EmptyQuadTree, result);
        }
    };

    pub const @"with buffer" = struct {
        test "uses provided buffer for query results" {
            const items = [_]pathfinding.EntityPosition{
                .{ .entity = 1, .x = 10, .y = 10 },
                .{ .entity = 2, .x = 5, .y = 5 },
            };

            var mock = MockQuadTree{ .items = &items };
            var buffer = std.array_list.Managed(pathfinding.EntityPosition).init(std.testing.allocator);
            defer buffer.deinit();

            const pos = Position{ .x = 0, .y = 0 };

            const result = try Controller.getClosestMovementNodeWithBuffer(
                &mock,
                pos,
                &buffer,
            );

            try expect.equal(result.entity, 2);
            try expect.equal(buffer.items.len, 2);
        }
    };
};
