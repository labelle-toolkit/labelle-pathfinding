const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");

const expect = zspec.expect;

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
