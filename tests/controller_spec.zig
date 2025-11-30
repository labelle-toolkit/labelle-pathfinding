const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");
const ecs = @import("ecs");

const expect = zspec.expect;
const Position = pathfinding.Position;
const Entity = pathfinding.Entity;
const Registry = pathfinding.Registry;
const MovementNode = pathfinding.MovementNode;
const ClosestMovementNode = pathfinding.ClosestMovementNode;
const MovementNodeController = pathfinding.MovementNodeController;

pub const MovementNodeControllerSpec = struct {
    var registry: Registry = undefined;

    test "tests:before" {
        registry = Registry.init(std.testing.allocator);
    }

    test "tests:after" {
        registry.deinit();
    }

    pub const @"finding closest node" = struct {
        test "tests:before" {
            // Create movement nodes at different positions
            const node1 = registry.create();
            registry.add(node1, MovementNode{});
            registry.add(node1, Position{ .x = 10, .y = 10 });

            const node2 = registry.create();
            registry.add(node2, MovementNode{});
            registry.add(node2, Position{ .x = 100, .y = 100 });

            const node3 = registry.create();
            registry.add(node3, MovementNode{});
            registry.add(node3, Position{ .x = 5, .y = 5 });
        }

        test "returns the closest node to position" {
            const pos = Position{ .x = 0, .y = 0 };

            const result = try MovementNodeController.getClosestMovementNode(
                &registry,
                pos,
            );

            // Node at (5,5) is closest to origin
            const result_pos = registry.get(Position, result);
            try expect.equal(result_pos.x, 5);
            try expect.equal(result_pos.y, 5);
        }

        test "returns closest node with distance" {
            const pos = Position{ .x = 0, .y = 0 };

            const result = try MovementNodeController.getClosestMovementNodeWithDistance(
                &registry,
                pos,
            );

            // Distance from (0,0) to (5,5) is sqrt(50) ≈ 7.07
            try std.testing.expectApproxEqAbs(@as(f32, 7.07), result.distance, 0.1);
        }
    };

    pub const @"error handling" = struct {
        test "tests:before" {
            // Clear all entities for this test group
            var view = registry.view(.{ MovementNode, Position }, .{});
            var iter = view.entityIterator();

            // Collect entities to destroy
            var entities_to_destroy: [64]Entity = undefined;
            var count: usize = 0;

            while (iter.next()) |entity| {
                if (count < 64) {
                    entities_to_destroy[count] = entity;
                    count += 1;
                }
            }

            for (entities_to_destroy[0..count]) |entity| {
                registry.destroy(entity);
            }
        }

        test "returns error when no movement nodes exist" {
            const pos = Position{ .x = 0, .y = 0 };

            const result = MovementNodeController.getClosestMovementNode(
                &registry,
                pos,
            );

            try std.testing.expectError(error.NoMovementNodes, result);
        }
    };

    pub const @"single node" = struct {
        test "tests:before" {
            // Clear existing movement nodes
            var view = registry.view(.{ MovementNode, Position }, .{});
            var iter = view.entityIterator();

            var entities_to_destroy: [64]Entity = undefined;
            var count: usize = 0;

            while (iter.next()) |entity| {
                if (count < 64) {
                    entities_to_destroy[count] = entity;
                    count += 1;
                }
            }

            for (entities_to_destroy[0..count]) |entity| {
                registry.destroy(entity);
            }

            // Add just one node
            const node = registry.create();
            registry.add(node, MovementNode{});
            registry.add(node, Position{ .x = 50, .y = 50 });
        }

        test "handles single node" {
            const pos = Position{ .x = 0, .y = 0 };

            const result = try MovementNodeController.getClosestMovementNode(
                &registry,
                pos,
            );

            const result_pos = registry.get(Position, result);
            try expect.equal(result_pos.x, 50);
            try expect.equal(result_pos.y, 50);
        }
    };

    pub const @"batch update" = struct {
        test "tests:before" {
            // Clear existing movement nodes
            var view = registry.view(.{ MovementNode, Position }, .{});
            var iter = view.entityIterator();

            var entities_to_destroy: [64]Entity = undefined;
            var count: usize = 0;

            while (iter.next()) |entity| {
                if (count < 64) {
                    entities_to_destroy[count] = entity;
                    count += 1;
                }
            }

            for (entities_to_destroy[0..count]) |entity| {
                registry.destroy(entity);
            }

            // Create movement nodes
            const node1 = registry.create();
            registry.add(node1, MovementNode{});
            registry.add(node1, Position{ .x = 0, .y = 0 });

            const node2 = registry.create();
            registry.add(node2, MovementNode{});
            registry.add(node2, Position{ .x = 100, .y = 100 });

            // Create an entity that tracks closest node
            const entity = registry.create();
            registry.add(entity, Position{ .x = 10, .y = 10 });
            registry.add(entity, ClosestMovementNode{});
        }

        test "updateAllClosestNodes updates entities" {
            MovementNodeController.updateAllClosestNodes(&registry);

            // The entity at (10,10) should have closest node at (0,0)
            var view = registry.view(.{ Position, ClosestMovementNode }, .{});
            var iter = view.entityIterator();

            while (iter.next()) |entity| {
                const closest = registry.get(ClosestMovementNode, entity);
                // Distance from (10,10) to (0,0) is sqrt(200) ≈ 14.14
                try std.testing.expectApproxEqAbs(@as(f32, 14.14), closest.distance, 0.1);
            }
        }
    };
};
