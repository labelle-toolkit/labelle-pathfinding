//! QuadTree spatial partitioning data structure
//!
//! Provides O(log n) spatial queries for points in 2D space.
//! Used for efficient entity lookups and node neighbor finding.

const std = @import("std");

/// Simple 2D point for boundary calculations
pub const Point2D = struct {
    x: f32,
    y: f32,
};

/// A point with an associated identifier
pub fn EntityPoint(comptime T: type) type {
    return struct {
        id: T,
        x: f32,
        y: f32,
    };
}

/// Axis-aligned bounding box
pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn containsPoint(self: Rectangle, px: f32, py: f32) bool {
        return px >= self.x and px < self.x + self.width and
            py >= self.y and py < self.y + self.height;
    }

    pub fn intersects(self: Rectangle, other: Rectangle) bool {
        return !(other.x >= self.x + self.width or
            other.x + other.width <= self.x or
            other.y >= self.y + self.height or
            other.y + other.height <= self.y);
    }
};

/// QuadTree node
fn QuadTreeNode(comptime T: type) type {
    const Point = EntityPoint(T);

    return struct {
        total_elements: u32 = 0,
        points: [4]Point = undefined,
        boundary: Rectangle,
        divided: bool = false,
        nw: u32 = 0,
        ne: u32 = 0,
        sw: u32 = 0,
        se: u32 = 0,
    };
}

/// QuadTree for spatial partitioning
pub fn QuadTree(comptime T: type) type {
    const Point = EntityPoint(T);
    const Node = QuadTreeNode(T);

    return struct {
        const Self = @This();

        nodes: std.ArrayListUnmanaged(Node),
        capacity: u32 = 4,
        gutter: f32 = 120.0,

        lowest_x: f32 = 0.0,
        lowest_y: f32 = 0.0,
        highest_x: f32 = 0.0,
        highest_y: f32 = 0.0,

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, boundary: Rectangle) Self {
            var qt = Self{
                .nodes = .{},
                .allocator = allocator,
            };
            qt.nodes.append(allocator, .{ .boundary = boundary }) catch |err| {
                std.log.err("Error appending node: {}\n", .{err});
            };
            return qt;
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit(self.allocator);
        }

        /// Clear the tree and reset with new boundary computed from points
        pub fn resetWithBoundaries(self: *Self, points: []const Point2D) void {
            self.nodes.clearRetainingCapacity();
            self.lowest_x = std.math.inf(f32);
            self.lowest_y = std.math.inf(f32);
            self.highest_x = -std.math.inf(f32);
            self.highest_y = -std.math.inf(f32);

            for (points) |point| {
                if (point.x < self.lowest_x) self.lowest_x = point.x;
                if (point.y < self.lowest_y) self.lowest_y = point.y;
                if (point.x > self.highest_x) self.highest_x = point.x;
                if (point.y > self.highest_y) self.highest_y = point.y;
            }

            self.nodes.append(self.allocator, .{ .boundary = .{
                .x = self.lowest_x - self.gutter,
                .y = self.lowest_y - self.gutter,
                .width = (self.highest_x - self.lowest_x) + self.gutter * 2,
                .height = (self.highest_y - self.lowest_y) + self.gutter * 2,
            } }) catch |err| {
                std.log.err("Error appending node: {}\n", .{err});
            };
        }

        /// Clear the tree keeping current boundaries
        pub fn reset(self: *Self) void {
            self.nodes.clearRetainingCapacity();
            self.nodes.append(self.allocator, .{ .boundary = .{
                .x = self.lowest_x - self.gutter,
                .y = self.lowest_y - self.gutter,
                .width = (self.highest_x - self.lowest_x) + self.gutter * 2,
                .height = (self.highest_y - self.lowest_y) + self.gutter * 2,
            } }) catch |err| {
                std.log.err("Error appending node: {}\n", .{err});
            };
            self.lowest_x = std.math.inf(f32);
            self.lowest_y = std.math.inf(f32);
            self.highest_x = -std.math.inf(f32);
            self.highest_y = -std.math.inf(f32);
        }

        /// Insert a point into the tree
        pub fn insert(self: *Self, point: Point) bool {
            if (point.x < self.lowest_x) self.lowest_x = point.x;
            if (point.y < self.lowest_y) self.lowest_y = point.y;
            if (point.x > self.highest_x) self.highest_x = point.x;
            if (point.y > self.highest_y) self.highest_y = point.y;
            return self.insertAt(point, 0);
        }

        fn insertAt(self: *Self, point: Point, position: u32) bool {
            if (!self.nodes.items[position].boundary.containsPoint(point.x, point.y)) {
                return false;
            }

            if (self.nodes.items[position].total_elements < self.capacity and !self.nodes.items[position].divided) {
                self.nodes.items[position].points[self.nodes.items[position].total_elements] = point;
                self.nodes.items[position].total_elements += 1;
                return true;
            }

            if (!self.nodes.items[position].divided) {
                self.subdivide(position) catch |err| {
                    std.log.err("Error subdividing: {}\n", .{err});
                    return false;
                };
            }

            if (self.insertAt(point, self.nodes.items[position].nw)) return true;
            if (self.insertAt(point, self.nodes.items[position].ne)) return true;
            if (self.insertAt(point, self.nodes.items[position].sw)) return true;
            if (self.insertAt(point, self.nodes.items[position].se)) return true;

            return false;
        }

        fn subdivide(self: *Self, position: u32) !void {
            const boundary = self.nodes.items[position].boundary;
            const half_width = boundary.width / 2.0;
            const half_height = boundary.height / 2.0;
            const x = boundary.x;
            const y = boundary.y;

            self.nodes.items[position].nw = @intCast(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .boundary = .{ .x = x, .y = y, .width = half_width, .height = half_height } });

            self.nodes.items[position].ne = @intCast(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .boundary = .{ .x = x + half_width, .y = y, .width = half_width, .height = half_height } });

            self.nodes.items[position].sw = @intCast(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .boundary = .{ .x = x, .y = y + half_height, .width = half_width, .height = half_height } });

            self.nodes.items[position].se = @intCast(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .boundary = .{ .x = x + half_width, .y = y + half_height, .width = half_width, .height = half_height } });

            self.nodes.items[position].divided = true;
        }

        /// Query all points within a rectangle, storing results in buffer
        pub fn queryRect(self: *Self, range: Rectangle, buffer: *std.ArrayListUnmanaged(Point)) !void {
            try self.queryRectAt(range, buffer, 0);
        }

        fn queryRectAt(self: *Self, range: Rectangle, buffer: *std.ArrayListUnmanaged(Point), position: u32) !void {
            if (!self.nodes.items[position].boundary.intersects(range)) {
                return;
            }

            for (0..self.nodes.items[position].total_elements) |i| {
                const p = self.nodes.items[position].points[i];
                if (range.containsPoint(p.x, p.y)) {
                    try buffer.append(self.allocator, p);
                }
            }

            if (self.nodes.items[position].divided) {
                try self.queryRectAt(range, buffer, self.nodes.items[position].nw);
                try self.queryRectAt(range, buffer, self.nodes.items[position].ne);
                try self.queryRectAt(range, buffer, self.nodes.items[position].sw);
                try self.queryRectAt(range, buffer, self.nodes.items[position].se);
            }
        }

        /// Query all points within a radius of a center point
        pub fn queryRadius(self: *Self, cx: f32, cy: f32, radius: f32, buffer: *std.ArrayListUnmanaged(Point)) !void {
            // First query the bounding rectangle
            const range = Rectangle{
                .x = cx - radius,
                .y = cy - radius,
                .width = radius * 2,
                .height = radius * 2,
            };
            try self.queryRadiusAt(range, cx, cy, radius * radius, buffer, 0);
        }

        fn queryRadiusAt(self: *Self, range: Rectangle, cx: f32, cy: f32, radius_sq: f32, buffer: *std.ArrayListUnmanaged(Point), position: u32) !void {
            if (!self.nodes.items[position].boundary.intersects(range)) {
                return;
            }

            for (0..self.nodes.items[position].total_elements) |i| {
                const p = self.nodes.items[position].points[i];
                const dx = p.x - cx;
                const dy = p.y - cy;
                if (dx * dx + dy * dy <= radius_sq) {
                    try buffer.append(self.allocator, p);
                }
            }

            if (self.nodes.items[position].divided) {
                try self.queryRadiusAt(range, cx, cy, radius_sq, buffer, self.nodes.items[position].nw);
                try self.queryRadiusAt(range, cx, cy, radius_sq, buffer, self.nodes.items[position].ne);
                try self.queryRadiusAt(range, cx, cy, radius_sq, buffer, self.nodes.items[position].sw);
                try self.queryRadiusAt(range, cx, cy, radius_sq, buffer, self.nodes.items[position].se);
            }
        }

        /// Check if any point exists within a rectangle
        pub fn hasPointInRect(self: *Self, range: Rectangle) bool {
            return self.hasPointInRectAt(range, 0);
        }

        fn hasPointInRectAt(self: *Self, range: Rectangle, position: u32) bool {
            if (!self.nodes.items[position].boundary.intersects(range)) {
                return false;
            }

            for (0..self.nodes.items[position].total_elements) |i| {
                const p = self.nodes.items[position].points[i];
                if (range.containsPoint(p.x, p.y)) {
                    return true;
                }
            }

            if (self.nodes.items[position].divided) {
                if (self.hasPointInRectAt(range, self.nodes.items[position].nw)) return true;
                if (self.hasPointInRectAt(range, self.nodes.items[position].ne)) return true;
                if (self.hasPointInRectAt(range, self.nodes.items[position].sw)) return true;
                if (self.hasPointInRectAt(range, self.nodes.items[position].se)) return true;
            }

            return false;
        }

        /// Remove a point by ID (searches entire tree)
        pub fn remove(self: *Self, id: T) bool {
            return self.removeAt(id, 0);
        }

        fn removeAt(self: *Self, id: T, position: u32) bool {
            // Check points in this node
            var i: u32 = 0;
            while (i < self.nodes.items[position].total_elements) {
                if (std.meta.eql(self.nodes.items[position].points[i].id, id)) {
                    // Found it - swap with last and decrement count
                    self.nodes.items[position].total_elements -= 1;
                    if (i < self.nodes.items[position].total_elements) {
                        self.nodes.items[position].points[i] = self.nodes.items[position].points[self.nodes.items[position].total_elements];
                    }
                    return true;
                }
                i += 1;
            }

            // Check children
            if (self.nodes.items[position].divided) {
                if (self.removeAt(id, self.nodes.items[position].nw)) return true;
                if (self.removeAt(id, self.nodes.items[position].ne)) return true;
                if (self.removeAt(id, self.nodes.items[position].sw)) return true;
                if (self.removeAt(id, self.nodes.items[position].se)) return true;
            }

            return false;
        }

        /// Update position of an existing point
        pub fn update(self: *Self, id: T, new_x: f32, new_y: f32) bool {
            if (self.remove(id)) {
                return self.insert(.{ .id = id, .x = new_x, .y = new_y });
            }
            return false;
        }
    };
}

test "QuadTree basic operations" {
    const allocator = std.testing.allocator;

    var qt = QuadTree(u32).init(allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
    defer qt.deinit();

    // Insert points
    try std.testing.expect(qt.insert(.{ .id = 1, .x = 10, .y = 10 }));
    try std.testing.expect(qt.insert(.{ .id = 2, .x = 20, .y = 20 }));
    try std.testing.expect(qt.insert(.{ .id = 3, .x = 80, .y = 80 }));

    // Query rectangle
    var buffer: std.ArrayListUnmanaged(EntityPoint(u32)) = .{};
    defer buffer.deinit(allocator);

    try qt.queryRect(.{ .x = 0, .y = 0, .width = 50, .height = 50 }, &buffer);
    try std.testing.expectEqual(@as(usize, 2), buffer.items.len);

    // Query radius
    buffer.clearRetainingCapacity();
    try qt.queryRadius(10, 10, 15, &buffer);
    try std.testing.expectEqual(@as(usize, 2), buffer.items.len);

    // Remove
    try std.testing.expect(qt.remove(1));
    buffer.clearRetainingCapacity();
    try qt.queryRect(.{ .x = 0, .y = 0, .width = 50, .height = 50 }, &buffer);
    try std.testing.expectEqual(@as(usize, 1), buffer.items.len);
}

test "QuadTree subdivide" {
    const allocator = std.testing.allocator;

    var qt = QuadTree(u32).init(allocator, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
    defer qt.deinit();

    // Insert more than capacity to trigger subdivide
    for (0..10) |i| {
        _ = qt.insert(.{ .id = @intCast(i), .x = @floatFromInt(i * 10), .y = @floatFromInt(i * 10) });
    }

    var buffer: std.ArrayListUnmanaged(EntityPoint(u32)) = .{};
    defer buffer.deinit(allocator);

    try qt.queryRect(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, &buffer);
    try std.testing.expectEqual(@as(usize, 10), buffer.items.len);
}
