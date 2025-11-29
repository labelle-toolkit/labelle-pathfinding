//! Pathfinding Components
//!
//! ECS components for node-based pathfinding systems.
//! These components can be used with any ECS library.

const std = @import("std");

/// A node in a movement graph with directional links to neighbors.
/// Supports 4-directional movement (left, right, up, down).
pub const MovementNode = struct {
    left_entt: ?u32 = null,
    right_entt: ?u32 = null,
    up_entt: ?u32 = null,
    down_entt: ?u32 = null,
};

/// Tracks the closest movement node to an entity.
/// Updated by spatial queries (quad tree, grid, etc.)
pub const ClosestMovementNode = struct {
    node_entt: u32 = 0,
    distance: f32 = 0,
};

/// Component for entities moving towards a target.
pub const MovingTowards = struct {
    target_x: f32 = 0,
    target_y: f32 = 0,
    closest_node_entt: u32 = 0,
    speed: f32 = 10,
};

/// A computed path through movement nodes.
/// Manages its own memory for the path array.
pub const WithPath = struct {
    allocator: std.mem.Allocator,
    path: std.ArrayListUnmanaged(u32) = .empty,

    pub fn init(allocator: std.mem.Allocator) WithPath {
        return .{ .allocator = allocator, .path = .empty };
    }

    pub fn deinit(self: *WithPath) void {
        self.path.deinit(self.allocator);
    }

    pub fn append(self: *WithPath, node: u32) !void {
        try self.path.append(self.allocator, node);
    }

    pub fn clear(self: *WithPath) void {
        self.path.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const WithPath) bool {
        return self.path.items.len == 0;
    }

    pub fn popFront(self: *WithPath) ?u32 {
        if (self.path.items.len == 0) return null;
        return self.path.orderedRemove(0);
    }

    pub fn peekFront(self: *const WithPath) ?u32 {
        if (self.path.items.len == 0) return null;
        return self.path.items[0];
    }
};

test "WithPath basic operations" {
    var path = WithPath.init(std.testing.allocator);
    defer path.deinit();

    try std.testing.expect(path.isEmpty());

    try path.append(1);
    try path.append(2);
    try path.append(3);

    try std.testing.expect(!path.isEmpty());
    try std.testing.expectEqual(@as(?u32, 1), path.peekFront());

    try std.testing.expectEqual(@as(?u32, 1), path.popFront());
    try std.testing.expectEqual(@as(?u32, 2), path.popFront());
    try std.testing.expectEqual(@as(?u32, 3), path.popFront());
    try std.testing.expectEqual(@as(?u32, null), path.popFront());

    try std.testing.expect(path.isEmpty());
}

test "MovementNode default values" {
    const node = MovementNode{};
    try std.testing.expectEqual(@as(?u32, null), node.left_entt);
    try std.testing.expectEqual(@as(?u32, null), node.right_entt);
    try std.testing.expectEqual(@as(?u32, null), node.up_entt);
    try std.testing.expectEqual(@as(?u32, null), node.down_entt);
}
