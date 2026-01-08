const std = @import("std");
const zspec = @import("zspec");
const pathfinding = @import("labelle_pathfinding");
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
            try expect.equal(astar.base.last_key, 0);
            try expect.equal(astar.base.size, 100);
        }

        test "defaults to euclidean heuristic" {
            try expect.equal(astar.base.heuristic_type, .euclidean);
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
            try astar.addEdge(0, 1, 1);
            try astar.addEdge(1, 2, 1);
            try astar.addEdge(2, 3, 1);
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
            try astar.addEdgeWithMapping(100, 200, 1);
            try astar.addEdgeWithMapping(200, 300, 1);
            try astar.addEdgeWithMapping(300, 400, 1);
        }

        test "maps entity IDs to internal indices" {
            try expect.toBeTrue(astar.base.ids.contains(100));
            try expect.toBeTrue(astar.base.ids.contains(200));
            try expect.toBeTrue(astar.base.ids.contains(300));
            try expect.toBeTrue(astar.base.ids.contains(400));
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
            try astar.addEdge(0, 1, 5);
            try astar.addEdge(1, 3, 3);
            try astar.addEdge(0, 2, 2);
            try astar.addEdge(2, 3, 2);
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
            try astar.addEdge(0, 1, 1);
            try astar.addEdge(0, 2, 1);
            try astar.addEdge(1, 3, 1);
            try astar.addEdge(2, 3, 1);
        }

        test "can set euclidean heuristic" {
            astar.setHeuristic(.euclidean);
            try expect.equal(astar.base.heuristic_type, .euclidean);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set manhattan heuristic" {
            astar.setHeuristic(.manhattan);
            try expect.equal(astar.base.heuristic_type, .manhattan);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set chebyshev heuristic" {
            astar.setHeuristic(.chebyshev);
            try expect.equal(astar.base.heuristic_type, .chebyshev);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set octile heuristic" {
            astar.setHeuristic(.octile);
            try expect.equal(astar.base.heuristic_type, .octile);
            try expect.equal(astar.value(0, 3), 2);
        }

        test "can set zero heuristic (Dijkstra)" {
            astar.setHeuristic(.zero);
            try expect.equal(astar.base.heuristic_type, .zero);
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
            try astar.addEdge(0, 1, 1);
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
            try astar.addEdgeWithMapping(10, 20, 1);
        }

        test "resets the graph when clean is called" {
            try expect.toBeTrue(astar.hasPathWithMapping(10, 20));

            // Clean and reconfigure
            try astar.clean();

            // Old mappings should be gone
            try expect.toBeFalse(astar.base.ids.contains(10));
            try expect.toBeFalse(astar.base.ids.contains(20));
            try expect.equal(astar.base.last_key, 0);
        }
    };
};

pub const AStarWithHooksSpec = struct {
    const hooks = pathfinding.hooks;

    pub const @"hook emission" = struct {
        test "emits path_found hook" {
            const TestHooks = struct {
                var path_found_called: bool = false;
                var last_cost: u64 = 0;

                pub fn path_found(payload: hooks.HookPayload) void {
                    const info = payload.path_found;
                    path_found_called = true;
                    last_cost = info.cost;
                }
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);
            var astar_hooks = pathfinding.AStarWithHooks(Dispatcher).init(std.testing.allocator);
            defer astar_hooks.deinit();

            astar_hooks.resize(3);
            try astar_hooks.clean();

            try astar_hooks.addEdge(0, 1, 10);
            try astar_hooks.addEdge(1, 2, 5);

            TestHooks.path_found_called = false;
            TestHooks.last_cost = 0;

            var path = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path.deinit();

            const cost = try astar_hooks.findPath(0, 2, &path);

            try expect.toBeTrue(TestHooks.path_found_called);
            try expect.equal(TestHooks.last_cost, 15);
            try expect.equal(cost.?, 15);
        }

        test "emits no_path_found hook" {
            const TestHooks = struct {
                var no_path_found_called: bool = false;

                pub fn no_path_found(_: hooks.HookPayload) void {
                    no_path_found_called = true;
                }
            };

            const Dispatcher = hooks.HookDispatcher(TestHooks);
            var astar_hooks = pathfinding.AStarWithHooks(Dispatcher).init(std.testing.allocator);
            defer astar_hooks.deinit();

            astar_hooks.resize(3);
            try astar_hooks.clean();

            // No edges - no path possible
            try astar_hooks.addEdge(0, 1, 10);
            // Node 2 is isolated

            TestHooks.no_path_found_called = false;

            var path = std.array_list.Managed(u32).init(std.testing.allocator);
            defer path.deinit();

            const cost = try astar_hooks.findPath(0, 2, &path);

            try expect.toBeTrue(TestHooks.no_path_found_called);
            try expect.toBeNull(cost);
        }

        // Note: node_visited hooks are not emitted by the zig-utils A* implementation
        // since it doesn't track individual node visits in its current form.
        // If needed, this could be added in a future enhancement.
    };
};
