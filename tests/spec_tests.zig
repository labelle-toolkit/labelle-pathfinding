const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");
const labelle = @import("labelle");

const expect = zspec.expect;
const Position = labelle.Position;

test {
    zspec.runAll(@This());
}

pub const FloydWarshallSpec = struct {
    var fw: pathfinding.FloydWarshall = undefined;

    test "tests:before" {
        fw = pathfinding.FloydWarshall.init(std.testing.allocator);
    }

    test "tests:after" {
        fw.deinit();
    }

    pub const @"initialization" = struct {
        test "creates with default size" {
            try expect.equal(fw.last_key, 0);
            try expect.equal(fw.size, 100);
        }
    };

    pub const @"simple linear graph" = struct {
        test "tests:before" {
            fw.resize(3);
            try fw.clean();
            // Create graph: 0 -> 1 -> 2
            fw.addEdge(0, 1, 1);
            fw.addEdge(1, 2, 1);
            fw.generate();
        }

        test "finds path between connected nodes" {
            try expect.toBeTrue(fw.hasPath(0, 1));
            try expect.toBeTrue(fw.hasPath(1, 2));
            try expect.toBeTrue(fw.hasPath(0, 2));
        }

        test "calculates correct distances" {
            try expect.equal(fw.value(0, 1), 1);
            try expect.equal(fw.value(1, 2), 1);
            try expect.equal(fw.value(0, 2), 2);
        }

        test "returns INF for unreachable nodes" {
            try expect.toBeFalse(fw.hasPath(2, 0));
        }

        test "returns zero for self-loops" {
            try expect.equal(fw.value(0, 0), 0);
            try expect.equal(fw.value(1, 1), 0);
        }
    };

    pub const @"entity ID mapping" = struct {
        test "tests:before" {
            fw.resize(4);
            try fw.clean();
            // Use entity IDs: 100 -> 200 -> 300 -> 400
            fw.addEdgeWithMapping(100, 200, 1);
            fw.addEdgeWithMapping(200, 300, 1);
            fw.addEdgeWithMapping(300, 400, 1);
            fw.generate();
        }

        test "maps entity IDs to internal indices" {
            try expect.toBeTrue(fw.ids.contains(100));
            try expect.toBeTrue(fw.ids.contains(200));
            try expect.toBeTrue(fw.ids.contains(300));
            try expect.toBeTrue(fw.ids.contains(400));
        }

        test "finds paths using entity IDs" {
            try expect.toBeTrue(fw.hasPathWithMapping(100, 400));
            try expect.toBeTrue(fw.hasPathWithMapping(100, 200));
            try expect.toBeTrue(fw.hasPathWithMapping(200, 300));
        }

        test "calculates distances using entity IDs" {
            try expect.equal(fw.valueWithMapping(100, 200), 1);
            try expect.equal(fw.valueWithMapping(100, 300), 2);
            try expect.equal(fw.valueWithMapping(100, 400), 3);
        }

        test "returns correct next hop in path" {
            try expect.equal(fw.nextWithMapping(100, 400), 200);
            try expect.equal(fw.nextWithMapping(200, 400), 300);
            try expect.equal(fw.nextWithMapping(300, 400), 400);
        }

        test "reconstructs full path" {
            var path_list = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path_list.deinit();

            try fw.setPathWithMapping(&path_list, 100, 400);

            try expect.equal(path_list.items.len, 4);
            try expect.equal(path_list.items[0], 100);
            try expect.equal(path_list.items[1], 200);
            try expect.equal(path_list.items[2], 300);
            try expect.equal(path_list.items[3], 400);
        }
    };

    pub const @"weighted edges" = struct {
        test "tests:before" {
            fw.resize(4);
            try fw.clean();
            // Create graph with different weights:
            // 0 --5--> 1 --3--> 3
            // 0 --2--> 2 --2--> 3
            fw.addEdge(0, 1, 5);
            fw.addEdge(1, 3, 3);
            fw.addEdge(0, 2, 2);
            fw.addEdge(2, 3, 2);
            fw.generate();
        }

        test "finds shortest path through lower weight route" {
            // 0 -> 2 -> 3 = 4 is shorter than 0 -> 1 -> 3 = 8
            try expect.equal(fw.value(0, 3), 4);
        }

        test "next hop follows shortest path" {
            // Should go through node 2, not node 1
            try expect.equal(fw.next(0, 3), 2);
        }
    };

    pub const @"clean and reset" = struct {
        test "tests:before" {
            fw.resize(3);
            try fw.clean();
            fw.addEdgeWithMapping(10, 20, 1);
            fw.generate();
        }

        test "resets the graph when clean is called" {
            try expect.toBeTrue(fw.hasPathWithMapping(10, 20));

            // Clean and reconfigure
            try fw.clean();

            // Old mappings should be gone
            try expect.toBeFalse(fw.ids.contains(10));
            try expect.toBeFalse(fw.ids.contains(20));
            try expect.equal(fw.last_key, 0);
        }
    };
};

pub const WithPathSpec = struct {
    var with_path: pathfinding.WithPath = undefined;

    test "tests:before" {
        with_path = pathfinding.WithPath.init(std.testing.allocator);
    }

    test "tests:after" {
        with_path.deinit();
    }

    pub const @"initialization" = struct {
        test "starts empty" {
            try expect.toBeTrue(with_path.isEmpty());
        }

        test "peekFront returns null when empty" {
            try expect.toBeNull(with_path.peekFront());
        }

        test "popFront returns null when empty" {
            try expect.toBeNull(with_path.popFront());
        }
    };

    pub const @"with nodes added" = struct {
        test "tests:before" {
            try with_path.append(10);
            try with_path.append(20);
            try with_path.append(30);
        }

        test "tests:after" {
            with_path.clear();
        }

        test "is not empty" {
            try expect.toBeFalse(with_path.isEmpty());
        }

        test "peekFront returns first node without removing" {
            try expect.equal(with_path.peekFront().?, 10);
            try expect.equal(with_path.peekFront().?, 10);
        }
    };

    pub const @"popFront behavior" = struct {
        test "tests:before" {
            try with_path.append(1);
            try with_path.append(2);
            try with_path.append(3);
        }

        test "tests:after" {
            with_path.clear();
        }

        test "returns nodes in FIFO order" {
            try expect.equal(with_path.popFront().?, 1);
            try expect.equal(with_path.popFront().?, 2);
            try expect.equal(with_path.popFront().?, 3);
            try expect.toBeNull(with_path.popFront());
        }
    };

    pub const @"clear behavior" = struct {
        test "tests:before" {
            try with_path.append(100);
        }

        test "tests:after" {
            with_path.clear();
        }

        test "removes all nodes" {
            with_path.clear();
            try expect.toBeTrue(with_path.isEmpty());
        }
    };
};

pub const MovementNodeSpec = struct {
    pub const @"default values" = struct {
        test "all directions are null by default" {
            const node = pathfinding.MovementNode{};
            try expect.toBeNull(node.left_entt);
            try expect.toBeNull(node.right_entt);
            try expect.toBeNull(node.up_entt);
            try expect.toBeNull(node.down_entt);
        }
    };

    pub const @"with connections" = struct {
        test "stores directional connections" {
            const node = pathfinding.MovementNode{
                .left_entt = 1,
                .right_entt = 2,
                .up_entt = 3,
                .down_entt = 4,
            };
            try expect.equal(node.left_entt.?, 1);
            try expect.equal(node.right_entt.?, 2);
            try expect.equal(node.up_entt.?, 3);
            try expect.equal(node.down_entt.?, 4);
        }
    };
};

pub const ClosestMovementNodeSpec = struct {
    test "stores node entity and distance" {
        const closest = pathfinding.ClosestMovementNode{
            .node_entt = 42,
            .distance = 15.5,
        };
        try expect.equal(closest.node_entt, 42);
        try expect.equal(closest.distance, 15.5);
    }

    test "has default values" {
        const closest = pathfinding.ClosestMovementNode{};
        try expect.equal(closest.node_entt, 0);
        try expect.equal(closest.distance, 0);
    }
};

pub const MovingTowardsSpec = struct {
    test "stores movement target and speed" {
        const moving = pathfinding.MovingTowards{
            .target_x = 100.5,
            .target_y = 200.5,
            .closest_node_entt = 5,
            .speed = 25.0,
        };
        try expect.equal(moving.target_x, 100.5);
        try expect.equal(moving.target_y, 200.5);
        try expect.equal(moving.closest_node_entt, 5);
        try expect.equal(moving.speed, 25.0);
    }

    test "has default values" {
        const moving = pathfinding.MovingTowards{};
        try expect.equal(moving.target_x, 0);
        try expect.equal(moving.target_y, 0);
        try expect.equal(moving.closest_node_entt, 0);
        try expect.equal(moving.speed, 10);
    }
};

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
