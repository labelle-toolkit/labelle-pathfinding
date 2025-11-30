const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("pathfinding");
const zig_utils = @import("zig_utils");

const expect = zspec.expect;
const Position = zig_utils.Vector2;

pub const AStarSpec = struct {
    var astar: pathfinding.AStar = undefined;

    test "tests:before" {
        astar = pathfinding.AStar.init(std.testing.allocator);
    }

    test "tests:after" {
        astar.deinit();
    }

    pub const @"initialization" = struct {
        test "creates with default size" {
            try expect.equal(astar.last_key, 0);
            try expect.equal(astar.size, 100);
        }

        test "defaults to euclidean heuristic" {
            try expect.equal(astar.heuristic_type, .euclidean);
        }
    };

    pub const @"basic pathfinding" = struct {
        test "tests:before" {
            astar.resize(4);
            try astar.clean();

            // Set positions for heuristic
            try astar.setNodePosition(0, .{ .x = 0, .y = 0 });
            try astar.setNodePosition(1, .{ .x = 1, .y = 0 });
            try astar.setNodePosition(2, .{ .x = 2, .y = 0 });
            try astar.setNodePosition(3, .{ .x = 3, .y = 0 });

            // Create graph: 0 -> 1 -> 2 -> 3
            astar.addEdge(0, 1, 1);
            astar.addEdge(1, 2, 1);
            astar.addEdge(2, 3, 1);
        }

        test "finds path between connected nodes" {
            try expect.toBeTrue(astar.hasPath(0, 1));
            try expect.toBeTrue(astar.hasPath(1, 2));
            try expect.toBeTrue(astar.hasPath(0, 3));
        }

        test "calculates correct distances" {
            try expect.equal(astar.value(0, 1), 1);
            try expect.equal(astar.value(1, 2), 1);
            try expect.equal(astar.value(0, 3), 3);
        }

        test "returns INF for unreachable nodes" {
            try expect.toBeFalse(astar.hasPath(3, 0));
        }

        test "returns zero for self-loops" {
            try expect.equal(astar.value(0, 0), 0);
            try expect.equal(astar.value(1, 1), 0);
        }
    };

    pub const @"entity ID mapping" = struct {
        test "tests:before" {
            astar.resize(4);
            try astar.clean();
            // Use entity IDs: 100 -> 200 -> 300 -> 400
            astar.addEdgeWithMapping(100, 200, 1);
            astar.addEdgeWithMapping(200, 300, 1);
            astar.addEdgeWithMapping(300, 400, 1);
        }

        test "maps entity IDs to internal indices" {
            try expect.toBeTrue(astar.ids.contains(100));
            try expect.toBeTrue(astar.ids.contains(200));
            try expect.toBeTrue(astar.ids.contains(300));
            try expect.toBeTrue(astar.ids.contains(400));
        }

        test "finds paths using entity IDs" {
            try expect.toBeTrue(astar.hasPathWithMapping(100, 400));
            try expect.toBeTrue(astar.hasPathWithMapping(100, 200));
            try expect.toBeTrue(astar.hasPathWithMapping(200, 300));
        }

        test "calculates distances using entity IDs" {
            try expect.equal(astar.valueWithMapping(100, 200), 1);
            try expect.equal(astar.valueWithMapping(100, 300), 2);
            try expect.equal(astar.valueWithMapping(100, 400), 3);
        }

        test "returns correct next hop in path" {
            try expect.equal(astar.nextWithMapping(100, 400), 200);
            try expect.equal(astar.nextWithMapping(200, 400), 300);
            try expect.equal(astar.nextWithMapping(300, 400), 400);
        }

        test "reconstructs full path" {
            var path_list = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path_list.deinit();

            try astar.setPathWithMapping(&path_list, 100, 400);

            try expect.equal(path_list.items.len, 4);
            try expect.equal(path_list.items[0], 100);
            try expect.equal(path_list.items[1], 200);
            try expect.equal(path_list.items[2], 300);
            try expect.equal(path_list.items[3], 400);
        }
    };

    pub const @"weighted edges" = struct {
        test "tests:before" {
            astar.resize(4);
            try astar.clean();
            // Create graph with different weights:
            // 0 --5--> 1 --3--> 3
            // 0 --2--> 2 --2--> 3
            astar.addEdge(0, 1, 5);
            astar.addEdge(1, 3, 3);
            astar.addEdge(0, 2, 2);
            astar.addEdge(2, 3, 2);
        }

        test "finds shortest path through lower weight route" {
            // 0 -> 2 -> 3 = 4 is shorter than 0 -> 1 -> 3 = 8
            try expect.equal(astar.value(0, 3), 4);
        }

        test "next hop follows shortest path" {
            // Should go through node 2, not node 1
            try expect.equal(astar.next(0, 3), 2);
        }
    };

    pub const @"heuristic selection" = struct {
        test "tests:before" {
            astar.resize(4);
            try astar.clean();

            // Grid positions
            try astar.setNodePosition(0, .{ .x = 0, .y = 0 });
            try astar.setNodePosition(1, .{ .x = 1, .y = 0 });
            try astar.setNodePosition(2, .{ .x = 0, .y = 1 });
            try astar.setNodePosition(3, .{ .x = 1, .y = 1 });

            // 4-directional grid
            astar.addEdge(0, 1, 1);
            astar.addEdge(0, 2, 1);
            astar.addEdge(1, 3, 1);
            astar.addEdge(2, 3, 1);
        }

        test "can set euclidean heuristic" {
            astar.setHeuristic(.euclidean);
            try expect.equal(astar.heuristic_type, .euclidean);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set manhattan heuristic" {
            astar.setHeuristic(.manhattan);
            try expect.equal(astar.heuristic_type, .manhattan);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set chebyshev heuristic" {
            astar.setHeuristic(.chebyshev);
            try expect.equal(astar.heuristic_type, .chebyshev);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set octile heuristic" {
            astar.setHeuristic(.octile);
            try expect.equal(astar.heuristic_type, .octile);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set zero heuristic (Dijkstra)" {
            astar.setHeuristic(.zero);
            try expect.equal(astar.heuristic_type, .zero);
            try expect.equal(astar.value(0, 3), 2);
        }
    };

    pub const @"edge cases" = struct {
        test "tests:before" {
            astar.resize(3);
            try astar.clean();
        }

        test "same source and destination returns zero cost" {
            var path = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path.deinit();

            const cost = try astar.findPath(0, 0, &path);

            try expect.toBeTrue(cost != null);
            try expect.equal(cost.?, 0);
            try expect.equal(path.items.len, 1);
        }

        test "no path returns null" {
            // Disconnected graph
            astar.addEdge(0, 1, 1);
            // No edge to 2

            try expect.toBeFalse(astar.hasPath(0, 2));
        }

        test "invalid source returns null" {
            var path = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path.deinit();

            const cost = try astar.findPath(99, 0, &path);
            try expect.toBeNull(cost);
        }

        test "invalid destination returns null" {
            var path = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path.deinit();

            const cost = try astar.findPath(0, 99, &path);
            try expect.toBeNull(cost);
        }
    };

    pub const @"clean and reset" = struct {
        test "tests:before" {
            astar.resize(3);
            try astar.clean();
            astar.addEdgeWithMapping(10, 20, 1);
        }

        test "resets the graph when clean is called" {
            try expect.toBeTrue(astar.hasPathWithMapping(10, 20));

            // Clean and reconfigure
            try astar.clean();

            // Old mappings should be gone
            try expect.toBeFalse(astar.ids.contains(10));
            try expect.toBeFalse(astar.ids.contains(20));
            try expect.equal(astar.last_key, 0);
        }
    };
};
