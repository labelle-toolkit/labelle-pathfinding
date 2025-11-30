//! Movement Node Controller
//!
//! Finds the closest movement node to a given position using spatial queries.
//! This is a generic implementation that works with any quad tree or spatial
//! index that provides the required interface.

const std = @import("std");
const zig_utils = @import("zig_utils");

/// Re-export Position (Vector2) from zig-utils for convenience
pub const Position = zig_utils.Vector2;

pub const MovementNodeControllerError = error{EmptyQuadTree};

/// Position with entity reference for spatial queries
pub const EntityPosition = struct {
    entity: u32,
    x: f32,
    y: f32,
};

/// Rectangle for spatial queries
pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// Calculate distance between two positions
pub fn distance(a: Position, b: Position) f32 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return @sqrt(dx * dx + dy * dy);
}

/// Calculate squared distance between two positions (faster, no sqrt)
pub fn distanceSqr(a: Position, b: Position) f32 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return dx * dx + dy * dy;
}

/// Interface that quad trees must implement for spatial queries
pub fn QuadTreeInterface(comptime Self: type) type {
    return struct {
        pub fn queryOnBuffer(self: *Self, rect: Rectangle, buffer: *std.array_list.Managed(EntityPosition)) !void {
            _ = self;
            _ = rect;
            _ = buffer;
        }
    };
}

/// Controller for finding closest movement nodes using spatial queries.
/// Generic over the quad tree implementation.
pub fn MovementNodeController(comptime QuadTree: type) type {
    return struct {
        const Self = @This();

        /// Find the closest movement node to a position, using a provided buffer
        pub fn getClosestMovementNodeWithBuffer(
            quad_tree: *QuadTree,
            pos: Position,
            buffer: *std.array_list.Managed(EntityPosition),
        ) !EntityPosition {
            try quad_tree.queryOnBuffer(
                .{ .x = pos.x - 40, .y = pos.y - 10, .width = 80, .height = 100 },
                buffer,
            );
            if (buffer.items.len == 0) {
                return error.EmptyQuadTree;
            }

            var current_distance: f32 = std.math.inf(f32);
            var closest_node: EntityPosition = buffer.items[0];

            for (buffer.items) |entity_position| {
                const entity_pos = Position{ .x = entity_position.x, .y = entity_position.y };
                const new_distance = distance(pos, entity_pos);
                if (new_distance < current_distance) {
                    closest_node = entity_position;
                    current_distance = new_distance;
                }
            }

            return closest_node;
        }

        const EntityPositionList = std.array_list.Managed(EntityPosition);

        /// Find the closest movement node to a position, allocating a temporary buffer
        pub fn getClosestMovementNode(
            quad_tree: *QuadTree,
            pos: Position,
            allocator: std.mem.Allocator,
        ) !EntityPosition {
            var buffer = EntityPositionList.init(allocator);
            defer buffer.deinit();

            return getClosestMovementNodeWithBuffer(quad_tree, pos, &buffer);
        }
    };
}
