const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");
const zig_ecs = @import("zig_ecs");

const expect = zspec.expect;
const Entity = pathfinding.Entity;
const Registry = pathfinding.Registry;

pub const WithPathSpec = struct {
    var with_path: pathfinding.WithPath = undefined;
    var registry: Registry = undefined;
    var test_entities: [3]Entity = undefined;

    test "tests:before" {
        registry = Registry.init(std.testing.allocator);
        with_path = pathfinding.WithPath.init(std.testing.allocator);

        // Create test entities for use in tests
        test_entities[0] = registry.create();
        test_entities[1] = registry.create();
        test_entities[2] = registry.create();
    }

    test "tests:after" {
        with_path.deinit();
        registry.deinit();
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
            try with_path.append(test_entities[0]);
            try with_path.append(test_entities[1]);
            try with_path.append(test_entities[2]);
        }

        test "tests:after" {
            with_path.clear();
        }

        test "is not empty" {
            try expect.toBeFalse(with_path.isEmpty());
        }

        test "peekFront returns first node without removing" {
            try expect.equal(with_path.peekFront().?, test_entities[0]);
            try expect.equal(with_path.peekFront().?, test_entities[0]);
        }
    };

    pub const @"popFront behavior" = struct {
        test "tests:before" {
            try with_path.append(test_entities[0]);
            try with_path.append(test_entities[1]);
            try with_path.append(test_entities[2]);
        }

        test "tests:after" {
            with_path.clear();
        }

        test "returns nodes in FIFO order" {
            try expect.equal(with_path.popFront().?, test_entities[0]);
            try expect.equal(with_path.popFront().?, test_entities[1]);
            try expect.equal(with_path.popFront().?, test_entities[2]);
            try expect.toBeNull(with_path.popFront());
        }
    };

    pub const @"clear behavior" = struct {
        test "tests:before" {
            try with_path.append(test_entities[0]);
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
        var registry: Registry = undefined;
        var entities: [4]Entity = undefined;

        test "tests:before" {
            registry = Registry.init(std.testing.allocator);
            entities[0] = registry.create();
            entities[1] = registry.create();
            entities[2] = registry.create();
            entities[3] = registry.create();
        }

        test "tests:after" {
            registry.deinit();
        }

        test "stores directional connections" {
            const node = pathfinding.MovementNode{
                .left_entt = entities[0],
                .right_entt = entities[1],
                .up_entt = entities[2],
                .down_entt = entities[3],
            };
            try expect.equal(node.left_entt.?, entities[0]);
            try expect.equal(node.right_entt.?, entities[1]);
            try expect.equal(node.up_entt.?, entities[2]);
            try expect.equal(node.down_entt.?, entities[3]);
        }
    };
};

pub const ClosestMovementNodeSpec = struct {
    var registry: Registry = undefined;
    var test_entity: Entity = undefined;

    test "tests:before" {
        registry = Registry.init(std.testing.allocator);
        test_entity = registry.create();
    }

    test "tests:after" {
        registry.deinit();
    }

    test "stores node entity and distance" {
        const closest = pathfinding.ClosestMovementNode{
            .node_entt = test_entity,
            .distance = 15.5,
        };
        try expect.equal(closest.node_entt.?, test_entity);
        try expect.equal(closest.distance, 15.5);
    }

    test "has default values" {
        const closest = pathfinding.ClosestMovementNode{};
        try expect.toBeNull(closest.node_entt);
        try expect.equal(closest.distance, 0);
    }
};

pub const MovingTowardsSpec = struct {
    var registry: Registry = undefined;
    var test_entity: Entity = undefined;

    test "tests:before" {
        registry = Registry.init(std.testing.allocator);
        test_entity = registry.create();
    }

    test "tests:after" {
        registry.deinit();
    }

    test "stores movement target and speed" {
        const moving = pathfinding.MovingTowards{
            .target_x = 100.5,
            .target_y = 200.5,
            .closest_node_entt = test_entity,
            .speed = 25.0,
        };
        try expect.equal(moving.target_x, 100.5);
        try expect.equal(moving.target_y, 200.5);
        try expect.equal(moving.closest_node_entt.?, test_entity);
        try expect.equal(moving.speed, 25.0);
    }

    test "has default values" {
        const moving = pathfinding.MovingTowards{};
        try expect.equal(moving.target_x, 0);
        try expect.equal(moving.target_y, 0);
        try expect.toBeNull(moving.closest_node_entt);
        try expect.equal(moving.speed, 10);
    }
};
