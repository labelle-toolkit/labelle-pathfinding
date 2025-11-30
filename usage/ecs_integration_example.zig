//! ECS Integration Usage Example
//!
//! Demonstrates using the exported ecs module alongside pathfinding.
//! This example shows that consumers can import both modules without
//! module collisions, enabling direct access to zig-ecs features like
//! Registry, views, and component iteration.

const std = @import("std");
const pathfinding = @import("pathfinding");
const ecs = @import("ecs");

const print = std.debug.print;

// Custom game components (not from pathfinding)
const Health = struct {
    current: f32 = 100,
    max: f32 = 100,
};

const Velocity = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n=== ECS Integration Example ===\n\n", .{});

    // Create registry using the exported ecs module directly
    // This is the same ecs instance used internally by pathfinding
    var registry = ecs.Registry.init(allocator);
    defer registry.deinit();

    print("1. Creating entities with pathfinding and custom components...\n\n", .{});

    // Create movement nodes (pathfinding components)
    const node_a = registry.create();
    registry.add(node_a, pathfinding.MovementNode{});
    registry.add(node_a, pathfinding.Position{ .x = 0, .y = 0 });
    print("   Node A: position (0, 0)\n", .{});

    const node_b = registry.create();
    registry.add(node_b, pathfinding.MovementNode{ .left_entt = node_a });
    registry.add(node_b, pathfinding.Position{ .x = 10, .y = 0 });
    print("   Node B: position (10, 0), connected left to A\n", .{});

    const node_c = registry.create();
    registry.add(node_c, pathfinding.MovementNode{ .left_entt = node_b });
    registry.add(node_c, pathfinding.Position{ .x = 20, .y = 0 });
    print("   Node C: position (20, 0), connected left to B\n", .{});

    // Create a player entity with both pathfinding and custom components
    const player = registry.create();
    registry.add(player, pathfinding.Position{ .x = 5, .y = 0 });
    registry.add(player, pathfinding.ClosestMovementNode{});
    registry.add(player, Health{ .current = 100, .max = 100 });
    registry.add(player, Velocity{ .x = 1, .y = 0 });
    print("   Player: position (5, 0), with Health and Velocity\n\n", .{});

    // Use pathfinding's MovementNodeController with the registry
    print("2. Using pathfinding controller to find closest node...\n\n", .{});

    const player_pos = registry.get(pathfinding.Position, player);
    const closest = try pathfinding.MovementNodeController.getClosestMovementNodeWithDistance(
        &registry,
        player_pos.*,
    );

    const closest_pos = registry.get(pathfinding.Position, closest.node_entt.?);
    print("   Player at ({d}, {d})\n", .{ player_pos.x, player_pos.y });
    print("   Closest node at ({d}, {d}), distance: {d:.2}\n\n", .{
        closest_pos.x,
        closest_pos.y,
        closest.distance,
    });

    // Use ecs views directly (feature not available through pathfinding re-exports)
    print("3. Using ecs.Registry views directly...\n\n", .{});

    // Iterate all entities with Position and Health (player only)
    var health_view = registry.view(.{ pathfinding.Position, Health }, .{});
    var health_iter = health_view.entityIterator();

    print("   Entities with Position + Health:\n", .{});
    while (health_iter.next()) |entity| {
        const pos = registry.get(pathfinding.Position, entity);
        const health = registry.get(Health, entity);
        print("   - Entity at ({d}, {d}): HP {d}/{d}\n", .{
            pos.x,
            pos.y,
            health.current,
            health.max,
        });
    }

    // Iterate all movement nodes
    var node_view = registry.view(.{ pathfinding.MovementNode, pathfinding.Position }, .{});
    var node_iter = node_view.entityIterator();

    print("\n   Movement nodes in registry:\n", .{});
    var node_count: u32 = 0;
    while (node_iter.next()) |entity| {
        const pos = registry.get(pathfinding.Position, entity);
        const node = registry.get(pathfinding.MovementNode, entity);
        const has_left = node.left_entt != null;
        print("   - Node at ({d}, {d}), has left connection: {}\n", .{
            pos.x,
            pos.y,
            has_left,
        });
        node_count += 1;
    }
    print("   Total movement nodes: {d}\n\n", .{node_count});

    // Demonstrate batch update using controller
    print("4. Batch updating closest nodes for all tracking entities...\n\n", .{});

    pathfinding.MovementNodeController.updateAllClosestNodes(&registry);

    const updated_closest = registry.get(pathfinding.ClosestMovementNode, player);
    print("   Player's closest node updated: distance = {d:.2}\n\n", .{updated_closest.distance});

    print("=== ECS Integration Example Complete ===\n\n", .{});
    print("This example demonstrates that both 'pathfinding' and 'ecs' modules\n", .{});
    print("can be imported and used together without module collisions.\n\n", .{});
}
