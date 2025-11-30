//! Movement Node Controller
//!
//! Finds the closest movement node to a given position using ECS registry queries.
//! Integrates directly with zig-ecs Registry for efficient component-based queries.

const std = @import("std");
const zig_utils = @import("zig_utils");
const ecs = @import("ecs");

const components = @import("components.zig");

/// Re-export Position (Vector2) from zig-utils for convenience
pub const Position = zig_utils.Vector2;

/// Re-export Entity type from zig-ecs
pub const Entity = ecs.Entity;

/// Re-export Registry type from zig-ecs
pub const Registry = ecs.Registry;

pub const MovementNodeControllerError = error{NoMovementNodes};

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

/// Controller for finding closest movement nodes using ECS registry queries.
pub const MovementNodeController = struct {
    /// Find the closest movement node entity to a given position.
    /// Queries all entities with MovementNode and Position components.
    ///
    /// Returns the entity ID of the closest movement node, or error if none exist.
    pub fn getClosestMovementNode(
        registry: *Registry,
        pos: Position,
    ) MovementNodeControllerError!Entity {
        var view = registry.view(.{ components.MovementNode, Position }, .{});

        var current_distance: f32 = std.math.inf(f32);
        var closest_entity: ?Entity = null;

        var iter = view.entityIterator();
        while (iter.next()) |entity| {
            const node_pos = registry.get(Position, entity);
            const new_distance = distance(pos, node_pos.*);
            if (new_distance < current_distance) {
                closest_entity = entity;
                current_distance = new_distance;
            }
        }

        return closest_entity orelse error.NoMovementNodes;
    }

    /// Find the closest movement node and return both entity and distance.
    /// Useful when you need to store the distance (e.g., in ClosestMovementNode component).
    pub fn getClosestMovementNodeWithDistance(
        registry: *Registry,
        pos: Position,
    ) MovementNodeControllerError!components.ClosestMovementNode {
        var view = registry.view(.{ components.MovementNode, Position }, .{});

        var current_distance: f32 = std.math.inf(f32);
        var closest_entity: ?Entity = null;

        var iter = view.entityIterator();
        while (iter.next()) |entity| {
            const node_pos = registry.get(Position, entity);
            const new_distance = distance(pos, node_pos.*);
            if (new_distance < current_distance) {
                closest_entity = entity;
                current_distance = new_distance;
            }
        }

        if (closest_entity) |entity| {
            return components.ClosestMovementNode{
                .node_entt = entity,
                .distance = current_distance,
            };
        }

        return error.NoMovementNodes;
    }

    /// Update the ClosestMovementNode component for all entities that have
    /// both Position and ClosestMovementNode components.
    /// This is useful for batch-updating all entities' nearest node references.
    pub fn updateAllClosestNodes(registry: *Registry) void {
        // First, ensure there are movement nodes to query against
        var node_view = registry.view(.{ components.MovementNode, Position }, .{});
        var node_iter = node_view.entityIterator();
        if (node_iter.next() == null) {
            return; // No movement nodes exist
        }

        // Update all entities that track their closest node
        var entity_view = registry.view(.{ Position, components.ClosestMovementNode }, .{});
        var entity_iter = entity_view.entityIterator();

        while (entity_iter.next()) |entity| {
            const entity_pos = registry.get(Position, entity);
            if (getClosestMovementNodeWithDistance(registry, entity_pos.*)) |closest| {
                registry.replace(entity, closest);
            } else |_| {
                // No movement nodes found, leave unchanged
            }
        }
    }
};
