//! Pathfinding Components
//!
//! ECS components for node-based pathfinding systems.
//! Designed for use with zig-ecs Registry.

const std = @import("std");
const ecs = @import("ecs");

/// Entity type from zig-ecs
pub const Entity = ecs.Entity;

/// A node in a movement graph with directional links to neighbors.
/// Supports 4-directional movement (left, right, up, down).
pub const MovementNode = struct {
    left_entt: ?Entity = null,
    right_entt: ?Entity = null,
    up_entt: ?Entity = null,
    down_entt: ?Entity = null,
};

/// Tracks the closest movement node to an entity.
/// Updated by spatial queries (quad tree, grid, etc.)
pub const ClosestMovementNode = struct {
    node_entt: ?Entity = null,
    distance: f32 = 0,
};

/// Component for entities moving towards a target.
pub const MovingTowards = struct {
    target_x: f32 = 0,
    target_y: f32 = 0,
    closest_node_entt: ?Entity = null,
    speed: f32 = 10,
};

/// A computed path through movement nodes.
/// Manages its own memory for the path array.
pub const WithPath = struct {
    allocator: std.mem.Allocator,
    path: std.ArrayListUnmanaged(Entity) = .empty,

    pub fn init(allocator: std.mem.Allocator) WithPath {
        return .{ .allocator = allocator, .path = .empty };
    }

    pub fn deinit(self: *WithPath) void {
        self.path.deinit(self.allocator);
    }

    pub fn append(self: *WithPath, node: Entity) !void {
        try self.path.append(self.allocator, node);
    }

    pub fn clear(self: *WithPath) void {
        self.path.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const WithPath) bool {
        return self.path.items.len == 0;
    }

    pub fn popFront(self: *WithPath) ?Entity {
        if (self.path.items.len == 0) return null;
        return self.path.orderedRemove(0);
    }

    pub fn peekFront(self: *const WithPath) ?Entity {
        if (self.path.items.len == 0) return null;
        return self.path.items[0];
    }
};
