const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("labelle_pathfinding");

const expect = zspec.expect;
const QuadTree = pathfinding.QuadTree;
const quad_tree = pathfinding.quad_tree;

pub const QuadTreeSpec = struct {
    pub const @"basic operations" = struct {
        test "insert and query points" {
            const allocator = std.testing.allocator;

            var qt = try QuadTree(u32).init(allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
            defer qt.deinit();

            // Insert points
            try expect.toBeTrue(qt.insert(.{ .id = 1, .x = 10, .y = 10 }));
            try expect.toBeTrue(qt.insert(.{ .id = 2, .x = 20, .y = 20 }));
            try expect.toBeTrue(qt.insert(.{ .id = 3, .x = 80, .y = 80 }));

            // Query rectangle
            var buffer: std.ArrayListUnmanaged(quad_tree.EntityPoint(u32)) = .{};
            defer buffer.deinit(allocator);

            try qt.queryRect(.{ .x = 0, .y = 0, .width = 50, .height = 50 }, &buffer);
            try expect.equal(buffer.items.len, 2);
        }

        test "query radius" {
            const allocator = std.testing.allocator;

            var qt = try QuadTree(u32).init(allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
            defer qt.deinit();

            _ = qt.insert(.{ .id = 1, .x = 10, .y = 10 });
            _ = qt.insert(.{ .id = 2, .x = 20, .y = 20 });
            _ = qt.insert(.{ .id = 3, .x = 80, .y = 80 });

            var buffer: std.ArrayListUnmanaged(quad_tree.EntityPoint(u32)) = .{};
            defer buffer.deinit(allocator);

            try qt.queryRadius(10, 10, 15, &buffer);
            try expect.equal(buffer.items.len, 2);
        }

        test "remove points" {
            const allocator = std.testing.allocator;

            var qt = try QuadTree(u32).init(allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
            defer qt.deinit();

            _ = qt.insert(.{ .id = 1, .x = 10, .y = 10 });
            _ = qt.insert(.{ .id = 2, .x = 20, .y = 20 });

            try expect.toBeTrue(qt.remove(1));

            var buffer: std.ArrayListUnmanaged(quad_tree.EntityPoint(u32)) = .{};
            defer buffer.deinit(allocator);

            try qt.queryRect(.{ .x = 0, .y = 0, .width = 50, .height = 50 }, &buffer);
            try expect.equal(buffer.items.len, 1);
        }
    };

    pub const @"subdivide" = struct {
        test "handles more than capacity points" {
            const allocator = std.testing.allocator;

            var qt = try QuadTree(u32).init(allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
            defer qt.deinit();

            // Insert more than capacity to trigger subdivide
            for (0..10) |i| {
                _ = qt.insert(.{ .id = @intCast(i), .x = @floatFromInt(i * 10), .y = @floatFromInt(i * 10) });
            }

            var buffer: std.ArrayListUnmanaged(quad_tree.EntityPoint(u32)) = .{};
            defer buffer.deinit(allocator);

            try qt.queryRect(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, &buffer);
            try expect.equal(buffer.items.len, 10);
        }
    };
};
